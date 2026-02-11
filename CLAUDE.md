# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Docker container for running Claude Code on TrueNAS Scale with integrated VS Code (code-server) and whitelist-based egress firewall. All source files are in `claude-build/`.

**Always read `claude-build/CLAUDE.md` for technical deep-dive with line-by-line file references, troubleshooting, and deployment verification.**

## Build & Run

All commands run from `claude-build/`:

```bash
cd claude-build

# First-time setup
cp .env.example .env   # Configure USER_UID, paths, SECURE_PASSWORD (all required)
docker compose build   # Base image pulled automatically from Docker Hub
docker compose up -d

# Rebuild after script/Dockerfile changes
docker compose build && docker compose up -d

# Rebuild base image locally (for Dockerfile.base changes)
docker build -f Dockerfile.base -t richtt02/claude-base:1.1 .
docker compose build --no-cache && docker compose restart

# Verify firewall
docker exec claude-code curl -sf --connect-timeout 3 https://example.com      # Should FAIL
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com   # Should SUCCEED
```

## Architecture

**Two-image build:**
- `Dockerfile.base` → `richtt02/claude-base:1.1` (Debian Bookworm Slim + Node.js 25 + Claude CLI + code-server + tools). Published to Docker Hub; only rebuild locally when changing base packages.
- `Dockerfile` → derived image. Copies `entrypoint.sh` and `init-firewall.sh` into the base. This is what `docker compose build` builds.

**Two-stage initialization (`entrypoint.sh`):**
1. **Root stage:** Runs `init-firewall.sh` (iptables/ipset DEFAULT DENY firewall). Failure is fatal — container refuses to start unprotected.
2. **User stage:** Creates/maps user to `USER_UID:USER_GID` (default 4000:4000), sets `/claude` ownership (non-recursive to preserve credential permissions), starts code-server in background, drops privileges via `gosu`.

**Why single container:** iptables rules are network-namespace-specific. A sidecar container would have its own isolated ruleset and wouldn't protect Claude Code.

## Key Files (claude-build/)

| File | Purpose |
|------|---------|
| `Dockerfile.base` | Base image: Debian packages, Node.js, Claude CLI, code-server, gh, fzf, git-delta |
| `Dockerfile` | Derived image: copies scripts, fixes CRLF line endings, verifies executability |
| `entrypoint.sh` | Init orchestrator: firewall → UID/GID mapping → code-server → privilege drop |
| `init-firewall.sh` | Egress firewall: DNS resolution, ipset whitelist, GitHub IP ranges, DEFAULT DROP |
| `compose.yaml` | Container config: NET_ADMIN/NET_RAW caps, volume mounts, env vars, health check, resource limits |
| `.env.example` | Required env vars template (no hardcoded defaults in compose.yaml) |

## Common Modifications

**Add a whitelisted domain:** Edit `init-firewall.sh` `ALLOWED_DOMAINS` list (line ~113), then `docker compose build && docker compose up -d`.

**Change base image packages:** Edit `Dockerfile.base`, rebuild base: `docker build -f Dockerfile.base -t richtt02/claude-base:1.1 .`, then `docker compose build --no-cache`.

**Update Claude CLI version:** Change the version in `Dockerfile.base` (`npm install -g @anthropic-ai/claude-code@<version>`), rebuild base image.

**Update code-server version:** Change `CODE_SERVER_VERSION` in `Dockerfile.base`, rebuild base image.

**Adjust UID/GID:** Edit `.env` file (`USER_UID`, `USER_GID`), then `docker compose restart`.

**Modify entrypoint or firewall logic:** Edit `entrypoint.sh` or `init-firewall.sh`, then `docker compose build && docker compose up -d`. If editing on Windows, the Dockerfile automatically converts CRLF→LF.

## Firewall Domain Whitelist

Defined in `init-firewall.sh`. DNS resolved once at startup and cached in ipset.

- `api.anthropic.com` — Claude API
- `registry.npmjs.org` — npm packages
- `sentry.io`, `o1137031.ingest.sentry.io` — error reporting
- `statsig.anthropic.com`, `statsig.com` — feature flags
- `open-vsx.org`, `www.open-vsx.org` — VS Code extensions
- GitHub IPs — fetched dynamically from `api.github.com/meta` (with hardcoded fallback)
- DNS (UDP 53), SSH (TCP 22), loopback, local network (/24 auto-detected) — always allowed

## Volume Mounts

| Container Path | Purpose |
|---------------|---------|
| `/workspace` | Working directory for projects |
| `/claude` | Claude config and credentials (CLAUDE_CONFIG_DIR) |
| `/home/claude/.config/code-server` | VS Code settings and extensions |

## Access

- **VS Code Web UI:** `http://<host>:8443` (password from `SECURE_PASSWORD` in `.env`)
- **Shell:** `docker exec -it claude-code bash`
- **Claude CLI:** Open terminal in VS Code and run `claude`

## Additional Documentation

- `claude-build/CLAUDE.md` — Technical deep-dive with line references, troubleshooting, deployment verification
- `claude-build/TRUENAS_SETUP.md` — TrueNAS user/group creation, sudo whitelist configuration
- `claude-build/QUICK_START.md` — Step-by-step deployment guide
