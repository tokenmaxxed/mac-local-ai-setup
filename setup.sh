#!/usr/bin/env bash
# TokenMaxxed: local AI setup for a fresh Apple Silicon Mac
# Usage:  bash setup.sh            (install everything, then a security check)
#         bash setup.sh --dry-run  (show what would happen)
#         bash setup.sh --harden   (also switch on the macOS firewall; asks for your password)
#         MODELS="gpt-oss:20b" bash setup.sh   (choose your own models)
set -euo pipefail

DRY=0; HARDEN=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --harden) HARDEN=1 ;; esac
done
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

say "1/6 Xcode command line tools"
xcode-select -p >/dev/null 2>&1 || run "xcode-select --install"

say "2/6 Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  run 'eval "$(/opt/homebrew/bin/brew shellenv)"'
fi

say "3/6 Apps: Ollama, LM Studio"
for cask in ollama-app lm-studio; do
  brew list --cask "$cask" >/dev/null 2>&1 || run "brew install --cask $cask"
done

say "4/6 Starting Ollama"
run "open -a Ollama"
[[ $DRY -eq 1 ]] || until curl -s localhost:11434 >/dev/null; do sleep 1; done

say "5/6 Downloading models: $MODELS"
for m in $MODELS; do run "ollama pull $m"; done

say "6/6 Security check"
WARN=0
ok(){ printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
bad(){ printf "  \033[1;31m!\033[0m %s\n" "$*"; WARN=1; }

# Ollama must only listen on this Mac, never your network or the internet
if [[ -n "$(launchctl getenv OLLAMA_HOST 2>/dev/null)${OLLAMA_HOST:-}" ]]; then
  bad "OLLAMA_HOST is set ($(launchctl getenv OLLAMA_HOST 2>/dev/null)${OLLAMA_HOST:-}). Unset it unless you mean to share Ollama: launchctl unsetenv OLLAMA_HOST"
fi
LISTEN=$(lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | sort -u || true)
if [[ -z "$LISTEN" ]]; then ok "Ollama not listening yet (it will default to this Mac only)"
elif echo "$LISTEN" | grep -qvE '^(127\.0\.0\.1|\[::1\]):11434$'; then bad "Ollama is reachable from other devices: $LISTEN"
else ok "Ollama only listens on this Mac"; fi

# macOS firewall
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if "$FW" --getglobalstate 2>/dev/null | grep -qi enabled; then ok "Firewall is on"
elif [[ $HARDEN -eq 1 ]]; then run "sudo $FW --setglobalstate on" && ok "Firewall switched on"
else bad "Firewall is off. Turn it on in System Settings > Network > Firewall, or re-run with --harden"; fi

# Disk encryption
if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then ok "FileVault disk encryption is on"
else bad "FileVault is off. Turn it on in System Settings > Privacy & Security > FileVault"; fi

# Homebrew usage analytics
run "brew analytics off" >/dev/null && ok "Homebrew analytics off"

echo "  • LM Studio: keep its local server off unless you need it, and leave 'Serve on Local Network' unticked."
echo "  • Only download models from sources you trust (Ollama library, official Hugging Face orgs)."
[[ $WARN -eq 0 ]] && ok "All checks passed"

say "Done. Try:  ollama run ${MODELS%% *}"
echo "Every token counts."
