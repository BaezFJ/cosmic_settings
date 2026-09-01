# AI tool installers

These scripts install the official Claude Code, Codex, and Grok Build CLIs,
the native Claude Desktop and Grok Bot Linux betas, and a desktop-menu launcher
for ChatGPT's official web app.

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

Do not run these scripts with `sudo`. Node, the CLIs, and web launchers are scoped
to your user account. The desktop installer requests sudo itself when it adds
Anthropic's repository and installs the system `claude-desktop` package.

## Desktop apps

Claude Desktop has an official beta for Ubuntu 22.04+, Debian 12+, and compatible
Debian-based distributions on amd64 and arm64. The script verifies Anthropic's
signing-key fingerprint, registers its apt repository, and installs the native
`claude-desktop` package.

Grok Bot publishes an official amd64 Debian package through Cursor's update
service. The script downloads the package, verifies its Debian metadata identifies
`grok-bot` for `amd64`, and installs it with apt. Other architectures are rejected
until an official matching artifact is available.

ChatGPT's official stable Linux package URL is not documented. The script creates
an isolated Chrome/Chromium app window for ChatGPT instead of installing an
unofficial wrapper.
