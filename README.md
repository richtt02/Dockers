# Claude Code Docker Container for TrueNAS Scale

Production-ready Docker container for running [Claude Code](https://claude.ai/code) on TrueNAS Scale with whitelist-based egress firewall security.

## Features

- **Whitelist-based egress firewall** - DEFAULT DENY policy with explicit domain whitelisting
- **Debian Bookworm Slim base** - Node.js 25 with reduced vulnerabilities
- **Two-stage initialization** - Root firewall setup → unprivileged user execution
- **Dynamic UID/GID mapping** - Seamless TrueNAS filesystem permission integration
- **Interactive shell access** - Direct access via `docker exec` for development
- **Complete dev environment** - Git, GitHub CLI, fzf, git-delta, and more

## Quick Start

### Prerequisites

- Docker 20.10+ with Compose v2.0+
- NET_ADMIN and NET_RAW capability support
- 5GB free disk space

### Installation

```bash
# Clone the repository
git clone https://github.com/richtt02/claude-truenas.git
cd claude-truenas/claude-build

# Make scripts executable
chmod +x *.sh

# Build and start the container (base image pulled automatically)
docker compose build
docker compose up -d

# Verify deployment
docker compose logs -f
```

> **Note:** The base image `richtt02/claude-base:latest` is automatically pulled from Docker Hub.
> To build it locally instead (for auditing or customization), run:
> `docker build -f Dockerfile.base -t richtt02/claude-base:latest .`

### Access the Container

```bash
# Interactive shell
docker exec -it claude-code bash

# Authenticate Claude Code
claude auth login
claude
```

## Configuration

### Environment Variables

Edit `compose.yaml` to customize:

```yaml
environment:
  - CLAUDE_CONFIG_DIR=/claude      # Configuration directory
  - TERM=xterm-256color            # Terminal type
  - USER_UID=4000                  # Match host user UID
  - USER_GID=4000                  # Match host group GID
```

### Volume Mounts

```yaml
volumes:
  - /your/workspace/path:/workspace:rw    # Projects directory
  - /your/config/path:/claude:rw          # Claude configuration
```

### Adding Whitelisted Domains

Edit `init-firewall.sh` and add domains to the `ALLOWED_DOMAINS` list:

```bash
ALLOWED_DOMAINS="
api.anthropic.com
registry.npmjs.org
your-new-domain.com
"
```

Then rebuild: `docker compose build && docker compose up -d`

## Architecture

### Two-Stage Initialization

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Firewall Setup (Root)                              │
│ • NET_ADMIN + NET_RAW capabilities                          │
│ • iptables/ipset configuration                              │
│ • DEFAULT DENY with domain whitelist                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: User Execution (Unprivileged)                      │
│ • Dynamic UID/GID mapping                                   │
│ • Privilege drop via gosu                                   │
│ • Keep container running for interactive shell access       │
└─────────────────────────────────────────────────────────────┘
```

### Firewall Security Model

**Default Policy:** REJECT all outbound traffic

**Whitelisted:**
- Anthropic API (`api.anthropic.com`)
- npm registry (`registry.npmjs.org`)
- GitHub (dynamic IP ranges from API)
- Sentry error reporting
- Statsig feature flags
- DNS queries (UDP 53)
- SSH connections (TCP 22)
- Local network (auto-detected)

**Blocked:** All other internet destinations

### Base Image Contents

Built on `node:25-bookworm-slim` (~930MB with tools):

| Category | Packages |
|----------|----------|
| Runtime | Node.js 25 |
| CLI Tools | Claude Code, GitHub CLI (gh) |
| Security | iptables, ipset, dnsutils, iproute2 |
| Development | git, vim, nano, zsh, fzf, git-delta |
| Utilities | jq, curl, gosu, procps |

## Testing

### Verify Firewall Rules

```bash
# Should FAIL (blocked domain)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com

# Should SUCCEED (whitelisted domain)
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com

# View active firewall rules
docker exec claude-code iptables -L -v -n
```

### Verify UID/GID Mapping

```bash
docker exec claude-code id
docker exec claude-code ls -la /workspace
```

## Common Operations

```bash
# Container lifecycle
docker compose up -d              # Start
docker compose down               # Stop
docker compose restart            # Restart
docker compose logs -f            # View logs

# Rebuild after changes
docker compose build              # Rebuild derived image
docker compose build --no-cache   # Force complete rebuild

# Update base image (pull latest from Docker Hub)
docker pull richtt02/claude-base:latest
docker compose build --no-cache
docker compose restart

# Or build base image locally (for customization)
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
docker compose build --no-cache
docker compose restart
```

## Documentation

| Document | Description |
|----------|-------------|
| [TRUENAS_SETUP.md](claude-build/TRUENAS_SETUP.md) | TrueNAS user/group setup with sudo whitelist security |
| [CLAUDE.md](claude-build/CLAUDE.md) | Technical documentation with line-by-line references |
| [QUICK_START.md](claude-build/QUICK_START.md) | Step-by-step deployment guide |

## Troubleshooting

### Container Won't Start

```bash
docker compose logs -f
```

Common causes:
- Missing NET_ADMIN/NET_RAW capabilities
- Volume mount permissions issues
- Firewall initialization failed

### Permission Denied Errors

```bash
# Check container UID
docker exec claude-code id

# Update USER_UID/USER_GID in compose.yaml to match host
docker compose restart
```

## Security Considerations

- **Required Capabilities:** NET_ADMIN and NET_RAW for iptables operations
- **Privilege Separation:** Firewall runs as root, then drops to unprivileged user
- **Credential Protection:** Non-recursive ownership prevents permission changes on credentials
- **Network Isolation:** DEFAULT DENY policy with explicit whitelist

## System Requirements

- **OS:** Linux-based Docker host (TrueNAS Scale, Ubuntu, Debian, etc.)
- **Docker:** Version 20.10+
- **Docker Compose:** Version 2.0+
- **Capabilities:** NET_ADMIN and NET_RAW support
- **Memory:** 512MB minimum, 1GB recommended
- **Storage:** 5GB for images and workspace

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Anthropic](https://anthropic.com) - Claude Code and the official devcontainer firewall implementation
- [Docker](https://docker.com) - Containerization technology

## Support

- **Issues:** [GitHub Issues](https://github.com/richtt02/claude-truenas/issues)
- **Documentation:** See [CLAUDE.md](claude-build/CLAUDE.md) for detailed technical docs

## Verify <meta name="google-site-verification" content="Bsq3Vq61GF81FbVMQoMRI7oaKV2hPAJsdpzZkcWVGu0" />
