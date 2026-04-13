---
name: flutter-test-reviewer
description: 检查测试覆盖（含 golden test）、运行 flutter test、验证测试隔离和状态转移覆盖。Deep 模式下 AI 生成缺失测试的 scaffold。由 flutter-review-orchestrator 调用。
tools: Read, Write, Bash, Grep, Glob
---

# Flutter Test Reviewer

接收变更文件列表、项目根路径、模式（medium/deep）。

---

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

---

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

---

## Step 3：覆盖率分析（如有 lcov.info）

```bash
lcov --summary coverage/lcov.info 2>&1 | grep "lines"
```

如果覆盖率 < 80%，标记为 MEDIUM 级别问题。

---

## Step 4：测试质量检查

对变更的测试文件（`*_test.dart`）执行以下质量检查：

### T1. 状态转移覆盖完整性 [HIGH]
每个 async 操作（网络请求、数据库操作）必须有对应的三种状态测试：
- loading → success 路径
- loading → error 路径
- retry / empty state 路径

检测：读取测试文件，检查 `group` 内是否有覆盖这三种场景的 `test`。

### T2. 测试隔离 [HIGH]
- 测试用例间不共享可变状态（在 `setUp`/`tearDown` 中初始化，不用 static/全局变量）
- 外部依赖（API、数据库）必须 mock/fake，不调用真实服务
- 每个 test 文件只测试一个类/单元

检测：`grep -n "static\|var [a-z]" <test_file>` 检查测试文件顶层是否有共享可变状态。

### T3. 最小 Stub 原则 [MEDIUM]
Mock 只定义当前测试需要的行为，不过度定义无关方法的 stub。
检测：查看 `when()` 调用数量与实际 mock 使用场景是否匹配。

### T4. 异步测试稳定性 [HIGH]
避免使用 `Future.delayed` 或 `sleep` 做时间假设，用 `pumpAndSettle` 或显式 `pump(Duration)` 控制帧推进。
检测：`grep -n "Future\.delayed\|sleep(" <test_file>`

### T5. Golden Test 检查 [MEDIUM]
设计关键 Widget（卡片、自定义组件）未配置 golden test（截图回归测试）。
检测：`grep -rn "matchesGoldenFile\|goldenFileComparator" test/ --include="*.dart"` 检查是否有 golden test 存在。

### T6. 集成测试覆盖关键流程 [LOW]
关键用户流程（登录、支付、核心业务）是否有 `integration_test/` 中的 E2E 测试。
检测：
```bash
ls <project_root>/integration_test/ 2>/dev/null || echo "NO_INTEGRATION_TESTS"
```

### T7. 测试验证行为而非实现 [MEDIUM]
测试断言内部私有方法调用次数而非可观察行为，过度绑定实现细节。
检测：`grep -n "verify\|verifyNever\|captureAny" <test_file>` 结合被测类判断是否过度 verify 内部实现。

---

## Step 5：Deep 模式 — AI 生成测试 Scaffold

**仅在 mode=deep 时执行。**

对缺失测试文件的变更 `lib/` 文件：

### 5a. 读取源文件，识别类型

```
- StatelessWidget / ConsumerWidget → Widget 测试
- StatefulWidget → Widget 测试（含 setState 场景）
- StateNotifier / AsyncNotifier → Provider 单元测试
- Bloc / Cubit → bloc_test 单元测试
- Repository 实现类 → Repository 单元测试（mock HTTP）
- 纯 Dart 类（Entity、DTO）→ 基础单元测试
- 有 @riverpod / @injectable 注解 → 对应注入框架测试
```

### 5b. Widget 测试 Scaffold

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
      await tester.pumpAndSettle();
      // expect(find.text('...'), findsOneWidget);
    });

    testWidgets('shows error view on failure', (tester) async {
      // TODO: 注入 mock provider，state = AsyncError(Exception(), StackTrace.empty)
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: <WidgetName>())),
      );
      await tester.pumpAndSettle();
      // expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('tap action triggers correct behavior', (tester) async {
      // TODO: 模拟用户点击，验证可观察行为（导航、状态变更）
    });
  });
}
```

### 5c. StateNotifier / AsyncNotifier 测试 Scaffold

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
    test('initial state is expected initial value', () {
      // expect(notifier.state, ...);
    });

    test('load() sets state to AsyncData on success', () async {
      // when(() => mockRepo.fetchXxx()).thenAnswer((_) async => mockData);
      // await notifier.load();
      // expect(notifier.state, isA<AsyncData<Xxx>>());
    });

    test('load() sets state to AsyncError on failure', () async {
      // when(() => mockRepo.fetchXxx()).thenThrow(Exception('error'));
      // await notifier.load();
      // expect(notifier.state, isA<AsyncError>());
    });

    test('retry after error resets to loading then success', () async {
      // TODO: 验证 retry 场景
    });
  });
}
```

### 5d. BLoC / Cubit 测试 Scaffold

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bookkeeping_flutter/features/<feature>/bloc/<bloc>.dart';

class Mock<Repository> extends Mock implements <Repository> {}

void main() {
  late <BlocName> bloc;
  late Mock<Repository> mockRepo;

  setUp(() {
    mockRepo = Mock<Repository>();
    bloc = <BlocName>(mockRepo);
  });

  tearDown(() => bloc.close());

  group('<BlocName>', () {
    blocTest<BlocName, <StateName>>(
      'emits [Loading, Loaded] when fetch succeeds',
      build: () => bloc,
      setUp: () {
        // when(() => mockRepo.fetchXxx()).thenAnswer((_) async => mockData);
      },
      act: (bloc) => bloc.add(<EventName>()),
      expect: () => [
        // isA<<StateName>Loading>(),
        // isA<<StateName>Loaded>(),
      ],
    );

    blocTest<BlocName, <StateName>>(
      'emits [Loading, Error] when fetch fails',
      build: () => bloc,
      setUp: () {
        // when(() => mockRepo.fetchXxx()).thenThrow(Exception('error'));
      },
      act: (bloc) => bloc.add(<EventName>()),
      expect: () => [
        // isA<<StateName>Loading>(),
        // isA<<StateName>Error>(),
      ],
    );
  });
}
```

### 5e. Repository 测试 Scaffold

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
    test('fetchXxx() returns parsed data on HTTP 200', () async {
      // TODO: mock HTTP 响应，验证返回值映射正确
    });

    test('fetchXxx() throws AppError on HTTP 4xx/5xx', () async {
      // TODO: mock HTTP 异常，验证错误映射为 AppError
    });

    test('fetchXxx() throws AppError on network timeout', () async {
      // TODO: mock 超时，验证处理
    });
  });
}
```

写入对应测试文件路径（scaffold，包含 TODO 注释，不填充完整 mock 细节）。

---

## 输出格式

返回结构化 JSON：
```json
{
  "category": "Test",
  "issues": [
    {
      "severity": "HIGH",
      "file": "test/features/bill/providers/bill_provider_test.dart",
      "line": 23,
      "rule": "T1",
      "message": "缺少 error 状态转移测试（loading → error 路径）"
    },
    {
      "severity": "MEDIUM",
      "file": "lib/features/bill/providers/bill_provider.dart",
      "line": null,
      "rule": "missing",
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
