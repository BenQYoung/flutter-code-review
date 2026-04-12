---
name: flutter-test-reviewer
description: 检查测试覆盖、运行 flutter test，Deep 模式下 AI 生成缺失测试的 scaffold。由 flutter-review-orchestrator 调用。
tools: Read, Write, Bash, Grep, Glob
---

# Flutter Test Reviewer

接收变更文件列表、项目根路径、模式（medium/deep）。

## Step 1：检查测试文件存在性

对每个变更的 `lib/` 文件，检查 `test/` 下是否有对应 `_test.dart`：

映射规则：
- `lib/features/bill/presentation/bill_screen.dart`
  → `test/features/bill/presentation/bill_screen_test.dart`
- `lib/features/bill/providers/bill_provider.dart`
  → `test/features/bill/providers/bill_provider_test.dart`
- `lib/core/network/dio_client.dart`
  → `test/core/network/dio_client_test.dart`

记录缺失测试文件的清单。

## Step 2：运行单元测试

```bash
cd <project_root> && flutter test --coverage 2>&1
```

解析输出，提取：
- 通过数量（`+N`）
- 失败用例（文件、行号、错误信息）
- 跳过数量
- 覆盖率（如果 `coverage/lcov.info` 存在）

如果测试运行失败（没有 flutter 环境），输出警告并跳过，不影响其他检查。

## Step 3：覆盖率分析（如有 lcov.info）

```bash
# 解析 lcov.info 获取总覆盖率
lcov --summary coverage/lcov.info 2>&1 | grep "lines"
```

如果覆盖率 < 80%，标记为 MEDIUM 级别问题。

## Step 4：Deep 模式 — AI 生成测试 Scaffold

**仅在 mode=deep 时执行。**

对缺失测试文件的变更 `lib/` 文件：

### 4a. 读取源文件，识别类型

```
- StatelessWidget / ConsumerWidget → Widget 测试
- StateNotifier / AsyncNotifier → Provider 单元测试
- Repository 实现类 → Repository 单元测试（mock HTTP）
- 纯 Dart 类（Entity、DTO）→ 基础单元测试
```

### 4b. Widget 测试 Scaffold

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookkeeping_flutter/features/<feature>/presentation/<widget>.dart';

void main() {
  group('<WidgetName>', () {
    testWidgets('shows loading indicator when state is loading', (tester) async {
      // TODO: 注入 mock provider，state = AsyncLoading()
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: <WidgetName>())),
      );
      // expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows content when data loaded', (tester) async {
      // TODO: 注入 mock provider，state = AsyncData(mockData)
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: <WidgetName>())),
      );
      // expect(find.text('...'), findsOneWidget);
    });

    testWidgets('shows error view on failure', (tester) async {
      // TODO: 注入 mock provider，state = AsyncError(Exception(), StackTrace.empty)
    });
  });
}
```

### 4c. StateNotifier 测试 Scaffold

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bookkeeping_flutter/features/<feature>/providers/<provider>.dart';

class Mock<Repository> extends Mock implements <Repository> {}

void main() {
  late <ProviderName> notifier;
  late Mock<Repository> mockRepo;

  setUp(() {
    mockRepo = Mock<Repository>();
    notifier = <ProviderName>(mockRepo);
  });

  group('<ProviderName>', () {
    test('initial state is AsyncLoading or expected initial', () {
      // expect(notifier.state, ...);
    });

    test('load() sets state to AsyncData on success', () async {
      // when(() => mockRepo.fetchXxx()).thenAnswer((_) async => mockData);
      // await notifier.load();
      // expect(notifier.state, AsyncData(mockData));
    });

    test('load() sets state to AsyncError on failure', () async {
      // when(() => mockRepo.fetchXxx()).thenThrow(Exception('error'));
      // await notifier.load();
      // expect(notifier.state, isA<AsyncError>());
    });
  });
}
```

### 4d. Repository 测试 Scaffold

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bookkeeping_flutter/core/network/dio_client.dart';
import 'package:bookkeeping_flutter/features/<feature>/data/<repo>_impl.dart';

class MockDioClient extends Mock implements DioClient {}

void main() {
  late <RepoName>Impl repo;
  late MockDioClient mockDio;

  setUp(() {
    mockDio = MockDioClient();
    repo = <RepoName>Impl(mockDio);
  });

  group('<RepoName>', () {
    test('fetchXxx() returns data on success', () async {
      // TODO: mock HTTP 响应
    });

    test('fetchXxx() throws AppError on failure', () async {
      // TODO: mock HTTP 异常
    });
  });
}
```

写入对应测试文件路径（scaffold，包含 TODO 注释，不填充完整 mock 细节）。

## 输出格式

返回结构化 JSON：
```json
{
  "category": "Test",
  "issues": [
    {
      "severity": "MEDIUM",
      "file": "lib/features/bill/providers/bill_provider.dart",
      "line": null,
      "message": "缺少对应测试文件：test/features/bill/providers/bill_provider_test.dart"
    }
  ],
  "test_results": {
    "passed": 42,
    "failed": 2,
    "skipped": 3,
    "coverage": "74%"
  },
  "generated_tests": [
    "test/features/bill/providers/bill_provider_test.dart"
  ]
}
```
