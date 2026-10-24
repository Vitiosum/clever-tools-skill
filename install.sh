#!/usr/bin/env bash
# Installe le skill clever-tools pour Claude Code et pour Codex (et tout agent qui lit ~/.agents/skills).
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/skills/clever-tools"

for dest in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$dest"
  rm -rf "${dest:?}/clever-tools"
  cp -R "$src" "$dest/clever-tools"
  echo "Installé : $dest/clever-tools"
done

if ! command -v clever >/dev/null 2>&1; then
  echo "clever-tools absent : npm install -g clever-tools (ou brew install CleverCloud/homebrew-tap/clever-tools)"
fi
