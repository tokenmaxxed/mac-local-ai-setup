# Mac Local AI Setup

One command to turn a fresh Apple Silicon Mac into a local AI machine. It's the exact setup used on the TokenMaxxed channel.

## What it does
1. **Checks your hardware**: chip, memory, GPU cores, macOS build, free disk and Thunderbolt version, then works out roughly how much memory a model can use
2. **Lets you pick your apps** (all ticked by default, untick what you don't want): **Ollama**, **LM Studio**, **Chrome**, **VS Code**, the **ChatGPT** and **Claude** desktop apps (for local vs cloud side by side), **ffmpeg**, and **whisper.cpp** with the Whisper **large-v3-turbo** model (about 1.6GB)
3. **Recommends models that fit** and lets you change the picks. Sizes come live from the Ollama library, and each one is marked *fits*, *tight* or *too big* for your Mac:
   - 96GB+: `gpt-oss:20b` + `qwen3.8:27b` + `gpt-oss:120b`
   - 48GB+: `gpt-oss:20b` + `qwen3.8:27b`
   - 32GB+: `gemma4:26b-a4b-it-qat` + `gpt-oss:20b`
   - 24GB+: `gemma4:12b-it-qat` + `gpt-oss:20b`
   - 16GB: `gemma4:12b-it-qat` (or its MLX build, `gemma4:12b-mlx`)
   - 8GB: `gemma4:e2b-it-qat`
4. Shows the plan and download total against your free disk, then installs

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
bash setup.sh             # hardware check, then tick what you want
bash setup.sh --yes       # no questions, take the recommended picks
bash setup.sh --harden    # also switch on the firewall (asks for your password)
```

Skip the menus:
```bash
MODELS="gemma4:12b-it-qat gemma4:12b-mlx" bash setup.sh
APPS="ollama ffmpeg whisper" bash setup.sh
```

Read any script before you run it, including this one.

## Links
- Channel: https://www.youtube.com/@tokenmaxxed
- Site: https://tokenmaxxed.io

Every token counts.
