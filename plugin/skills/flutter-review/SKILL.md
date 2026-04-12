---
name: flutter-review
description: Flutter 项目自动代码检测与 Review。支持 --fast（仅 analyze）、--medium（默认，analyze+test）、--deep（AI 生成测试）、--file <path>（指定目录）
---

根据参数选择模式，调用 flutter-review-orchestrator agent 执行检测。

## 覆盖范围

- **Dart 语言**：!滥用、隐式 dynamic、空 catch、无意义 async、late 滥用、Future 忽略等
- **Widget**：const、Key、build() 长度、shrinkWrap 嵌套、UniqueKey、build() 内副作用
- **状态管理**：Riverpod / BLoC / GetX / MobX 多框架——不可变性、禁止布尔标志组合、穷举分支
- **架构**：Feature-First、Repository 模式、跨 feature import、main.dart 纯净
- **无障碍**：语义标签、点击目标大小、颜色非唯一状态指示
- **国际化**：硬编码字符串、字符串拼接、日期/数字格式化
- **安全**：硬编码密钥、明文存储、日志泄露、明文 HTTP
- **测试**：运行 flutter test、检查缺失测试文件、Deep 模式生成 scaffold
- **依赖**：版本约束、dev_dependencies 分离、未使用依赖

## 参数解析

**模式（决定检查深度）：**
- 无参数 / `--medium` → Medium 模式（默认）
- `--fast` → Fast 模式（只跑 flutter analyze + lint 检查）
- `--deep` → Deep 模式（全量检测 + AI 生成缺失测试 scaffold）

**范围（决定扫描哪些文件）：**
- 无参数 → 增量模式，只扫描 `git diff` 变更文件
- `--all` → 全量模式，扫描整个 `lib/` 目录
  - 配合 `--fast`：**纯命令行驱动，不读文件内容，token 消耗极低** ⚡️
  - 配合 `--medium/--deep`：逐文件 AI 分析，消耗大量 token（会提示确认）
- `--file <path>` → 指定目录（可与 --all 或默认增量组合）

## 执行

调用 `flutter-review-orchestrator` agent，传入以下参数：

```
mode: fast | medium | deep
scope: diff | all
target_path: 指定路径（可选）
report_dir: /Users/mac/Desktop/CodeReview/reports/
```

## 使用示例

```bash
/flutter-review                         # 增量 Medium：只扫描 git diff 变更文件
/flutter-review --fast                  # 增量 Fast：analyze + 快速 lint
/flutter-review --deep                  # 增量 Deep：全检测 + 生成测试 scaffold

/flutter-review --all --fast            # ⚡️ 全量轻量：纯命令行，整个工程体检，token 消耗极低
/flutter-review --all                   # 全量 Medium：逐文件 AI 分析（消耗大，会提示确认）
/flutter-review --all --deep            # 全量 Deep：最重量级（会提示确认）

/flutter-review --file lib/features/bill           # 增量，限定目录
/flutter-review --all --fast --file lib/features/bill  # 轻量全量，限定目录
```

## 输出

- 终端：彩色摘要（问题数量、严重程度分级、测试结果）
- 文件：`/Users/mac/Desktop/CodeReview/reports/review_YYYYMMDD_HHMMSS.md`
