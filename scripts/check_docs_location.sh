#!/usr/bin/env bash
set -euo pipefail

# This script fails if there are .md files outside of Documentation/ (except README.md)
# It intentionally ignores vendor/library docs under `lib/` and workflow/.github files.

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || printf "%s" "$(pwd)")
cd "$repo_root"

echo "Checking markdown file locations..."

# List tracked markdown files, exclude README.md, exclude Documentation/, lib/, and .github/
mapfile -t files < <(git ls-files '*.md' 2>/dev/null | grep -Ev '(^README\.md$|/README\.md$)' | grep -Ev '^Documentation/' | grep -Ev '^lib/' | grep -Ev '^.github/' || true)

if [ "${#files[@]}" -ne 0 ]; then
  echo "Found markdown files outside of Documentation/:"
  for f in "${files[@]}"; do
    echo "  - $f"
  done
  echo
  echo "Please move these files into the 'Documentation/' directory or update this script to allow them."
  exit 1
fi

echo "All markdown files are correctly located (or are allowed exceptions)."
