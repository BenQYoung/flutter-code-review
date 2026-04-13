---
name: flutter-review
description: Flutter 项目自动代码检测与 Review（Cursor 版）。支持 --fast（仅 analyze）、--medium（默认，analyze+多维检测）、--deep（全检测）、--all（全量）、--file <path>（指定目录）、--project <path>（指定项目）。所有逻辑内联执行，不依赖 Agent 工具。自动检测项目路径、状态管理框架、lint 规则，输出 BLOCK/APPROVE 结论。
---

# Flutter Code Review（Cursor 版）

Cursor 版本：所有检测逻辑内联执行，不依赖 Agent 工具。

**零配置：** 自动检测当前目录或 git 根目录的 Flutter 项目，无需手动配置路径。
报告输出路径：`<project_root>/../flutter-review-reports/`

## 参数解析

**模式（决定检查深度）：**
- 无参数 / `--medium` → Medium 模式（默认）
- `--fast` → Fast 模式（只跑 flutter analyze + 关键 lint 检查）
- `--deep` → Deep 模式（全量检测 + 生成缺失测试 scaffold 路径提示）

**范围（决定扫描哪些文件）：**
- 无参数 → 增量模式，只扫描 `git diff` 变更文件
- `--all` → 全量模式，扫描整个 `lib/` 目录
  - 配合 `--fast`：**纯命令行驱动，不读文件内容，token 消耗极低** ⚡️
  - 配合 `--medium/--deep`：逐文件 AI 分析（会提示确认）
- `--file <path>` → 指定目录（可与 --all 或默认增量组合）
- `--project <path>` → 显式指定 Flutter 项目根目录（跨目录使用）
- `--fix` → 在 Review 完成后自动执行 `dart fix --apply && dart format lib/`（仅 APPROVE 状态时执行）

## 使用示例

```bash
/flutter-review                         # 增量 Medium：只扫描 git diff 变更文件
/flutter-review --fast                  # 增量 Fast：analyze + 快速 lint
/flutter-review --deep                  # 增量 Deep：全检测 + 测试 scaffold 提示

/flutter-review --all --fast            # ⚡️ 全量轻量：纯命令行，整个工程体检，token 消耗极低
/flutter-review --all                   # 全量 Medium：逐文件 AI 分析（消耗大，会提示确认）
/flutter-review --all --deep            # 全量 Deep：最重量级（会提示确认）

/flutter-review --file lib/features/bill                  # 增量，限定目录
/flutter-review --all --fast --file lib/features/bill     # 轻量全量，限定目录
/flutter-review --project /path/to/other/flutter/app      # 指定任意 Flutter 项目
```

---

## 执行流程

### Step 1：零配置定位 Flutter 项目根目录

```bash
# 优先级：--project 参数 > 当前目录 > git 根目录
if [ -n "$project_path" ]; then
  PROJECT_ROOT="$project_path"
elif [ -f "./pubspec.yaml" ]; then
  PROJECT_ROOT="$(pwd)"
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$PROJECT_ROOT" ] || [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
    echo "ERROR: 未找到 Flutter 项目。请在 Flutter 项目目录运行，或使用 --project /path 指定。"
    exit 1
  fi
fi
REPORT_DIR="$(dirname "$PROJECT_ROOT")/flutter-review-reports"
mkdir -p "$REPORT_DIR"
echo "📁 项目：$PROJECT_ROOT"
```

### Step 1b：环境感知

```bash
# 加载 CLAUDE.md 项目约定
[ -f "$PROJECT_ROOT/CLAUDE.md" ] && echo "📋 已加载项目约定（CLAUDE.md）"

# 检测已启用 lint 规则
ENABLED_LINT_RULES=""
[ -f "$PROJECT_ROOT/analysis_options.yaml" ] && \
  ENABLED_LINT_RULES=$(grep -E "^\s+- [a-z]" "$PROJECT_ROOT/analysis_options.yaml" \
    | sed 's/.*- //' | tr '\n' ',') && \
  echo "📋 lint 规则：$ENABLED_LINT_RULES"

# 自动识别状态管理框架
STATE_MGMT="unknown"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
grep -q "flutter_bloc\|  bloc:" "$PUBSPEC"          && STATE_MGMT="bloc"
grep -q "flutter_riverpod\|  riverpod:" "$PUBSPEC"   && STATE_MGMT="riverpod"
grep -q "^  provider:" "$PUBSPEC"                    && STATE_MGMT="provider"
grep -q "^  get:" "$PUBSPEC"                         && STATE_MGMT="getx"
grep -q "  mobx:" "$PUBSPEC"                         && STATE_MGMT="mobx"
grep -q "  signals:" "$PUBSPEC"                      && STATE_MGMT="signals"
echo "🔍 状态管理框架：$STATE_MGMT"
```

### Step 2：确定扫描范围

#### 增量模式（无 --all 参数）

```bash
git diff --name-only HEAD 2>/dev/null
git diff --name-only --cached 2>/dev/null
```

过滤出 `.dart` 文件。如果指定了 `--file <path>`，进一步过滤。

如果没有变更文件（干净工作区），自动切换为全量模式并提示用户。

**存储变更 diff（用于 MEDIUM/LOW 变更行过滤）：**
```bash
git diff HEAD --unified=0 2>/dev/null > /tmp/review_diff.patch
git diff --cached --unified=0 2>/dev/null >> /tmp/review_diff.patch
```

#### 全量 + Fast 模式（`--all --fast`）⚡️

**纯命令行驱动，零 AI token 消耗，直接执行 shell 输出结果：**

```bash
ROOT="${target_path:-$PROJECT_ROOT/lib}"

echo "=== flutter analyze ==="
flutter analyze --no-fatal-infos 2>&1

echo "=== [L4] async 后未检查 mounted ==="
grep -rn "setState\|context\." "$ROOT" --include="*.dart" -l | \
  xargs grep -ln "async" | \
  xargs grep -n "setState\|context\." | \
  grep -v "mounted\|context\.mounted\|//"

echo "=== [D3] 空 catch / 过宽 catch ==="
grep -rn "} catch (e)\|} catch (err)\|catch (_)" "$ROOT" --include="*.dart"

echo "=== [L2] 硬编码颜色 ==="
grep -rn "Color(0x\|Colors\." "$ROOT" --include="*.dart" | \
  grep -v "theme/\|app_colors\|//"

echo "=== [S1] 硬编码密钥 ==="
grep -rn "apiKey\s*=\s*\"\|secret\s*=\s*\"\|password\s*=\s*\"\|token\s*=\s*\"" \
  "$ROOT" --include="*.dart" | grep -v "test\|mock\|fake\|your_"

echo "=== [S5] 明文 HTTP ==="
grep -rn "http://" "$ROOT" --include="*.dart" | \
  grep -v "localhost\|127\.0\.0\.1\|//"

echo "=== [L8] print 语句 ==="
grep -rn "^\s*print(" "$ROOT" --include="*.dart"

echo "=== [L10] WillPopScope 废弃 ==="
grep -rn "WillPopScope" "$ROOT" --include="*.dart"

echo "=== [B1] Provider 直连网络层 ==="
grep -rn "DioClient\|import.*dio_client" \
  "$ROOT/features" --include="*.dart" | \
  grep "presentation\|providers\|notifier\|bloc"

echo "=== [C2] 布尔标志状态反模式 ==="
grep -rn "bool isLoading\|bool hasError\|bool isSuccess\|bool isFetching" \
  "$ROOT" --include="*.dart"

echo "=== [N1] 混用路由方式 ==="
grep -rn "Navigator\.push\b" "$ROOT" --include="*.dart" | grep -v "test\|//"

echo "=== [I1] 硬编码字符串 Text ==="
grep -rn "Text('" "$ROOT" --include="*.dart" | \
  grep -v "l10n\|AppLocalizations\|tr(\|//\|test"

echo "=== [缺失测试] lib 文件无对应 _test.dart ==="
find "$ROOT" -name "*.dart" ! -name "*_test.dart" | while read f; do
  tf="${f/lib\//test/}"
  tf="${tf%.dart}_test.dart"
  [ ! -f "$tf" ] && echo "MISSING: $f"
done

echo "=== flutter test ==="
flutter test --no-pub 2>&1 | tail -20
```

所有输出直接作为报告内容，整理后写入报告文件。

### Step 3：运行 flutter analyze（所有模式）

```bash
flutter analyze --no-fatal-infos 2>&1 | head -100
```

### Step 4：按模式执行检测

#### Fast 模式（增量）

1. 输出 `flutter analyze` 结果
2. 对变更的 `.dart` 文件执行以下快速 lint 检查（grep 命令，不读文件内容进上下文）：
   - `[L4]` async 后未检查 mounted
   - `[D3]` 空 catch / 过宽 catch
   - `[S1]` 硬编码密钥
   - `[S5]` 明文 HTTP
   - `[L8]` print 语句
3. 终端显示摘要后结束

#### Medium 模式（默认，增量）

对变更文件依次执行以下检测（顺序执行，对应 Claude Code 版的 4 个并行 Agent）：

**架构检测（对应 flutter-arch-reviewer 规则）：**
- Feature-First 目录结构：检查文件路径是否在 `lib/features/<feature>/data|domain|presentation/` 下
- Repository 模式：检查 Provider/Notifier/BLoC 是否直接 import DioClient 或 http 包
- 状态不可变性：检查 State 类中有无直接字段赋值（`state.xxx =`）；MobX 检查 @action 之外的赋值
- 布尔标志反模式：检查 `bool isLoading`/`bool hasError` 组合，应用 AsyncValue/sealed class
- 路由规范：检查 `Navigator.push` 与 GoRouter 混用
- 跨 feature import：检查 `import 'package:.*/features/<other_feature>/.*'`
- State 类 == / hashCode：Riverpod/BLoC 不可变状态类是否实现（Equatable / freezed / 手动）
- DI 规范：Provider 层不直接 new 依赖实现类
- Deep link URL 校验：pathParameters/queryParameters 使用前是否有验证
- Auth guard：受保护路由是否有 redirect 逻辑
- 全局错误捕获：main.dart 是否有 FlutterError.onError 和 PlatformDispatcher.instance.onError
- 错误上报集成：是否接入 Crashlytics/Sentry

**Lint / Dart 语言检测（对应 flutter-lint-reviewer 规则）：**
- `[L4]` async 函数后使用 context/setState 前未检查 mounted（CRITICAL）
- `[D1]` 隐式 dynamic
- `[D2]` Bang 操作符滥用（超过 5 处）
- `[D3]` 空 catch 或过宽 catch；捕获 Error 类型
- `[D4]` 无意义 async（函数标记 async 但无 await）
- `[D12]` 未使用 Dart 3 Pattern Matching（is + as 手动 cast）
- `[D13]` 单次 DTO 可改用 Dart 3 Records
- `[D14]` const 类中有 mutable 字段
- `[L1]` build() 超过 80 行，且应拆为 Widget 类而非私有方法
- `[L2]` 硬编码颜色/间距（Color(0x...)、Colors.*、数字间距）
- `[L6]` shrinkWrap: true 嵌套 ListView
- `[L8]` print 语句（应用 dart:developer log）
- `[L10]` WillPopScope 废弃
- `[L16]` `_buildXxx()` 私有方法返回 Widget（应提为独立 Widget 类）
- `[L18]` TextStyle 硬编码不走 Theme
- `[P1]` build() 内 sort/filter/RegExp 耗时计算
- `[P4]` Opacity 用于动画（应用 AnimatedOpacity/FadeTransition）
- `[P5]` IntrinsicHeight/IntrinsicWidth 在列表中滥用
- `[R1]` Scaffold 页面缺少 SafeArea
- `[R3]` 无界容器内 Text 无溢出保护
- `[R6]` TextStyle fontSize 硬编码不响应系统字体大小
- `[A1]` IconButton/GestureDetector 缺少 Semantics/tooltip
- `[I1]` Text('...') 硬编码用户可见字符串
- `[D15]` 函数圈复杂度过高：非 build() 函数超 50 行或嵌套深度 > 4 层（MEDIUM）
- `[D16]` 未使用 import：import 声明无对应使用，可通过 --fix 自动清除（MEDIUM）
- `[D17]` Widget 子树重复：同文件同 Widget 出现 3+ 次建议提取（LOW）

**安全检测（对应 flutter-security-reviewer 规则）：**
- `[S1]` 硬编码 apiKey/secret/password/token 赋值（应用 --dart-define 或安全存储）
- `[S2]` Hive 存储 token/password（应用 FlutterSecureStorage）
- `[S3]` print 输出包含 token/password/secret/credential
- `[S5]` 非 localhost 的 `http://` 请求
- `[S6]` URL 参数含 token/password（`?token=`）
- `[S7]` SSL 校验禁用（`badCertificateCallback` 返回 true）
- `[S9]` 用户输入未经 validator 直接传给 API
- `[S10]` Deep link URL 参数未校验直接用于导航
- `[S13]` 弱加密算法：XOR/MD5/SHA1 用于密码、DES、ECB 模式（CRITICAL）
- `[S14]` 不安全随机数：安全场景使用 `Random()` 而非 `Random.secure()`（HIGH）

**测试检测（对应 flutter-test-reviewer 规则）：**
- 检查变更文件是否有对应 `_test.dart`
- 检查测试文件是否覆盖 loading→success、loading→error、retry 三种状态转移
- 检查测试文件顶层是否有共享可变状态（违反测试隔离）
- 检查是否有 `Future.delayed`/`sleep` 导致 flaky 测试
- 运行 `flutter test --no-pub 2>&1 | tail -20`
- 统计通过/失败数量

#### Deep 模式（增量）

同 Medium 模式，额外执行：
- 对每个缺失 `_test.dart` 的文件，输出建议生成的测试 scaffold 路径
- 提示用户：`建议生成测试文件：test/features/xxx/xxx_test.dart`
- 统计 `lib/` 文件数 vs `test/` 文件数，计算覆盖率

#### 全量 + Medium/Deep 模式（`--all --medium/--deep`）

文件数量大，先统计并提示：

```bash
find "${target_path:-lib}" -name "*.dart" | wc -l
```

若 > 50 文件：
```
⚠️  全量 medium/deep 模式将扫描 N 个文件，预计消耗大量 token。
   建议改用：/flutter-review --all --fast（轻量，基于命令行）
   确认继续？(y/N)
```

用户确认后，分批（每批 20 个文件）执行上述 Medium/Deep 检测逻辑。

### Step 5：聚合结果 + 生成报告

**聚合规则：**
- 置信度 ≥ 80% 的问题才输出；启发式检测结果用 ⚠️ 标注提示人工确认
- 相同 rule + 相同 severity 的问题合并（"N 处 X 问题，示例：file:line"）
- MEDIUM/LOW 问题仅报变更行内的匹配（未变更代码不报 MEDIUM/LOW）
- 框架适配：已识别 `STATE_MGMT` 后，跳过不相关框架的问题（如 Riverpod 项目不报 BLoC 专项）
- `enabled_rules` 中已覆盖的 lint 规则对应问题不重复报告

**终端输出格式：**

```
═══════════════════════════════════════════════════
  Flutter Code Review — YYYY-MM-DD HH:MM
  Mode: medium | Files reviewed: N | Framework: riverpod
═══════════════════════════════════════════════════

🔴 CRITICAL: N  🟠 HIGH: N  🟡 MEDIUM: N  🔵 LOW: N

─── Architecture ───────────────────────────────────
  [HIGH]   B1  lib/features/bill/providers/bill_provider.dart:23
               StateNotifier 直接 import DioClient，应通过 Repository

─── Lint / Dart ────────────────────────────────────
  [CRITICAL] L4  lib/features/auth/presentation/login_screen.dart:45
                 async 函数后使用 setState 前未检查 mounted
  [MEDIUM]   L2 ⚠️  硬编码颜色（5 处，示例：lib/features/home/home_screen.dart:32）

─── Security ───────────────────────────────────────
  [HIGH]   S2  lib/core/storage/app_storage.dart:42
               refreshToken 存储在 Hive（明文），应用 FlutterSecureStorage

─── Tests ──────────────────────────────────────────
  ✅ 42 passed / ❌ 0 failed
  缺少测试: lib/features/bill/providers/bill_provider.dart

─── Verdict ────────────────────────────────────────
  CRITICAL: N  HIGH: N  →  🚫 BLOCK / ✅ APPROVE

  判定规则：有任意 CRITICAL 或 HIGH → 🚫 BLOCK（合并前必须修复）
           全部 MEDIUM/LOW → ✅ APPROVE（可带问题合入）

═══════════════════════════════════════════════════
  报告已保存：<REPORT_DIR>/review_YYYYMMDD_HHMMSS.md
═══════════════════════════════════════════════════
```

**同时写入 Markdown 报告文件：**
路径：`$REPORT_DIR/review_YYYYMMDD_HHMMSS.md`

报告格式：
```markdown
# Flutter Code Review Report
**Date:** YYYY-MM-DD HH:MM
**Mode:** medium
**Project:** <project_name>
**Files Reviewed:** N
**Framework:** riverpod

## Summary
| Severity | Count |
|----------|-------|
| 🔴 CRITICAL | N |
| 🟠 HIGH | N |
| 🟡 MEDIUM | N |
| 🔵 LOW | N |
| **Verdict** | 🚫 BLOCK / ✅ APPROVE |

## Flutter Analyze
[analyze 原始输出]

## Architecture Issues
[问题列表]

## Lint Issues
[问题列表]

## Security Issues
[问题列表]

## Test Results
[测试结果 + 缺失测试文件列表]
```

### Step 6：CRITICAL/BLOCK 处理

如发现 CRITICAL 级别问题，输出：

```
⚠️  发现 CRITICAL 问题！请在修复以下问题后再提交：
   - [问题列表]
```

**Verdict 判定：** 有任意 CRITICAL 或 HIGH → `🚫 BLOCK`；全部 MEDIUM/LOW → `✅ APPROVE`

### Step 7：自动修复（仅 --fix 模式）

如用户传入 `--fix` 参数，在报告生成后执行：

- 若 Verdict 为 **APPROVE**（无 CRITICAL/HIGH）：
```bash
cd "$PROJECT_ROOT"
echo "🔧 运行 dart fix..."
dart fix --apply 2>&1
echo "✨ 运行 dart format..."
dart format lib/ 2>&1 | tail -5
echo "✅ 自动修复完成，建议重新运行 /flutter-review 验证结果"
```

- 若 Verdict 为 **BLOCK**（存在 CRITICAL/HIGH）：
```
⚠️  检测到 CRITICAL/HIGH 问题，自动修复已跳过。
   请先手动修复上述 CRITICAL/HIGH 问题后，再使用 --fix 参数。
```

注意：`dart fix --apply` 只修复有确定性自动修复的问题（未使用 import、可自动转换的 lint 警告等），不会引入语义变更。D16（未使用 import）可通过此步骤自动清除。

---

## 覆盖范围说明

本技能内联了以下检查规则（Claude Code 版通过 4 个独立 Agent 执行，Cursor 版顺序内联执行）：

| 规则来源 | 覆盖内容 |
|---------|---------|
| flutter-arch-reviewer | Feature-First、Repository 模式、状态不可变、路由、跨 feature import |
| flutter-lint-reviewer | Dart 语言陷阱、Widget 规范、async/mounted、无障碍、i18n |
| flutter-security-reviewer | 硬编码密钥、明文存储、日志泄露、明文 HTTP |
| flutter-test-reviewer | 测试覆盖检查、flutter test 执行、Deep 模式 scaffold 提示 |

检查规则详情参见：
- `agents/flutter-arch-reviewer.md`
- `agents/flutter-lint-reviewer.md`
- `agents/flutter-security-reviewer.md`
- `agents/flutter-test-reviewer.md`
