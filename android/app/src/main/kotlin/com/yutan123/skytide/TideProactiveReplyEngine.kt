package com.yutan123.skytide

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/** Runs the same Dart request builder as foreground chat, without opening an Activity. */
object TideProactiveReplyEngine {
    // Accessed only on the Android main thread, including the bridge handler.
    private val active = mutableMapOf<String, (done: () -> Unit) -> Unit>()

    fun interrupt(botId: String, done: () -> Unit) {
        val stop = active[botId]
        if (stop == null) done() else stop(done)
    }

    suspend fun generate(context: Context, botId: String, generation: String, due: String?): JSONObject =
        runChat(context, botId, mapOf("kind" to "proactive", "generation" to generation, "due" to due)) {
            withContext(Dispatchers.IO) {
                TideStore.open(context).use { TideProactiveRequestGate.allowed(it, botId, generation, due) }
            }
        }

    suspend fun generateFuture(context: Context, botId: String, prompt: String): JSONObject =
        runChat(context, botId, mapOf("kind" to "future", "prompt" to prompt))

    suspend fun generateVitals(context: Context, botId: String, reason: String, pending: String): JSONObject =
        runChat(context, botId, mapOf("kind" to "vitals", "reason" to reason, "pending" to pending))

    fun requireReply(context: Context, response: JSONObject): JSONObject {
        if (TideBackgroundLog.enabled(context)) {
            response.optJSONArray("request_logs")?.let { logs ->
                for (index in 0 until logs.length()) {
                    val entry = logs.optJSONObject(index) ?: continue
                    TideBackgroundLog.add(context, entry.optString("message"), entry.optString("level", "BACKGROUND_CHAT"))
                }
            }
        }
        check(response.optBoolean("success")) { response.optString("error", "Background chat request failed") }
        return response
    }

    private suspend fun runChat(
        context: Context,
        botId: String,
        arguments: Map<String, String?>,
        allowed: (suspend () -> Boolean)? = null
    ): JSONObject = withContext(Dispatchers.Main) {
        check(allowed?.invoke() != false) { "Proactive request interrupted by user activity" }
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context.applicationContext)
        loader.ensureInitializationComplete(context.applicationContext, null)
        val engine = FlutterEngine(context.applicationContext)
        TideMemoryEmbedding.register(context.applicationContext, engine.dartExecutor.binaryMessenger)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "skytide/proactive_reply")
        val native = MethodChannel(engine.dartExecutor.binaryMessenger, "skytide.native.channel")
        val completed = CompletableDeferred<JSONObject>()
        native.setMethodCallHandler { call, result ->
            if (call.method == "deviceContext") {
                runCatching {
                    TideDeviceContext.read(context, call.argument<List<String>>("allowed")?.toSet() ?: emptySet())
                }.fold(result::success) { result.error("DEVICE_CONTEXT_FAILED", it.message, null) }
            } else {
                result.notImplemented()
            }
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                result.success(null)
                channel.invokeMethod("generate", arguments + ("botId" to botId), object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        if (value is Map<*, *>) completed.complete(JSONObject(value))
                        else completed.completeExceptionally(IllegalStateException("Invalid proactive response"))
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        completed.completeExceptionally(IllegalStateException("$code: $message"))
                    }
                    override fun notImplemented() {
                        completed.completeExceptionally(IllegalStateException("Proactive entry point unavailable"))
                    }
                })
            } else result.notImplemented()
        }
        val stop: (done: () -> Unit) -> Unit = { done ->
            val once = java.util.concurrent.atomic.AtomicBoolean(false)
            val finish = {
                if (once.compareAndSet(false, true)) {
                    completed.completeExceptionally(IllegalStateException("Proactive request interrupted by user activity"))
                    done()
                }
                Unit
            }
            channel.invokeMethod("cancel", null, object : MethodChannel.Result {
                override fun success(value: Any?) = finish()
                override fun error(code: String, message: String?, details: Any?) = finish()
                override fun notImplemented() = finish()
            })
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ finish() }, 1000)
        }
        if (allowed != null) active[botId] = stop
        val monitor = allowed?.let { stillAllowed ->
            launch {
                while (!completed.isCompleted) {
                    delay(200)
                    if (!stillAllowed()) {
                        stop {}
                        break
                    }
                }
            }
        }
        try {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "proactiveReplyMain")
            )
            withTimeout(5 * 60 * 1000L) { completed.await() }
        } finally {
            if (active[botId] === stop) active.remove(botId)
            monitor?.cancel()
            channel.setMethodCallHandler(null)
            native.setMethodCallHandler(null)
            engine.destroy()
        }
    }
}
