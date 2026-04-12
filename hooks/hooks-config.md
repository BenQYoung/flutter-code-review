# Flutter Review — Hooks 配置说明

将以下配置合并到 `~/.claude/settings.json` 的 `hooks` 字段，实现自动触发 Review。

---

## 1. PostToolUse Hook（文件保存后触发 Fast 检测）

在 `~/.claude/settings.json` 的 `hooks.PostToolUse` 中添加：

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "FILE=\"$CLAUDE_TOOL_INPUT_FILE_PATH\"; if echo \"$FILE\" | grep -q '\\.dart$'; then echo \"[Flutter Review] .dart 文件已修改: $FILE\" && echo \"{\\\"mode\\\":\\\"fast\\\",\\\"file\\\":\\\"$FILE\\\"}\" > /tmp/flutter_review_trigger.json; fi",
      "timeout": 5000
    }
  ]
}
```

**说明：** 每次 Write/Edit 工具调用后，如果修改的是 `.dart` 文件，写入触发标记到 `/tmp/flutter_review_trigger.json`。Claude 在下次交互时会检测到此文件并提示是否运行快速 lint 检查。

---

## 2. Stop Hook（会话结束前输出 Review 提醒）

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "if [ -f /tmp/flutter_review_trigger.json ]; then echo '⚠️  本次会话修改了 .dart 文件，建议运行 /flutter-review 进行代码检测'; rm -f /tmp/flutter_review_trigger.json; fi"
      }
    ]
  }
}
```

---

## 3. Git Pre-commit Hook（提交前自动触发 Medium 检测）

在 Flutter 项目目录创建 `.git/hooks/pre-commit`：

```bash
#!/bin/bash
# Flutter Code Review — Pre-commit Hook
# 在 git commit 前自动运行 Medium 模式 Review

set -e

echo "🔍 Running Flutter Code Review (Medium mode)..."

# 获取变更的 dart 文件
CHANGED_DART=$(git diff --cached --name-only | grep '\.dart$' || true)

if [ -z "$CHANGED_DART" ]; then
  echo "✅ 没有变更的 .dart 文件，跳过 Flutter Review"
  exit 0
fi

echo "变更文件："
echo "$CHANGED_DART"

# 运行 flutter analyze（快速检查）
echo "运行 flutter analyze..."
flutter analyze --no-fatal-infos $CHANGED_DART 2>&1

ANALYZE_EXIT=$?
if [ $ANALYZE_EXIT -ne 0 ]; then
  echo "❌ flutter analyze 发现错误，请修复后再提交"
  echo "提示：运行 /flutter-review --fast 获取详细报告"
  exit 1
fi

echo "✅ flutter analyze 通过"
echo ""
echo "💡 提示：运行 /flutter-review 进行完整的 Medium 模式检测（包含架构、安全、测试检查）"

# 如需阻断 CRITICAL 问题提交，取消下面的注释：
# claude --no-interactive "/flutter-review --medium" 2>&1
# if grep -q "CRITICAL" /Users/mac/Desktop/CodeReview/reports/review_*.md 2>/dev/null; then
#   echo "❌ 发现 CRITICAL 问题，请修复后再提交"
#   exit 1
# fi

exit 0
```

安装方式：
```bash
cp .git/hooks/pre-commit.example .git/hooks/pre-commit  # 如果没有示例
chmod +x .git/hooks/pre-commit
```

或直接写入：
```bash
cat > /Users/mac/Desktop/ArkUI-X/bookkeeping_flutter/.git/hooks/pre-commit << 'EOF'
#!/bin/bash
# [上方脚本内容]
EOF
chmod +x /Users/mac/Desktop/ArkUI-X/bookkeeping_flutter/.git/hooks/pre-commit
```

---

## 4. 完整 settings.json 参考结构

`~/.claude/settings.json` 中 hooks 相关的完整结构：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=\"$CLAUDE_TOOL_INPUT_FILE_PATH\"; if echo \"$FILE\" | grep -q '\\.dart$'; then echo \"[Flutter Review] .dart 文件已修改: $FILE\"; fi",
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "if [ -f /tmp/flutter_review_trigger.json ]; then echo '⚠️  本次会话修改了 .dart 文件，建议运行 /flutter-review 进行代码检测'; rm -f /tmp/flutter_review_trigger.json; fi"
      }
    ]
  }
}
```

---

## 5. 验证 Hooks 是否生效

```bash
# 检查 settings.json
cat ~/.claude/settings.json | python3 -m json.tool | grep -A 20 '"hooks"'

# 手动测试 PostToolUse hook（模拟修改 dart 文件）
FILE="lib/main.dart" bash -c 'echo "test" > /tmp/test.dart && echo "[Flutter Review] .dart 文件已修改: $FILE"'
```
