# Quint LLM Kit
[![Apache-2.0][apache-badge]][apache-url]

[apache-badge]: https://img.shields.io/badge/license-Apache%20License%202.0-blue
[apache-url]: https://github.com/informalsystems/quint-connect/blob/main/LICENSE

![Robot illustrations doing four different tasks, with descriptions: 1. Writes specs from scratch, 2. Assit on validating specs, 3. Writes code from specs, 4. Sets up Quint Connect](https://github.com/user-attachments/assets/c5c31ab5-3769-428a-9438-b5470e7c43a4)

A containerized development environment for using Claude Code with [Quint](https://quint-lang.org/)-related agents, commands and MCP servers.

## About

This tooling was initially developed for the experiments reported in our blog post [**Reliable Software in the LLM Era**](https://quint-lang.org/posts/llm_era). We invite you to check it out to learn about our vision for LLM-assisted formal specification! Since that initial work, we've been actively using and refining these tools internally at Informal Systems for our own Quint projects.

**We welcome collaborations!** As we continue to refine and expand this toolkit for our internal use, we plan to regularly push updates to this repository. If you're interested in contributing, have suggestions, or want to share your experiences using these tools, please open an issue or reach out.

> **⚠️ DISCLAIMER**: The agents and tools in this repository were developed for internal use at Informal Systems and have not been thoroughly evaluated or tested for general public use. They are provided as-is without any warranties or guarantees. We make no representations about their suitability, reliability, or fitness for any particular purpose. Use at your own risk. We accept no responsibility or liability for any consequences, damages, or issues that may arise from using these tools.

## Overview

This project provides a Docker-based environment that includes:

- Go 1.24.1
- Python 3 with pip and venv
- Rust (latest stable via rustup)
- Node.js 20.x
- Claude Code CLI
- Common development tools (git, curl, jq, tree, etc.)
- Non-root user for security
- **Quint-specific tools:**
  - Quint CLI (for running, testing, and type-checking specs)
  - Quint Language Server (for IDE-like features)
  - Specialized agents for Quint specification work (analyzer, implementer, verifier, etc.)
  - MCP servers for Quint documentation and LSP integration
  - Pre-configured commands for common Quint workflows
- **Optional:** Foundry toolchain for Solidity development (see [FOUNDRY.md](FOUNDRY.md))

> **📌 Important:** We recommend using the [latest version of Quint](https://github.com/informalsystems/quint/releases/latest), as we are continuously making improvements to the language to make it more LLM-friendly. You can check your Quint version with `quint --version`. If you're using the Docker setup provided in this repository, the latest version is automatically installed for you.

## Prerequisites

- Docker installed on your system
- A project directory — new or existing. The tools work whether you're starting from scratch, adding a spec to an existing codebase, or generating code from a spec you've already written.

## Setup

Build the Docker image:

```bash
make build
```

This builds the Docker image tagged as `claudecode:latest`.

> **Note:** For Solidity development, you can optionally include the Foundry toolchain. See [FOUNDRY.md](FOUNDRY.md) for instructions.

## Usage

### Quick Start

The easiest way to get started:

```bash
# Build the image (includes all agents and MCP servers)
make build

# Option 1: Specify project path directly
make run DIR=~/my-project

# Option 2: Interactive prompt for project path
make run
```

**That's it!** The MCP servers (quint-lsp and quint-kb) are automatically configured on first run. All agents and commands are ready to use immediately.

## Getting started

See [GET_STARTED.md](GET_STARTED.md) for a full walkthrough of the workflow — from bootstrapping your first spec to testing, debugging, and driving your implementation.

When in doubt of what to try next, run
```
/spec:next
```

which will suggest potential next things you can try. This works from the very start (even if your project doesn't have a Quint spec yet).

## Agent Skills (no Docker required)

> **Two paths, same goal.**
> The `agentic/` commands (above) are the **Docker-native path**: they run inside the container, use MCP servers for the Quint REPL, and are optimised for Claude Code.
> The `skills/` below are the **lightweight path**: plain `quint` CLI, no Docker, any agent.
> Both cover Quint spec work — pick whichever fits your setup. If you are already in the Docker environment, prefer the slash commands; if you are not, install the skills.

The `skills/` directory contains standalone agent skills for working with Quint. They work independently of Docker — install them directly into your AI agent of choice.

| Skill | What it does |
|---|---|
| [`quint-lang`](skills/quint-lang/SKILL.md) | Full Quint language reference, CLI toolchain, distributed protocol patterns |
| [`quint-from-code`](skills/quint-from-code/SKILL.md) | Generate a Quint spec from source code (Rust, Go, TypeScript, …) or TLA+ |
| [`quint-execute-spec`](skills/quint-execute-spec/SKILL.md) | Implement code grounded by an existing Quint spec |
| [`tlaplus-to-quint`](skills/tlaplus-to-quint/SKILL.md) | Translate a TLA+ spec to Quint |
| [`quint-spec-review`](skills/quint-spec-review/SKILL.md) | Audit a spec for quality, patterns, and correctness |
| [`design-verification-framing`](skills/design-verification-framing/SKILL.md) | Frame properties and explain simulation outcomes |
| [`design-model-building-blocks`](skills/design-model-building-blocks/SKILL.md) | Derive model structure from plain-English requirements |
| [`spec-plain-english-explanation`](skills/spec-plain-english-explanation/SKILL.md) | Walk through a spec for engineers unfamiliar with formal methods |

### Install skills

**Claude Code**
```
/plugin marketplace add quint-co/quint-llm-kit
/plugin install quint-llm-kit
```

**Cursor** — open Settings → Plugins, paste `https://github.com/quint-co/quint-llm-kit`, add. Or clone this repo and open it in Cursor (auto-discovers `.cursor-plugin/plugin.json`).

**VS Code + Copilot** — clone this repo and open it in VS Code (auto-discovers `.copilot-plugin/plugin.json`).

**Codex / Gemini CLI / OpenCode / Cline / and more (macOS / Linux)**
```bash
curl -fsSL https://raw.githubusercontent.com/quint-co/quint-llm-kit/main/install.sh | bash
# or pass the platform to skip the prompt:
curl -fsSL https://raw.githubusercontent.com/quint-co/quint-llm-kit/main/install.sh | bash -s codex
```

**Windows (PowerShell)**
```powershell
iwr -useb https://raw.githubusercontent.com/quint-co/quint-llm-kit/main/install.ps1 | iex
```

**npx**
```bash
npx skills add quint-co/quint-llm-kit
```

Supported CLI platforms: `gemini`, `codex`, `opencode`, `pi`, `openclaw`, `antigravity`, `vibe`, `vscode`, `hermes`, `cline`, `kimi`, `trae`

---

## Security Notes

- The container runs as a non-root user (`dev`) for security
- Your API key is stored by Claude Code inside the container (not in the image or host)
- The container is labeled with `project=claude-code` for easy identification
- Use `make stop` to properly clean up the container when done
