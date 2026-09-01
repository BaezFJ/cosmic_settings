# AI tool installers

These scripts install the official Claude Code, Codex, and Grok Build CLIs and
create desktop-menu launchers for their official web apps on COSMIC/Linux.

## Install

```bash
cd scripts
./install-node-latest.sh --lts
./install-ai-tools.sh
```

Install a subset with `--only` (repeat it to select more than one):

```bash
./install-ai-clis.sh --only claude --only codex
./install-ai-desktop-apps.sh --only chatgpt
```

Preview without changing anything:

```bash
./install-ai-tools.sh --dry-run
```

The CLI script uses only vendor-supported installers:

- Claude Code: npm package `@anthropic-ai/claude-code`
- Codex CLI: npm package `@openai/codex`
- Grok Build: xAI's `https://x.ai/cli/install.sh`

Do not run these scripts with `sudo`. Node is installed through nvm and all AI
tools and launchers are scoped to your user account.

## Desktop app note

Claude Desktop and Grok Bot do not currently have official Linux builds. The
desktop script therefore makes isolated Chrome/Chromium app windows for the
official web services instead of installing an unofficial wrapper. ChatGPT has
announced a Linux desktop preview, but its official stable package URL is not
currently documented; its launcher also uses the official web app for now.
