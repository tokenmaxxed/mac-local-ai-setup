# Mac Local AI Setup

One command to turn a fresh Apple Silicon Mac into a local AI machine. It's the exact setup used on the TokenMaxxed channel.

## What it does
1. Installs the Xcode command line tools and Homebrew, if they're missing
2. Installs the apps: **Ollama**, **LM Studio**, **Chrome**, **VS Code**, and the **ChatGPT** and **Claude** desktop apps (for local vs cloud side by side)
3. Installs **ffmpeg** and **whisper.cpp** for local speech-to-text
4. Checks your Mac's memory and downloads models that fit:
   - 96GB+: `gpt-oss:20b` + `qwen3.8:27b` + `gpt-oss:120b`
   - 32GB+: `gpt-oss:20b` + `qwen3.8:27b`
   - under 32GB: `gemma3:4b`
5. Downloads the Whisper **large-v3-turbo** model (about 1.6GB) to `~/whisper-models`

It skips anything you already have.

Then it runs a security check:
- Ollama only listens on your Mac (not your network or the internet)
- macOS firewall is on (`--harden` switches it on for you)
- FileVault disk encryption is on
- Homebrew analytics are off
- Reminders on LM Studio's local server and trusted model sources

## Run it
```bash
curl -fsSL https://raw.githubusercontent.com/tokenmaxxed/mac-local-ai-setup/main/setup.sh -o setup.sh
bash setup.sh --dry-run   # see what it will do first
bash setup.sh
bash setup.sh --harden    # also switch on the firewall (asks for your password)
```

Pick your own models:
```bash
MODELS="gpt-oss:20b gemma3:12b" bash setup.sh
```

Read any script before you run it, including this one.

## Links
- Channel: https://www.youtube.com/@tokenmaxxed
- Site: https://tokenmaxxed.io

Every token counts.
