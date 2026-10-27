#!/usr/bin/env bash
# TokenMaxxed: local AI setup for any Apple Silicon Mac
# Checks your hardware, recommends models that fit, then lets you tick what you want.
#
# Usage:  bash setup.sh             (hardware check, pick apps + models, install, security check)
#         bash setup.sh --yes       (no questions: take the recommended picks)
#         bash setup.sh --dry-run   (show what would happen, install nothing)
#         bash setup.sh --harden    (also switch on the macOS firewall; asks for your password)
#         MODELS="gemma4:12b-it-qat gemma4:12b-mlx" bash setup.sh   (skip the model menu)
#         APPS="ollama whisper" bash setup.sh                         (skip the app menu)
set -euo pipefail

DRY=0; HARDEN=0; YES=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --harden) HARDEN=1 ;; --yes|-y) YES=1 ;; esac
done
run(){ echo "→ $*"; [[ $DRY -eq 1 ]] || eval "$@"; }
say(){ printf "\n\033[1;33m%s\033[0m\n" "$*"; }
dim(){ printf "\033[2m%s\033[0m\n" "$*"; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { echo "This script is for Apple Silicon Macs."; exit 1; }

# Ask questions only when a person is at the keyboard (works with curl | bash too)
TTY=""
if [[ $YES -eq 0 ]] && { true </dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi
ask(){ local r=""; [[ -n "$TTY" ]] && read -r -p "$1" r <"$TTY"; echo "$r"; }

# ───────────────────────── 1. Hardware check ─────────────────────────
say "Hardware check"
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
GPU_CORES=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/{print $2; exit}')
MACOS="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
FREE_GB=$(df -g / | awk 'NR==2{print $4}')
TB=$(system_profiler SPThunderboltDataType 2>/dev/null | grep -Eo 'Thunderbolt ?[0-9]' | sort -u | tail -1 || true)

# Rough memory the GPU can use for a model: macOS gives it about 2/3 of RAM up to 36GB, about 3/4 above, minus headroom
BUDGET=$(awk -v r="$RAM_GB" 'BEGIN{f=(r<=36)?0.67:0.75; printf "%.1f", r*f-1}')

printf "  Chip:        %s\n" "$CHIP"
printf "  Memory:      %sGB unified (about %sGB usable for a model)\n" "$RAM_GB" "$BUDGET"
printf "  GPU cores:   %s\n" "${GPU_CORES:-unknown}"
printf "  macOS:       %s\n" "$MACOS"
printf "  Free disk:   %sGB\n" "$FREE_GB"
printf "  Thunderbolt: %s\n" "${TB:-unknown}"
if [[ "$TB" == *5 ]]; then dim "  (Thunderbolt 5: this Mac can join an RDMA cluster on macOS 26.2+)"; fi

# ───────────────────────── 2. Model catalogue ─────────────────────────
# tag | what it's for
CATALOGUE=(
  "gemma4:e2b-it-qat|Tiny. Notes and summaries on 8GB Macs"
  "gemma4:e4b-it-qat|Small. Quick chat, light docs"
  "gemma4:12b-it-qat|Everyday model for 16GB Macs (QAT build)"
  "gemma4:12b-mlx|Same Gemma 12B, built for Apple's MLX engine"
  "gemma4:26b-a4b-it-qat|Fast mixture-of-experts for 24GB+"
  "gpt-oss:20b|Everyday reasoning + docs"
  "qwen3.8:27b|Coding and agents"
  "qwen3.8:27b-mlx|Qwen 27B, MLX build"
  "gpt-oss:120b|The big one. 96GB+ Macs"
)
if   (( RAM_GB >= 96 )); then REC="gpt-oss:20b qwen3.8:27b gpt-oss:120b"
elif (( RAM_GB >= 48 )); then REC="gpt-oss:20b qwen3.8:27b"
elif (( RAM_GB >= 32 )); then REC="gemma4:26b-a4b-it-qat gpt-oss:20b"
elif (( RAM_GB >= 24 )); then REC="gemma4:12b-it-qat gpt-oss:20b"
elif (( RAM_GB >= 16 )); then REC="gemma4:12b-it-qat"
else                          REC="gemma4:e2b-it-qat"
fi

size_gb(){ # live size from the Ollama registry, so the menu never goes stale
  curl -fsSL -m 8 --retry 2 -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://registry.ollama.ai/v2/library/${1%%:*}/manifests/${1#*:}" 2>/dev/null \
    | grep -oE '"size": ?[0-9]+' | awk -F: '{s+=$2} END{if(s) printf "%.1f", s/1e9; else print "?"}'
}
fit(){ awk -v s="$1" -v b="$BUDGET" 'BEGIN{ if(s=="?") print "?"; else if(s<=b) print "fits"; else if(s<=b+2) print "tight"; else print "too big" }'; }

# Toggle menu: numbers flip a tick, Enter carries on
menu(){ # $1 title, then globals M_LABEL[] M_ON[]
  local n i input
  n=${#M_LABEL[@]}
  while true; do
    echo; echo "  $1"
    for ((i=0;i<n;i++)); do
      printf "   [%s] %2d. %s\n" "$([[ ${M_ON[$i]} -eq 1 ]] && echo x || echo ' ')" $((i+1)) "${M_LABEL[$i]}"
    done
    [[ -z "$TTY" ]] && return
    input=$(ask "  Type numbers to tick/untick (e.g. 2 4), 'a' all, 'n' none, Enter to continue: ")
    [[ -z "$input" ]] && return
    case "$input" in
      a) for ((i=0;i<n;i++)); do M_ON[$i]=1; done ;;
      n) for ((i=0;i<n;i++)); do M_ON[$i]=0; done ;;
      *) for i in $input; do
           if [[ "$i" =~ ^[0-9]+$ ]] && (( i>=1 && i<=n )); then M_ON[$((i-1))]=$(( 1 - M_ON[$((i-1))] )); fi
         done ;;
    esac
  done
}

# ───────────────────────── 3. Pick apps ─────────────────────────
APP_KEYS=(ollama lmstudio chrome vscode chatgpt claude ffmpeg whisper)
APP_DESC=("Ollama (runs the models, needed for the model step)" "LM Studio (model app with a GUI)" "Google Chrome" "VS Code" "ChatGPT desktop app (cloud, for side-by-side)" "Claude desktop app (cloud, for side-by-side)" "ffmpeg (audio and video tools)" "whisper.cpp + large-v3-turbo model, ~1.6GB (local speech-to-text)")
M_LABEL=(); M_ON=()
for ((i=0;i<${#APP_KEYS[@]};i++)); do
  M_LABEL+=("${APP_DESC[$i]}")
  if [[ -n "${APPS:-}" ]]; then [[ " $APPS " == *" ${APP_KEYS[$i]} "* ]] && M_ON+=(1) || M_ON+=(0); else M_ON+=(1); fi
done
if [[ -z "${APPS:-}" ]]; then say "Apps (all ticked by default)"; menu "Apps to install:"; fi
WANT=" "; for ((i=0;i<${#APP_KEYS[@]};i++)); do [[ ${M_ON[$i]} -eq 1 ]] && WANT+="${APP_KEYS[$i]} "; done
want(){ [[ "$WANT" == *" $1 "* ]]; }

# ───────────────────────── 4. Pick models ─────────────────────────
if [[ -z "${MODELS:-}" ]]; then
  if want ollama || command -v ollama >/dev/null 2>&1; then
    say "Models for a ${RAM_GB}GB Mac (recommended ones are ticked)"
    dim "  Checking live sizes from the Ollama library..."
    M_LABEL=(); M_ON=(); TAGS=(); SIZES=()
    for row in "${CATALOGUE[@]}"; do
      tag=${row%%|*}; desc=${row#*|}; s=$(size_gb "$tag"); f=$(fit "$s")
      TAGS+=("$tag"); SIZES+=("$s")
      M_LABEL+=("$(printf '%-24s %6sGB  %-8s %s' "$tag" "$s" "$f" "$desc")")
      [[ " $REC " == *" $tag "* && "$f" != "too big" ]] && M_ON+=(1) || M_ON+=(0)
    done
    menu "Models to download:"
    MODELS=""; TOTAL=0
    for ((i=0;i<${#TAGS[@]};i++)); do
      if [[ ${M_ON[$i]} -eq 1 ]]; then
        MODELS+="${TAGS[$i]} "
        TOTAL=$(awk -v t="$TOTAL" -v s="${SIZES[$i]}" 'BEGIN{ if(s!="?") t+=s; printf "%.1f", t }')
        if [[ "$(fit "${SIZES[$i]}")" == "too big" ]]; then
          echo "  ! ${TAGS[$i]} is bigger than this Mac can hold in memory. It will swap or fail to load."
        fi
      fi
    done
    MODELS=${MODELS% }
    echo "  Download total: about ${TOTAL}GB of your ${FREE_GB}GB free."
    if awk -v t="$TOTAL" -v f="$FREE_GB" 'BEGIN{exit !(t+10>f)}'; then
      echo "  ! That leaves under 10GB free. Untick something or clear space first."
      if [[ -n "$TTY" ]]; then
        if [[ ! "$(ask '  Carry on anyway? [y/N] ')" =~ ^[Yy] ]]; then echo "Nothing installed."; exit 1; fi
      fi
    fi
  else
    MODELS=""
  fi
fi

say "Plan"
echo "  Apps:   ${WANT# }"
echo "  Models: ${MODELS:-none}"
if [[ -n "$TTY" && $DRY -eq 0 ]]; then
  if [[ "$(ask '  Install this? [Y/n] ')" =~ ^[Nn] ]]; then echo "Nothing installed."; exit 0; fi
fi

# ───────────────────────── 5. Install ─────────────────────────
say "1/6 Xcode command line tools"
xcode-select -p >/dev/null 2>&1 || run "xcode-select --install"

say "2/6 Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  run 'eval "$(/opt/homebrew/bin/brew shellenv)"'
fi

say "3/6 Apps and tools"
cask_for(){ case "$1" in ollama) echo ollama-app;; lmstudio) echo lm-studio;; chrome) echo google-chrome;; vscode) echo visual-studio-code;; chatgpt) echo chatgpt;; claude) echo claude;; esac; }
for k in ollama lmstudio chrome vscode chatgpt claude; do
  want "$k" || continue
  c=$(cask_for "$k")
  if brew list --cask "$c" >/dev/null 2>&1; then
    if [[ "$k" == ollama ]]; then run "brew upgrade --cask $c || true"; fi   # newer Ollama needed for -mlx models
  else run "brew install --cask $c"; fi
done
want ffmpeg  && { brew list ffmpeg >/dev/null 2>&1 || run "brew install ffmpeg"; }
want whisper && { brew list whisper-cpp >/dev/null 2>&1 || run "brew install whisper-cpp"; }

say "4/6 Models"
if [[ -n "${MODELS:-}" ]]; then
  run "open -a Ollama"
  [[ $DRY -eq 1 ]] || until curl -s localhost:11434 >/dev/null; do sleep 1; done
  for m in $MODELS; do run "ollama pull $m"; done
else
  echo "  No models picked."
fi

say "5/6 Whisper model"
WHISPER_DIR="$HOME/whisper-models"; WHISPER_MODEL="$WHISPER_DIR/ggml-large-v3-turbo.bin"
if want whisper && [[ ! -f "$WHISPER_MODEL" ]]; then
  run "mkdir -p \"$WHISPER_DIR\""
  run "curl -fL --progress-bar -o \"$WHISPER_MODEL\" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
else
  echo "  Skipped (not picked, or already there)."
fi

# ───────────────────────── 6. Security check ─────────────────────────
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

FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if "$FW" --getglobalstate 2>/dev/null | grep -qi enabled; then ok "Firewall is on"
elif [[ $HARDEN -eq 1 ]]; then run "sudo $FW --setglobalstate on" && ok "Firewall switched on"
else bad "Firewall is off. Turn it on in System Settings > Network > Firewall, or re-run with --harden"; fi

if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then ok "FileVault disk encryption is on"
else bad "FileVault is off. Turn it on in System Settings > Privacy & Security > FileVault"; fi

command -v brew >/dev/null 2>&1 && run "brew analytics off" >/dev/null && ok "Homebrew analytics off"

if want lmstudio; then echo "  • LM Studio: keep its local server off unless you need it, and leave 'Serve on Local Network' unticked."; fi
echo "  • Only download models from sources you trust (Ollama library, official Hugging Face orgs)."
if [[ $WARN -eq 0 ]]; then ok "All checks passed"; fi

say "Done."
if [[ -n "${MODELS:-}" ]]; then echo "Try:  ollama run ${MODELS%% *} --verbose"; fi
if want whisper; then echo "Transcribe audio:  whisper-cli -m ~/whisper-models/ggml-large-v3-turbo.bin -f your-audio.wav"; fi
echo "Every token counts."
