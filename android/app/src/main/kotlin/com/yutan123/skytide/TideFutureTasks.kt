package com.yutan123.skytide

import android.content.Context
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import java.util.Calendar

/** Executes the existing schedule_tasks queue with the shared Dart chat pipeline. */
object TideFutureTasks {
    private const val LEASE_MS = 6 * 60_000L

    fun reconcile(context: Context) {
        val tasks = TideStore.open(context).use { db ->
            val now = System.currentTimeMillis()
            db.execSQL("UPDATE schedule_tasks SET status='pending',locked_at=NULL,retry_at=?,last_error='Execution lease expired' WHERE status='running' AND (locked_at IS NULL OR locked_at<=?)",
                arrayOf(now, now - LEASE_MS))
            db.execSQL("UPDATE background_tasks SET enabled=0 WHERE task_type='FUTURE_TASK' AND NOT EXISTS (SELECT 1 FROM schedule_tasks s WHERE s.id=background_tasks.task_id AND s.status IN ('pending','running') AND COALESCE(s.is_done,0)=0)")
            TideStore.rows(db, "SELECT * FROM schedule_tasks WHERE status='pending' AND COALESCE(is_done,0)=0")
        }
        for (task in tasks) {
            val runAt = task.optLong("run_at", task.optLong("time"))
            if (runAt <= 0) continue
            TideMasterScheduler.registerTask(context, task.getString("id"), "FUTURE_TASK",
                task.optString("bot_id"), maxOf(runAt, task.optLong("retry_at")), false,
                JSONObject().put("title", task.optString("title")))
        }
    }

    suspend fun execute(context: Context, taskId: String, executionId: String) {
        val now = System.currentTimeMillis()
        val task = TideStore.open(context).use { db ->
            TideStore.transaction(db) {
                val row = TideStore.rows(db, "SELECT * FROM schedule_tasks WHERE id=? AND status='pending' AND run_at<=? AND (retry_at IS NULL OR retry_at<=?) AND COALESCE(is_done,0)=0",
                    taskId, now.toString(), now.toString()).firstOrNull() ?: return@transaction null
                db.execSQL("UPDATE schedule_tasks SET status='running',locked_at=? WHERE id=?", arrayOf(now, taskId))
                row
            }
        } ?: throw IllegalStateException("Future task is not runnable")
        val started = android.os.SystemClock.elapsedRealtime()
        try {
            val botId = task.getString("bot_id")
            check(TideConfigReader.isBotEnabled(context, botId)) { "Bot is disabled or not found" }
            val prompt = task.optString("prompt").ifBlank { task.optString("note") }
            check(prompt.isNotBlank()) { "Empty task prompt" }
            val response = TideProactiveReplyEngine.requireReply(context,
                TideProactiveReplyEngine.generateFuture(context, botId, prompt))
            TideStore.open(context).use { db ->
                TideStore.transaction(db) {
                    val lease = TideStore.rows(db, "SELECT locked_at,status FROM schedule_tasks WHERE id=?", taskId).firstOrNull()
                    check(lease?.optString("status") == "running" && lease.optLong("locked_at") == now) { "Future task lease expired" }
                    if (response.optBoolean("silent")) {
                        db.execSQL("UPDATE background_task_executions SET status='success',finished_at=? WHERE execution_id=? AND status='running'",
                            arrayOf(System.currentTimeMillis(), executionId))
                    } else {
                        TideTaskExecutor.publishMessage(db, botId, taskId, response.optString("reply"), executionId, response)
                    }
                    if (task.optString("frequency") == "daily") {
                        val next = Calendar.getInstance().apply { timeInMillis = task.getLong("run_at") }
                        do { next.add(Calendar.DAY_OF_MONTH, 1) } while (next.timeInMillis <= System.currentTimeMillis())
                        db.execSQL("UPDATE schedule_tasks SET run_at=?,status='pending',attempts=0,last_error=NULL,retry_at=NULL,locked_at=NULL WHERE id=?",
                            arrayOf(next.timeInMillis, taskId))
                    } else {
                        db.execSQL("DELETE FROM schedule_tasks WHERE id=?", arrayOf(taskId))
                    }
                    db.execSQL("UPDATE background_tasks SET enabled=0,updated_at=? WHERE task_id=?", arrayOf(System.currentTimeMillis(), taskId))
                }
            }
            runCatching { TideBackgroundLog.add(context,
                "未来任务完成：task=$taskId，execution=$executionId，耗时=${android.os.SystemClock.elapsedRealtime() - started}ms，silent=${response.optBoolean("silent")}" +
                    if (TideBackgroundLog.enabled(context)) "\n响应：${response.optString("reply")}" else "",
                "FUTURE_TASK_RESPONSE") }
        } catch (e: Exception) {
            runCatching { TideBackgroundLog.add(context,
                "未来任务${if (e is CancellationException) "取消" else "失败"}：task=$taskId，execution=$executionId，耗时=${android.os.SystemClock.elapsedRealtime() - started}ms，错误=${e.message}",
                "FUTURE_TASK_ERROR") }
            TideStore.open(context).use { db ->
                val attempts = task.optInt("attempts") + if (e is CancellationException) 0 else 1
                db.execSQL("UPDATE schedule_tasks SET status=?,attempts=?,last_error=?,retry_at=?,locked_at=NULL WHERE id=? AND status='running' AND locked_at=?",
                    arrayOf(if (attempts >= 5) "failed" else "pending", attempts,
                        if (e is CancellationException) "Cancelled" else e.message,
                        System.currentTimeMillis() + 30_000L * (1L shl (attempts - 1).coerceIn(0, 6)), taskId, now))
            }
            throw e
        } finally {
            reconcile(context)
        }
    }
}
