---
name: flutter-review
description: Flutter 项目自动代码检测与 Review（Cursor 版）。支持 --fast（仅 analyze）、--medium（默认，analyze+多维检测）、--deep（全检测）、--all（全量）、--file <path>（指定目录）。所有逻辑内联执行，不依赖 Agent 工具。
---

# Flutter Code Review（Cursor 版）

Cursor 版本：所有检测逻辑内联执行，不依赖 Agent 工具。

默认项目路径：`/Users/mac/Desktop/ArkUI-X/bookkeeping_flutter`
报告输出路径：`/Users/mac/Desktop/CodeReview/reports/`

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
```

---

## 执行流程

### Step 1：定位 Flutter 项目根目录

运行以下命令确认当前目录是否为 Flutter 项目：

```bash
ls pubspec.yaml 2>/dev/null || echo "not_flutter_root"
```

如果不是 Flutter 项目根目录，切换到 `/Users/mac/Desktop/ArkUI-X/bookkeeping_flutter`。

### Step 2：确定扫描范围

#### 增量模式（无 --all 参数）

```bash
git diff --name-only HEAD 2>/dev/null
git diff --name-only --cached 2>/dev/null
```

过滤出 `.dart` 文件。如果指定了 `--file <path>`，进一步过滤。

如果没有变更文件（干净工作区），自动切换为全量模式并提示用户。

#### 全量 + Fast 模式（`--all --fast`）⚡️

**纯命令行驱动，零 AI token 消耗，直接执行 shell 输出结果：**

```bash
ROOT="${target_path:-lib}"

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
- 状态不可变性：检查 State 类中有无直接字段赋值（`state.xxx =`）
- 布尔标志反模式：检查 `bool isLoading`/`bool hasError` 组合
- 路由规范：检查 `Navigator.push` 与 GoRouter 混用
- 跨 feature import：检查 `import 'package:.*/features/<other_feature>/.*'`

**Lint / Dart 语言检测（对应 flutter-lint-reviewer 规则）：**
- `[L4]` async 函数后使用 context/setState 前未检查 mounted（CRITICAL）
- `[D1]` 隐式 dynamic（`var x = ...` 推断为 dynamic）
- `[D3]` 空 catch 或过宽 catch
- `[D5]` 无意义 async（函数标记 async 但无 await）
- `[L1]` build() 超过 60 行
- `[L2]` 硬编码颜色/间距（Color(0x...)、Colors.*、数字间距）
- `[L6]` shrinkWrap: true 嵌套 ListView
- `[L8]` print 语句
- `[L10]` WillPopScope 废弃
- `[A1]` IconButton/GestureDetector 缺少 Semantics/tooltip
- `[I1]` Text('...') 硬编码中文字符串

**安全检测（对应 flutter-security-reviewer 规则）：**
- `[S1]` 硬编码 apiKey/secret/password/token 赋值
- `[S2]` Hive 存储 token/password（应用 FlutterSecureStorage）
- `[S3]` print 输出包含 token/password/secret
- `[S5]` 非 localhost 的 `http://` 请求
- `[S6]` URL 参数含 token（`?token=`）
- `[S7]` SSL 校验禁用（`badCertificateCallback`）

**测试检测（对应 flutter-test-reviewer 规则）：**
- 检查变更文件是否有对应 `_test.dart`
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

**终端输出格式：**

```
═══════════════════════════════════════════════════
  Flutter Code Review — YYYY-MM-DD HH:MM
  Mode: medium | Files reviewed: N
═══════════════════════════════════════════════════

🔴 CRITICAL: N  🟠 HIGH: N  🟡 MEDIUM: N  🔵 LOW: N

─── Architecture ───────────────────────────────────
  [HIGH]   B1  lib/features/bill/providers/bill_provider.dart:23
               StateNotifier 直接 import DioClient，应通过 Repository

─── Lint / Dart ────────────────────────────────────
  [CRITICAL] L4  lib/features/auth/presentation/login_screen.dart:45
                 async 函数后使用 setState 前未检查 mounted

─── Security ───────────────────────────────────────
  [HIGH]   S2  lib/core/storage/app_storage.dart:42
               refreshToken 存储在 Hive（明文），应用 FlutterSecureStorage

─── Tests ──────────────────────────────────────────
  ✅ 42 passed / ❌ 0 failed
  缺少测试: lib/features/bill/providers/bill_provider.dart

═══════════════════════════════════════════════════
  报告已保存：reports/review_YYYYMMDD_HHMMSS.md
═══════════════════════════════════════════════════
```

**同时写入 Markdown 报告文件：**
路径：`/Users/mac/Desktop/CodeReview/reports/review_YYYYMMDD_HHMMSS.md`

报告格式：
```markdown
# Flutter Code Review Report
**Date:** YYYY-MM-DD HH:MM
**Mode:** medium
**Project:** bookkeeping_flutter
**Files Reviewed:** N

## Summary
| Severity | Count |
|----------|-------|
| 🔴 CRITICAL | N |
| 🟠 HIGH | N |
| 🟡 MEDIUM | N |
| 🔵 LOW | N |

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

### Step 6：CRITICAL 处理

如发现 CRITICAL 级别问题，输出：

```
⚠️  发现 CRITICAL 问题！请在修复以下问题后再提交：
   - [问题列表]
```

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
