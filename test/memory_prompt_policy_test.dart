import 'package:flutter_test/flutter_test.dart';
import 'package:skytide/memory_prompt_policy.dart';
import 'package:skytide/memory_retrieval_policy.dart';
import 'package:skytide/proactive_contact.dart';
import 'package:skytide/cognition_review.dart';

void main() {
  test('proactive rules select latest five first and omit overlaps', () {
    final rows = [
      for (var i = 10; i >= 1; i--)
        {
          'id': '$i',
          'category': i == 10 || i <= 6 ? '规则' : '记忆',
          'content': '条目$i',
          'timestamp': i,
        },
    ];
    final recent = recentOrdinaryMemories(rows);
    final rules = additionalProactiveRules(rows, recent: recent);
    expect(recent.map((row) => row['id']), ['10', '9', '8', '7', '6']);
    expect(rules.map((row) => row['id']), ['5', '4', '3']);
    final reference = proactiveRuleReference(rules);
    expect(reference, contains('最近规则分类世界书条目'));
    expect(reference, contains('条目3'));
    expect(reference, isNot(contains('条目2')));
    expect(reference, isNot(contains('条目10')));
    expect(
      rankMemoryMatches(rows, '条目', exclude: [...recent, ...rules]).every(
        (row) => ![
          ...recent,
          ...rules,
        ].any((included) => memoryIdentity(included) == memoryIdentity(row)),
      ),
      isTrue,
    );
  });

  test('proactive rules omit empty supplemental block and request respect', () {
    final rules = [
      {'id': 'one', 'category': '规则', 'content': '不要催回复'},
    ];
    expect(additionalProactiveRules(rules, recent: rules), isEmpty);
    expect(proactiveRuleReference([]), isEmpty);
    expect(proactiveContactInstructions, contains('请完整阅读已注入的世界书条目'));
    expect(proactiveContactInstructions, contains('重点注意规则分类'));
    expect(proactiveContactInstructions, contains('不要做的事情一定要遵守'));
  });

  test(
    'recent reference includes IDs and excludes cognition before limiting',
    () {
      final reference = recentMemoryReference([
        {'id': 'profile', 'category': '角色眼中的你', 'content': '画像'},
        {'id': 'event', 'category': '记忆', 'content': '同一事件'},
        {'id': 'other', 'category': '记忆', 'content': '其他事件'},
      ], limit: 1);
      expect(reference, contains('event'));
      expect(reference, isNot(contains('profile')));
      expect(reference, isNot(contains('other')));
    },
  );
  test('cognition review preserves profiles and rejects event summaries', () {
    final prompt = cognitionReviewPrompt(
      bot: {},
      memories: [
        {'category': '角色眼中的你', 'content': '耐心且认真'},
      ],
      now: DateTime(2026),
    );
    expect(prompt, contains(memoryCategoryPolicy));
    expect(prompt, contains('耐心且认真'));
    expect(prompt, contains('保留旧内容中仍有效的信息'));
    expect(prompt, contains('modify 必须为 false'));
    expect(memoryDeduplicationPolicy, contains('同一件事'));
    expect(memoryDeduplicationPolicy, contains('没有新增事实'));
  });
}
