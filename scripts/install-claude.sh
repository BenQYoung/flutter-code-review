#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing Flutter Code Review for Claude Code..."

mkdir -p ~/.claude/agents
ln -sf "$REPO_DIR/agents/flutter-review-orchestrator.md" ~/.claude/agents/
ln -sf "$REPO_DIR/agents/flutter-arch-reviewer.md"       ~/.claude/agents/
ln -sf "$REPO_DIR/agents/flutter-lint-reviewer.md"       ~/.claude/agents/
ln -sf "$REPO_DIR/agents/flutter-test-reviewer.md"       ~/.claude/agents/
ln -sf "$REPO_DIR/agents/flutter-security-reviewer.md"   ~/.claude/agents/

echo "Done. Restart Claude Code and add the plugin config to ~/.claude/settings.json"
echo "See README.md for details."
