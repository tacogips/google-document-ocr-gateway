#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s <version>\n' "$0" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/render-homebrew-formula.sh" "$1" "$script_dir/../../homebrew-tap/Formula/google-document-ocr-gateway.rb"
