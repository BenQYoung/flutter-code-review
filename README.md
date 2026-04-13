# Flutter Auto Code Review

基于 Claude Code Agent 的 Flutter 项目自动代码检测系统。支持增量（git diff）和全量扫描，覆盖架构、Dart 语言规范、安全、测试、无障碍、国际化等多个维度，输出终端摘要与 Markdown 报告。

## 功能概览

| 能力 | 说明 |
|------|------|
| **零配置项目检测** | 自动检测当前目录或 git 根的 Flutter 项目，支持 `--project` 跨目录使用 |
| **CLAUDE.md 约定感知** | 读取项目约定并传给所有 Agent，按实际项目规则检查 |
| **analysis_options.yaml 感知** | 检测已启用 lint 规则，自动跳过已覆盖的检查，消除重复报告 |
| **状态管理框架自动识别** | 检测 Riverpod/BLoC/GetX/MobX/Signals，只执行对应框架规则 |
| **80% 置信度 + 问题合并** | 相同类型问题合并汇报（"N 处 X 问题"），过滤低置信度启发式结果 |
| **BLOCK/APPROVE 结论** | 有 CRITICAL/HIGH → 🚫 BLOCK；全 MEDIUM/LOW → ✅ APPROVE |
| **变更行过滤** | MEDIUM/LOW 仅报变更行内的问题，CRITICAL/HIGH 全文件扫描 |
| 增量扫描 | 只检测 `git diff` 变更文件，日常提交前使用 |
| 全量轻量扫描 | 纯命令行驱动，不读文件内容，token 极低，整个工程体检 |
| 全量深度扫描 | 逐文件 AI 分析，适合版本里程碑前的完整审查 |
| 多维度检查 | 架构 / Lint / Dart 语言 / 安全 / 测试 / Accessibility / i18n |
| 测试执行 | 实际运行 `flutter test`，检查缺失测试文件 |
| 测试生成 | Deep 模式自动生成缺失测试的 scaffold 文件 |
| 报告输出 | 终端摘要 + Markdown 文件（存入 `flutter-review-reports/`） |
| Hooks 集成 | 修改 .dart 文件后自动提示，支持 git pre-commit |
| **自动修复闭环** | `--fix` 参数：Review 后执行 `dart fix --apply + dart format`（APPROVE 状态时） |
| **弱加密检测** | S13: XOR/MD5/SHA1/DES/ECB 检测（CRITICAL）；S14: `Random()` vs `Random.secure()`（HIGH） |
| **代码质量度量** | D15: 圈复杂度（嵌套深度/函数长度）；D16: 未使用 import；D17: Widget 重复子树 |

---

## 检查项覆盖范围

### 架构（`flutter-arch-reviewer`）
- Feature-First 目录结构、Barrel export 同步、平台代码隔离
- Repository 模式（Provider/Notifier 不直连网络层）、Widget 不直接调用 API
- 状态管理多框架支持：Riverpod / BLoC / GetX / MobX / Signals
  - 状态不可变性（含 MobX `@action`、Signals `.value` 规范）
  - 禁止布尔标志状态组合（`isLoading + hasError`），应用 AsyncValue / sealed class
  - State 类 `==` / `hashCode` 实现（Equatable / freezed / 手动）
  - UI 分支穷举处理、订阅与 Dispose 配对
  - MobX computed 派生状态、Riverpod ref.watch 循环检测
- DI 规范：接口依赖而非实现、无循环依赖、环境 binding 用配置
- 跨 Feature 内部 import、Monorepo 跨包私有 `src/` import
- 路由规范（命令式/声明式混用、路径硬编码、Deep link 校验、Auth guard）
- 错误处理架构（全局 handler、Crashlytics/Sentry 集成、BlocObserver 接入、ErrorWidget 定制）
- 依赖包审查（版本约束、dev_dependencies 分离、未使用依赖、pub.dev 质量评估）

### Lint / Dart 语言（`flutter-lint-reviewer`）
- Dart 语言陷阱：隐式 dynamic、Bang 操作符滥用、过宽 catch（含捕获 Error）、无意义 async、late 滥用、循环内字符串拼接、忽略 Future 返回值
- **Dart 3 新特性**：Pattern Matching、switch 表达式、if-case、Records 替代单用 DTO
- Widget 规范：build() 超 80 行应拆 Widget 类（非私有方法）、`_build*()` 私有方法、UniqueKey、build() 内副作用、StatefulWidget 过度使用
- const 规范：const 构造函数、const 集合字面量、const 传播、const 类中 mutable 字段
- async 后未检查 mounted（CRITICAL）、MediaQuery 旧用法
- WillPopScope 废弃、Image.network 无缓存
- **性能**：build() 内耗时计算、RepaintBoundary、AnimatedBuilder child 参数、Opacity 动画、IntrinsicHeight/Width、图片 cacheWidth/cacheHeight、大列表用具体构造函数
- **平台适配**：SafeArea、响应式布局、文本溢出、back navigation、权限声明、字体缩放
- 无障碍：语义标签、点击目标大小、焦点顺序、装饰性元素排除、颜色非唯一状态指示
- 国际化：硬编码字符串、字符串拼接、日期/数字格式化、RTL 布局
- 静态分析配置：`analysis_options.yaml` 严格配置（strict-casts、unawaited_futures 等）
- **圈复杂度**（D15）：非 build() 函数超 50 行或嵌套深度 > 4 层
- **未使用 import**（D16）：无对应使用的 import 声明，配合 --fix 自动清除
- **Widget 重复子树**（D17）：同文件同 Widget 出现 3+ 次建议提取为独立 Widget

### 安全（`flutter-security-reviewer`）
- 硬编码密钥（应用 `--dart-define` / `.env`，不出现在源码）
- 敏感数据明文存储（Hive 存储 token，应用 FlutterSecureStorage）
- 日志泄露（print 输出含 token/password/credential）
- 明文 HTTP、SSL 证书校验禁用、证书 Pinning 评估
- 用户输入未验证即传给 API、Deep link URL 注入
- 401 处理缺失、URL 参数携带 token、Token 刷新与过期处理
- 生物识别认证评估、Android 导出组件未保护
- **弱加密算法**（S13）：XOR 加密、MD5/SHA1 密码哈希、DES、ECB 模式检测（CRITICAL）
- **不安全随机数**（S14）：安全场景使用 `math.Random()` 而非 `Random.secure()`（HIGH）

### 测试（`flutter-test-reviewer`）
- 检查每个 `lib/` 文件是否有对应 `_test.dart`
- 实际运行 `flutter test --coverage`，覆盖率低于 80% 标记警告
- **状态转移覆盖**：loading→success、loading→error、retry 三路径均须有测试
- **测试隔离**：无共享可变状态、外部依赖必须 mock、最小 Stub 原则
- **异步稳定性**：禁止 `Future.delayed` 时间假设，用 `pumpAndSettle`
- **Golden Test**：设计关键 Widget 的截图回归测试
- **集成测试**：`integration_test/` 关键用户流程覆盖
- Deep 模式：自动生成 Widget / StateNotifier / BLoC / Repository 测试 scaffold

---

## 快速开始

### 前置要求

- Flutter SDK 已安装并在 PATH 中
- [Claude Code](https://claude.ai/claude-code) 或 [Cursor](https://cursor.sh)（至少一个）

### 克隆仓库

```bash
git clone https://github.com/BenQYoung/flutter-code-review.git
cd flutter-code-review
mkdir -p reports
```

---

## Claude Code 安装

```bash
bash scripts/install-claude.sh
```

脚本会自动将所有 Agent 软链到 `~/.claude/agents/`。

完成后在 `~/.claude/settings.json` 的对应字段中合并以下配置，注册 `/flutter-review` 命令：

```json
{
  "extraKnownMarketplaces": {
    "flutter-review-local": {
      "source": {
        "source": "directory",
        "path": "/path/to/flutter-code-review/plugin"
      }
    }
  },
  "enabledPlugins": {
    "flutter-review@flutter-review-local": true
  }
}
```

> 将 `/path/to/flutter-code-review` 替换为实际克隆路径，然后重启 Claude Code。

### 配置目标项目路径（可选）

工具支持**零配置**自动检测：
- 在 Flutter 项目目录内运行 → 自动识别
- 使用 `--project /path/to/flutter_project` 参数显式指定

报告自动输出到 `<project_root>/../flutter-review-reports/`，无需配置。

---

## Cursor 安装

```bash
bash scripts/install-cursor.sh
```

脚本会自动将技能软链到 `~/.cursor/skills/flutter-review`，重启 Cursor 后即可使用 `/flutter-review`。

重启 Cursor 后，在 Chat 中即可使用 `/flutter-review` 命令。

### 说明

Cursor 版与 Claude Code 版功能一致，区别在于：
- Cursor 版所有检测逻辑**内联执行**（不依赖 Agent 工具）
- `--all --fast` 模式完全相同：纯命令行驱动，零额外 token 消耗
- Medium/Deep 模式为**顺序执行**（Claude Code 版为 4 个 Agent 并行）
- 检查规则与 `agents/*.md` 保持同步，不维护两套规则

---

## 使用方法

### 参数总览

| 参数 | 说明 |
|------|------|
| _(无参数)_ | 增量 Medium 模式，扫描 `git diff` 变更文件（推荐日常使用） |
| `--fast` | Fast 模式：只跑 `flutter analyze` + 关键 lint grep，约 30 秒 |
| `--medium` | Medium 模式：完整多维检测，输出 BLOCK/APPROVE 结论（默认） |
| `--deep` | Deep 模式：全检测 + 生成缺失测试 scaffold 路径提示 |
| `--all` | 全量模式：扫描整个 `lib/`（不加则仅扫描 git diff 变更文件） |
| `--file <path>` | 限定扫描目录，可与 `--all` 或增量模式组合使用 |
| `--project <path>` | 显式指定 Flutter 项目根目录（跨目录使用时传入） |
| `--fix` | Review 完成后自动执行 `dart fix --apply && dart format lib/`，仅 APPROVE 状态时生效 |

---

### 场景一：日常提交前检查（最常用）

在 Flutter 项目目录内，修改代码后提交前运行：

```bash
# 增量 Medium（默认）：扫描 git diff 变更文件，输出 BLOCK/APPROVE
/flutter-review

# 增量 Fast：只跑 analyze + 关键 lint，适合频繁自检
/flutter-review --fast

# 增量 Deep：完整检测 + 显示缺失测试文件路径
/flutter-review --deep
```

**输出示例：**
```
═══════════════════════════════════════════════════
  Flutter Code Review — 2026-04-13 10:30
  Mode: medium | Files reviewed: 5 | Framework: riverpod
═══════════════════════════════════════════════════

🔴 CRITICAL: 0  🟠 HIGH: 1  🟡 MEDIUM: 3  🔵 LOW: 1

─── Security ───────────────────────────────────────
  [HIGH]   S2  lib/core/storage/app_storage.dart:42
               refreshToken 存储在 Hive（明文），应用 FlutterSecureStorage
               建议修复：
               // ❌ 错误
               box.put('refreshToken', token);
               // ✅ 正确
               await FlutterSecureStorage().write(key: 'refreshToken', value: token);

─── Verdict ────────────────────────────────────────
  HIGH: 1  →  🚫 BLOCK（合并前必须修复）

═══════════════════════════════════════════════════
  报告已保存：../flutter-review-reports/review_20260413_103022.md
═══════════════════════════════════════════════════
```

---

### 场景二：提交前检查 + 自动修复

Review 通过（APPROVE）后，自动执行 `dart fix --apply && dart format`：

```bash
/flutter-review --fix           # Medium + 自动修复
/flutter-review --fast --fix    # Fast + 自动修复
```

> 注意：存在 CRITICAL/HIGH 问题时（BLOCK 状态），`--fix` 不会执行，需先手动修复。

---

### 场景三：全量工程体检

适合每周例行检查或版本发布前：

```bash
# ⚡️ 推荐：纯命令行驱动，不读文件内容，token 极低（约 5k）
/flutter-review --all --fast

# 限定某个 feature 目录做全量轻量检查
/flutter-review --all --fast --file lib/features/auth

# 全量 Medium：逐文件 AI 分析（文件 > 50 个会提示确认）
/flutter-review --all

# 全量 Deep：最完整，适合版本里程碑前
/flutter-review --all --deep
```

---

### 场景四：指定目录检查

只检查某个 feature 或模块：

```bash
# 只扫描 bill feature 的变更文件
/flutter-review --file lib/features/bill

# 全量扫描 auth feature（不受 git diff 限制）
/flutter-review --all --fast --file lib/features/auth

# Deep 模式检查 core 目录
/flutter-review --deep --file lib/core
```

---

### 场景五：跨项目使用

无需切换目录，在任意位置指定项目路径：

```bash
/flutter-review --project /path/to/my_flutter_app
/flutter-review --fast --project ~/projects/another_app
/flutter-review --all --fast --project /path/to/my_flutter_app
```

---

### 场景六：PR 前完整审查

功能开发完成、准备提 PR 时：

```bash
# Deep 模式：完整检测 + 列出缺失测试文件
/flutter-review --deep

# 全量 Deep（适合改动跨多个 feature）
/flutter-review --all --deep
```

---

### 模式选择参考

| 命令 | Token 消耗 | 耗时 | 推荐场景 |
|------|-----------|------|---------|
| `/flutter-review --fast` | ~5k | 30 秒 | 随时自检，写代码过程中 |
| `/flutter-review`（默认） | ~30k | 2-3 分钟 | 功能完成后，提交前 |
| `/flutter-review --deep` | ~80k | 5-10 分钟 | PR 提交前完整审查 |
| `/flutter-review --all --fast` | ~5k | 1 分钟 | 每周工程体检，整体扫描 |
| `/flutter-review --all` | ~300k+ | 20 分钟+ | 版本发布前（偶尔使用） |
| `/flutter-review --fix` | ~30k | 2-4 分钟 | 提交前检查 + 自动格式化 |

---

### 理解输出结论

每次 Review 结束输出 **Verdict（裁决）**：

| 结论 | 触发条件 | 建议操作 |
|------|---------|---------|
| 🚫 **BLOCK** | 存在任意 CRITICAL 或 HIGH 问题 | 合并前必须修复 |
| ✅ **APPROVE** | 全部为 MEDIUM / LOW 问题 | 可合入，建议后续跟进 |

**变更行过滤规则：**
- CRITICAL / HIGH：全文件扫描，所有匹配均报告
- MEDIUM / LOW：仅报告出现在本次 `git diff` 变更行内的问题，未改动代码的 MEDIUM/LOW 不输出（减少噪音）

---

### 报告文件

每次运行自动保存 Markdown 报告：

```
<project_root>/../flutter-review-reports/review_YYYYMMDD_HHMMSS.md
```

报告包含：Flutter Analyze 原始输出、各维度问题列表、测试结果、Verdict 汇总。

---

## Hooks 自动触发

参考 `hooks/hooks-config.md` 配置以下自动化行为：

- **PostToolUse Hook**：修改 `.dart` 文件后，自动在终端提示运行 `/flutter-review`
- **Stop Hook**：会话结束时，若本次修改了 `.dart` 文件，显示提醒
- **Git Pre-commit Hook**：提交前自动运行 `flutter analyze`，失败则阻断提交

---

## 文件结构

```
flutter-code-review/
├── agents/
│   ├── flutter-review-orchestrator.md   # 编排器（主入口，Claude Code）
│   ├── flutter-arch-reviewer.md         # 架构合规检测
│   ├── flutter-lint-reviewer.md         # Dart/Flutter 规范检测
│   ├── flutter-test-reviewer.md         # 测试覆盖与执行
│   └── flutter-security-reviewer.md    # 安全检测
├── plugin/
│   ├── .claude-plugin/
│   │   ├── plugin.json                  # Claude Code 插件元数据
│   │   └── marketplace.json             # 本地 marketplace 配置
│   ├── .cursor-plugin/
│   │   ├── plugin.json                  # Cursor 插件元数据
│   │   └── hooks-cursor.json            # Cursor hooks 配置
│   └── skills/
│       ├── flutter-review/
│       │   └── SKILL.md                 # Claude Code 版 skill
│       └── flutter-review-cursor/
│           └── SKILL.md                 # Cursor 版 skill（内联执行）
├── skills/
│   └── flutter-review.md               # skill 源文件
├── hooks/
│   └── hooks-config.md                 # Hooks 配置说明
├── reports/                            # 报告输出目录（自动生成）
└── README.md
```

---

## 严重程度说明

| 级别 | 含义 | 建议操作 |
|------|------|---------|
| 🔴 CRITICAL | 会导致运行时崩溃或安全漏洞 | 提交前必须修复 |
| 🟠 HIGH | 架构违规或重要规范问题 | 本次迭代内修复 |
| 🟡 MEDIUM | 代码质量问题，有改进空间 | 记录并计划修复 |
| 🔵 LOW | 最佳实践建议 | 有时间时优化 |

---

## 竞品对比

### 对比工具

| 工具 | 类型 | 定价 | 部署方式 |
|------|------|------|---------|
| **本工具** (flutter-code-review) | AI Agent + CLI | 免费开源 | 本地 |
| **CodeRabbit** | AI SaaS | $15-19/用户/月 | 云端 |
| **DCM (Dart Code Metrics)** | 静态分析 CLI | $39/月 | 本地/CI |
| **LucasXu0/claude-code-plugin** | Claude Code 插件 | 免费开源 | 本地 |
| **flutter analyze（官方）** | 静态分析 | 免费 | 本地/CI |

### 安全检测覆盖

| 检测项 | 本工具 | CodeRabbit | DCM | LucasXu0 | flutter analyze |
|--------|--------|-----------|-----|----------|----------------|
| 硬编码 API Key/Secret | ✅ S1 CRITICAL | ✅ | ❌ | ✅ | ❌ |
| 敏感数据明文存储（Hive vs Keychain） | ✅ S2 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |
| 日志泄露（token/password in print） | ✅ S3 HIGH | ✅ | ❌ | ❌ | ❌ |
| 明文 HTTP | ✅ S5 HIGH | ✅ | ❌ | ✅ | ❌ |
| SSL 证书校验禁用 | ✅ S7 HIGH | ✅ | ❌ | ❌ | ❌ |
| Deep Link URL 注入 | ✅ S10 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |
| 弱加密算法（XOR/MD5/SHA1/DES/ECB） | ✅ S13 CRITICAL | ✅ | ❌ | ❌ | ❌ |
| 不安全随机数（Random() vs Random.secure()） | ✅ S14 HIGH | ✅ | ❌ | ❌ | ❌ |
| 用户输入未验证 | ✅ S9 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |

### 架构规范覆盖

| 检测项 | 本工具 | CodeRabbit | DCM | LucasXu0 | flutter analyze |
|--------|--------|-----------|-----|----------|----------------|
| Feature-First 目录结构 | ✅ A1 | ❌ | ❌ | ❌ | ❌ |
| Repository 模式（Provider 不直连网络） | ✅ B1 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |
| Widget 不直接调用 API | ✅ B3 CRITICAL | ⚠️ 通用 | ❌ | ❌ | ❌ |
| 布尔标志状态反模式（isLoading+hasError） | ✅ C2 HIGH | ❌ | ❌ | ❌ | ❌ |
| 状态不可变性（Riverpod/BLoC/MobX 多框架） | ✅ C1 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |
| 订阅/Dispose 配对（含 AnimationController） | ✅ C6 HIGH | ⚠️ 通用 | ❌ | ❌ | ❌ |
| 跨 Feature 内部 import | ✅ A4 HIGH | ❌ | ❌ | ❌ | ❌ |
| Auth Guard / 路由保护 | ✅ N5 HIGH | ❌ | ❌ | ❌ | ❌ |
| 状态管理框架自动识别（6 框架） | ✅ | ❌ | ❌ | ❌ | ❌ |

### Dart/Flutter Lint 覆盖

| 检测项 | 本工具 | CodeRabbit | DCM | LucasXu0 | flutter analyze |
|--------|--------|-----------|-----|----------|----------------|
| async 后未检查 mounted | ✅ L4 CRITICAL | ⚠️ | ❌ | ✅ | ✅ |
| build() 超 80 行 | ✅ L1 HIGH | ⚠️ | ✅ | ❌ | ❌ |
| 圈复杂度（嵌套 > 4 / 函数 > 50 行） | ✅ D15 MEDIUM | ❌ | ✅ | ❌ | ❌ |
| 未使用 import | ✅ D16 MEDIUM | ⚠️ | ✅ | ❌ | ✅ |
| Widget 重复子树（3+ 次） | ✅ D17 LOW | ❌ | ✅ | ❌ | ❌ |
| Dart 3 Pattern Matching 建议 | ✅ D12 LOW | ❌ | ⚠️ | ❌ | ❌ |
| shrinkWrap 嵌套 ListView | ✅ L9 HIGH | ❌ | ❌ | ❌ | ❌ |
| UniqueKey 在 build() 中 | ✅ L11 HIGH | ❌ | ✅ | ❌ | ❌ |
| analysis_options.yaml 感知（跳过重复） | ✅ | ❌ | ❌ | ❌ | N/A |

### 工程能力对比

| 能力 | 本工具 | CodeRabbit | DCM | LucasXu0 | flutter analyze |
|------|--------|-----------|-----|----------|----------------|
| 自动修复闭环（--fix） | ✅ `dart fix + format` | ❌ 仅建议 | ❌ | ✅ 基础 | ❌ |
| 修复代码片段（fix 字段附 Dart 示例） | ✅ HIGH+ | ✅ | ❌ | ❌ | ❌ |
| 增量扫描（git diff） | ✅ | ✅ PR 触发 | ❌ 全量 | ✅ | ❌ |
| 变更行过滤（MEDIUM/LOW 只报变更行） | ✅ | ✅ | ❌ | ❌ | ❌ |
| BLOCK/APPROVE 结论 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 零配置自动检测项目 | ✅ | ✅ | ❌ 需配置 | ✅ | ✅ |
| 并行 Agent 执行（4 Agent 同时） | ✅ | N/A | N/A | ❌ | N/A |
| 全量轻量模式（纯 CLI，零 token） | ✅ --all --fast | ❌ | ✅ | ❌ | ✅ |
| 测试实际执行 + scaffold 生成 | ✅ | ❌ | ❌ | ❌ | ❌ |
| Cursor 版（内联执行，无需 Agent） | ✅ | ❌ | ❌ | ❌ | ❌ |
| 代码上传风险 | 无（本地） | 有（云端） | 无 | 无 | 无 |

### 规则数量汇总

| 类别 | 本工具 | DCM | flutter analyze | CodeRabbit |
|------|--------|-----|----------------|-----------|
| 安全 | **14 条** | ~5 条 | 0 条 | ~20 条（通用） |
| 架构 / 设计模式 | **25 条** | ~10 条 | 0 条 | ~5 条（通用） |
| Dart/Flutter Lint | **63 条** | **475+ 条** | ~100 条 | ~30 条（通用） |
| 测试 | **7 条** | 0 条 | 0 条 | ~5 条（通用） |
| **合计** | **~109 条** | **490+ 条** | ~100 条 | 通用，非 Flutter 专项 |

> DCM 规则数量最多，但绝大多数为 Dart 语言层面的静态规则（命名规范、代码风格）。本工具侧重 Flutter 专项高价值规则（架构、安全、测试），在**有效密度**上更高。

### 核心差异化优势

1. **Flutter 语境深度** — 唯一理解状态管理框架差异（Riverpod/BLoC/MobX/GetX/Signals）并按框架切换规则的工具
2. **架构规则完整性** — Feature-First 目录、Repository 模式、DI 规范等 25 条架构规则，竞品均无
3. **测试生命周期集成** — 实际执行 `flutter test`、检查状态转移三路径、Deep 模式自动生成 scaffold
4. **修复闭环** — `--fix` 执行 `dart fix --apply + dart format`；`fix` 字段对每个 HIGH+ 问题附 Dart 示例代码
5. **隐私安全** — 全本地运行，无代码上传至云端（CodeRabbit 需上传代码）
6. **零订阅费** — 免费开源，无月费

### 仍存在的差距

| 差距项 | 对标工具 | 说明 |
|--------|---------|------|
| 纯静态 Lint 规则数量（475+ vs 63） | DCM | DCM 专注命名/风格，本工具侧重高价值规则 |
| CI/CD GitHub App 集成（PR 自动评论）| CodeRabbit | 本工具需手动触发，暂无 PR bot |
| analysis_options 规则自动写入 | DCM | DCM 可生成配置文件 |
| 多语言项目支持（非纯 Flutter）| CodeRabbit | 本工具专注 Flutter |

---

## 参考资料

- [Effective Dart](https://dart.dev/effective-dart)
- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter Testing Overview](https://docs.flutter.dev/testing/overview)
- [Flutter Accessibility](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- [Claude Code Documentation](https://claude.ai/claude-code)

---

## License

MIT
