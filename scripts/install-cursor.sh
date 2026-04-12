#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing Flutter Code Review for Cursor..."

mkdir -p ~/.cursor/skills
ln -sf "$REPO_DIR/plugin/skills/flutter-review-cursor" ~/.cursor/skills/flutter-review

echo "Done. Restart Cursor and use /flutter-review in Chat."
