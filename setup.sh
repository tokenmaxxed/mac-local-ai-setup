#!/usr/bin/env bash
# TokenMaxxed: local AI setup for a fresh Apple Silicon Mac
# Usage:  bash setup.sh            (install everything)
#         bash setup.sh --dry-run  (show what would happen)
#         MODELS="gpt-oss:20b" bash setup.sh   (choose your own models)
set -euo pipefail

DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
run(){ echo "→ $*"; [[ $DRY -eq 1 ]] || eval "$@"; }
say(){ printf "\n\033[1;33m%s\033[0m\n" "$*"; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { echo "This script is for Apple Silicon Macs."; exit 1; }

RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
say "Detected ${RAM_GB}GB unified memory"

# Pick models that fit this machine unless the user set MODELS
if [[ -z "${MODELS:-}" ]]; then
  if   (( RAM_GB >= 96 )); then MODELS="gpt-oss:20b gpt-oss:120b"
  elif (( RAM_GB >= 32 )); then MODELS="gpt-oss:20b"
  else                          MODELS="gemma3:4b"
  fi
fi

say "1/5 Xcode command line tools"
xcode-select -p >/dev/null 2>&1 || run "xcode-select --install"

say "2/5 Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  run 'eval "$(/opt/homebrew/bin/brew shellenv)"'
fi

say "3/5 Apps: Ollama, LM Studio"
for cask in ollama-app lm-studio; do
  brew list --cask "$cask" >/dev/null 2>&1 || run "brew install --cask $cask"
done

say "4/5 Starting Ollama"
run "open -a Ollama"
[[ $DRY -eq 1 ]] || until curl -s localhost:11434 >/dev/null; do sleep 1; done

say "5/5 Downloading models: $MODELS"
for m in $MODELS; do run "ollama pull $m"; done

say "Done. Try:  ollama run ${MODELS%% *}"
echo "Every token counts."
