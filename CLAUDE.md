# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Docker containerization projects. Currently includes:

- **claude-build/**: Docker containerization stack for running Claude Code on TrueNAS Scale with security-focused egress filtering

## Project: claude-build

A production-ready Docker container for Claude Code with whitelist-based egress firewall, designed for TrueNAS Scale deployment.

### Build Commands

```bash
# Navigate to project directory
cd claude-build

# First-time setup: Build base image (one-time, ~3-5 minutes)
docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Build the derived image
docker compose build

# Start container
docker compose up -d

# View logs
docker compose logs -f
```

### Common Operations

```bash
# Container lifecycle
docker compose up -d              # Start
docker compose down               # Stop
docker compose restart            # Restart
docker compose logs -f            # View logs

# Rebuild after changes
docker compose build              # Rebuild derived image only
docker compose build --no-cache   # Force complete rebuild

# Update base image
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
docker compose build --no-cache
docker compose restart

# Testing firewall rules (inside container)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com      # Should FAIL
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com   # Should SUCCEED

# Interactive shell access
docker exec -it claude-code bash
```

### Architecture Overview

**Two-Stage Initialization Pattern:**
1. Stage 1 (Root): Firewall setup using iptables/ipset with NET_ADMIN/NET_RAW capabilities
2. Stage 2 (User): Dynamic UID/GID mapping, privilege drop via gosu, launch ttyd/Claude Code

**Whitelist-Based Egress Firewall:**
- DEFAULT DENY policy for all outbound traffic
- Whitelisted domains: Claude API, npm registry, GitHub, Sentry, Statsig
- DNS resolution converts domains to IPs stored in ipset
- Local network auto-detected and allowed

**Key Files:**
- `Dockerfile.base`: Custom Debian Bookworm base with Node.js 22 + Claude CLI + tools
- `Dockerfile`: Derived image that adds entrypoint and firewall scripts
- `entrypoint.sh`: Two-stage initialization (firewall → user mapping → privilege drop)
- `init-firewall.sh`: Egress firewall setup adapted from Anthropic's devcontainer
- `compose.yaml`: Docker Compose configuration with NET_ADMIN/NET_RAW capabilities

### Adding Whitelisted Domains

Edit `init-firewall.sh:107-114` and add domain to `ALLOWED_DOMAINS`:
```bash
ALLOWED_DOMAINS="
api.anthropic.com
registry.npmjs.org
your-new-domain.com
"
```
Then rebuild: `docker compose build && docker compose up -d`

### UID/GID Mapping for TrueNAS

Set in `compose.yaml`:
```yaml
environment:
  - USER_UID=4000  # Match TrueNAS user
  - USER_GID=4000  # Match TrueNAS group
```

This ensures files created in mounted volumes have correct ownership on the host filesystem.

### Volume Structure

- `/workspace` - Working directory for projects (mounted from host)
- `/claude` - Configuration and credentials (CLAUDE_CONFIG_DIR, mounted from host)

### Security Notes

- Firewall must run in same container (network namespace-specific)
- NET_ADMIN and NET_RAW capabilities required for iptables operations
- Runs as unprivileged user after firewall setup (gosu privilege drop)
- Credential files in /claude preserve their original permissions

### Detailed Documentation

For comprehensive details, see `claude-build/CLAUDE.md` which includes:
- Line-by-line file references
- TrueNAS-specific configuration
- Troubleshooting common issues
- Deployment verification steps
- Alpine to Debian migration notes
