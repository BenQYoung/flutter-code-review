# Flutter Auto Code Review

基于 Claude Code Agent 的 Flutter 项目自动代码检测系统。支持增量（git diff）和全量扫描，覆盖架构、Dart 语言规范、安全、测试、无障碍、国际化等多个维度，输出终端摘要与 Markdown 报告。

## 功能概览

| 能力 | 说明 |
|------|------|
| 增量扫描 | 只检测 `git diff` 变更文件，日常提交前使用 |
| 全量轻量扫描 | 纯命令行驱动，不读文件内容，token 极低，整个工程体检 |
| 全量深度扫描 | 逐文件 AI 分析，适合版本里程碑前的完整审查 |
| 多维度检查 | 架构 / Lint / Dart 语言 / 安全 / 测试 / Accessibility / i18n |
| 测试执行 | 实际运行 `flutter test`，检查缺失测试文件 |
| 测试生成 | Deep 模式自动生成缺失测试的 scaffold 文件 |
| 报告输出 | 终端摘要 + Markdown 文件（存入 `reports/`） |
| Hooks 集成 | 修改 .dart 文件后自动提示，支持 git pre-commit |

---

## 检查项覆盖范围

### 架构（`flutter-arch-reviewer`）
- Feature-First 目录结构合规
- Repository 模式（Provider/Notifier 不直连网络层）
- Widget 不直接调用 API
- 状态管理多框架支持：Riverpod / BLoC / GetX / MobX
  - 状态不可变性
  - 禁止布尔标志状态组合（`isLoading + hasError`）
  - UI 分支穷举处理
  - 订阅与 Dispose 配对
- 跨 Feature 内部 import 检测
- 路由规范（命令式/声明式混用、路径硬编码）
- 错误处理架构（全局 handler、原始异常暴露、空 catch）
- 依赖包审查（版本约束、dev_dependencies 分离、未使用依赖）

### Lint / Dart 语言（`flutter-lint-reviewer`）
- Dart 语言陷阱：隐式 dynamic、Bang 操作符滥用、过宽 catch、无意义 async、late 滥用、循环内字符串拼接、忽略 Future 返回值
- Widget 规范：build() 长度、硬编码颜色/间距、shrinkWrap 嵌套、UniqueKey、build() 内副作用
- async 后未检查 mounted（CRITICAL）
- MediaQuery 旧用法（`of(context).size` → `sizeOf`）
- WillPopScope 废弃、Image.network 无缓存、print 语句
- 无障碍（Accessibility）：语义标签、点击目标大小、颜色非唯一状态指示
- 国际化（i18n）：硬编码字符串、字符串拼接、日期/数字格式化
- 静态分析配置：`analysis_options.yaml` 严格配置检查

### 安全（`flutter-security-reviewer`）
- 硬编码密钥（apiKey / secret / token 赋值为字符串字面量）
- 敏感数据明文存储（Hive 存储 token，应用 FlutterSecureStorage）
- 日志泄露（print 输出敏感字段）
- 明文 HTTP（非 localhost 的 `http://` 请求）
- 401 处理缺失、URL 参数携带 token、SSL 证书校验禁用

### 测试（`flutter-test-reviewer`）
- 检查每个 `lib/` 文件是否有对应 `_test.dart`
- 实际运行 `flutter test --coverage`
- 覆盖率分析（低于 80% 标记警告）
- Deep 模式：自动生成 Widget / StateNotifier / Repository 测试 scaffold

---

## 快速开始

### 前置要求

- [Claude Code](https://claude.ai/claude-code) CLI 已安装
- Flutter SDK 已安装并在 PATH 中
- `jq` 已安装（`brew install jq`）

### 安装

```bash
# 1. 克隆仓库
git clone https://github.com/yourname/flutter-code-review.git
cd flutter-code-review

# 2. 创建 reports 目录
mkdir -p reports

# 3. 部署 Agents（软链到 Claude Code agents 目录）
mkdir -p ~/.claude/agents
ln -sf "$(pwd)/agents/flutter-review-orchestrator.md" ~/.claude/agents/
ln -sf "$(pwd)/agents/flutter-arch-reviewer.md"       ~/.claude/agents/
ln -sf "$(pwd)/agents/flutter-lint-reviewer.md"       ~/.claude/agents/
ln -sf "$(pwd)/agents/flutter-test-reviewer.md"       ~/.claude/agents/
ln -sf "$(pwd)/agents/flutter-security-reviewer.md"   ~/.claude/agents/

# 4. 注册本地插件（/flutter-review slash command）
# 编辑 ~/.claude/settings.json，添加以下内容：
```

在 `~/.claude/settings.json` 的对应字段中合并以下配置：

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

> 将 `/path/to/flutter-code-review` 替换为实际克隆路径。

### 配置目标项目路径

编辑 `agents/flutter-review-orchestrator.md`，将默认项目路径改为你的 Flutter 项目：

```
默认项目路径：`/path/to/your/flutter_project`
报告输出路径：`/path/to/flutter-code-review/reports/`
```

### 重启 Claude Code

配置完成后重启 Claude Code，等待插件加载完毕。

---

## Cursor 安装

### 前置要求

- [Cursor](https://cursor.sh) 已安装
- Flutter SDK 已安装并在 PATH 中

### 注册技能（软链）

```bash
mkdir -p ~/.cursor/skills
ln -sf "$(pwd)/plugin/skills/flutter-review-cursor" ~/.cursor/skills/flutter-review
```

重启 Cursor 后，在 Chat 中即可使用 `/flutter-review` 命令。

### 说明

Cursor 版与 Claude Code 版功能一致，区别在于：
- Cursor 版所有检测逻辑**内联执行**（不依赖 Agent 工具）
- `--all --fast` 模式完全相同：纯命令行驱动，零额外 token 消耗
- Medium/Deep 模式为**顺序执行**（Claude Code 版为 4 个 Agent 并行）
- 检查规则与 `agents/*.md` 保持同步，不维护两套规则

---

## 使用方法

在 Claude Code 对话框中输入以下命令：

### 日常使用（增量，只扫描变更文件）

```
/flutter-review              # Medium 模式（推荐日常使用）
/flutter-review --fast       # 快速模式：analyze + lint，约 30 秒
/flutter-review --deep       # 深度模式：全检测 + 生成测试 scaffold
```

### 全量工程体检

```
/flutter-review --all --fast      # ⚡️ 轻量全量：纯命令行，token 极低，推荐
/flutter-review --all             # 全量 Medium：逐文件 AI 分析（会提示确认）
/flutter-review --all --deep      # 全量 Deep：最完整，耗时最长（会提示确认）
```

### 指定目录

```
/flutter-review --file lib/features/bill
/flutter-review --all --fast --file lib/features/auth
```

### 模式对比

| 命令 | Token 消耗 | 耗时 | 适用场景 |
|------|-----------|------|---------|
| `--fast` | ~5k | 30秒 | 快速检查，随时用 |
| `--medium`（默认）| ~30k | 2-3分钟 | 功能完成后提交前 |
| `--deep` | ~80k | 5-10分钟 | PR 前完整审查 |
| `--all --fast` | ~5k | 1分钟 | 每周工程体检 |
| `--all --medium` | ~300k+ | 20分钟+ | 版本发布前（偶尔）|

---

## 报告输出

每次运行自动生成报告文件：`reports/review_YYYYMMDD_HHMMSS.md`

终端输出示例：

```
═══════════════════════════════════════════════════
  Flutter Code Review — 2026-04-12 21:30
  Mode: medium | Files reviewed: 8
═══════════════════════════════════════════════════

🔴 CRITICAL: 1  🟠 HIGH: 3  🟡 MEDIUM: 5  🔵 LOW: 2

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
  报告已保存：reports/review_20260412_213022.md
═══════════════════════════════════════════════════
```

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

## 参考资料

- [Effective Dart](https://dart.dev/effective-dart)
- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter Testing Overview](https://docs.flutter.dev/testing/overview)
- [Flutter Accessibility](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- [Claude Code Documentation](https://claude.ai/claude-code)

---

## License

MIT
