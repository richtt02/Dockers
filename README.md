# Claude Code Docker Container for TrueNAS Scale

Production-ready Claude Code container for TrueNAS Scale with Docker Compose deployment. Secure, hardened containerization for running Claude Code on TrueNAS with whitelist-based firewall.

## 📦 Projects

### Claude Code Container for TrueNAS Scale

A hardened Docker container for running [Claude Code](https://claude.ai/code) on TrueNAS Scale with whitelist-based firewall security.

**Key Features:**
- 🔒 **Whitelist-based egress firewall** - DEFAULT DENY policy with explicit domain whitelisting
- 🐧 **Debian Bookworm base** - Official Anthropic-recommended OS with Node.js 22 LTS
- 🔐 **Two-stage initialization** - Root firewall setup → unprivileged user execution
- 🎯 **Dynamic UID/GID mapping** - Seamless TrueNAS filesystem permission integration
- 💻 **Interactive shell access** - Direct access via `docker exec` for development
- 🛠️ **Complete development environment** - Git, GitHub CLI, fzf, git-delta, and more

This Claude Code container is specifically designed for TrueNAS Scale deployments, providing a Docker-based environment for running Claude Code securely. The containerized approach ensures Claude Code runs isolated on TrueNAS with persistent configuration and workspace volumes.

## 🚀 Quick Start: Deploy Claude Code on TrueNAS with Docker

### Prerequisites

- Docker installed on your system (TrueNAS Scale, Linux, or macOS)
- Basic familiarity with Docker Compose
- 5GB free disk space

### Installation

```bash
# Clone the repository
git clone https://github.com/richtt02/Dockers.git
cd Dockers/claude-build

# Make scripts executable
chmod +x *.sh

# Build the base image (one-time, ~3-5 minutes)
docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Build and start the container
docker compose build
docker compose up -d

# Verify deployment
docker compose logs -f
```

### Access the Container

**Interactive Shell:**
```bash
docker exec -it claude-code bash
```

**Authenticate Claude Code:**
```bash
docker exec -it claude-code bash
claude auth login
claude
```

## 🔧 Configuration: TrueNAS Docker Setup for Claude Code

### Environment Variables

Edit `compose.yaml` to customize:

```yaml
environment:
  - CLAUDE_CONFIG_DIR=/claude      # Configuration directory
  - TERM=xterm-256color             # Terminal type
  - USER_UID=4000                   # Match host user UID
  - USER_GID=4000                   # Match host group GID
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

Then rebuild and restart:
```bash
docker compose build && docker compose up -d
```

## 🏗️ Docker Container Architecture for TrueNAS

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
- ✅ Anthropic API (`api.anthropic.com`)
- ✅ npm registry (`registry.npmjs.org`)
- ✅ GitHub (dynamic IP ranges from API)
- ✅ Sentry error reporting
- ✅ Statsig feature flags
- ✅ DNS queries (UDP 53)
- ✅ SSH connections (TCP 22)
- ✅ Local network (auto-detected)

**Blocked:**
- ❌ All other internet destinations

### Custom Base Image

Built on `node:22-bookworm` with:
- **Runtime:** Node.js 22 LTS
- **CLI Tools:** Claude Code, GitHub CLI (gh)
- **Security:** iptables, ipset, firewall utilities
- **Development:** git, vim, nano, zsh, fzf, git-delta
- **Utilities:** jq, curl, gosu, procps

**Image Size:** ~355MB (base: ~350MB)

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [TRUENAS_SETUP.md](claude-build/TRUENAS_SETUP.md) | TrueNAS user/group setup with security analysis |
| [CLAUDE.md](claude-build/CLAUDE.md) | Comprehensive technical documentation with line-by-line references |
| [QUICK_START.md](claude-build/QUICK_START.md) | Step-by-step deployment guide for TrueNAS Scale |

## 🧪 Testing

### Verify Firewall Rules

```bash
# Should FAIL (blocked domain)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com

# Should SUCCEED (whitelisted domain)
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com

# View active firewall rules
docker exec claude-code iptables -L -v -n

# View whitelisted IPs
docker exec claude-code ipset list allowed-domains
```

### Verify UID/GID Mapping

```bash
# Check container user
docker exec claude-code id

# Check workspace permissions
docker exec claude-code ls -la /workspace
```

### Verify Claude Code

```bash
# Check version
docker exec claude-code claude --version

# Check authentication status
docker exec claude-code claude auth status
```

## 🛠️ Common Operations

```bash
# Container lifecycle
docker compose up -d              # Start
docker compose down               # Stop
docker compose restart            # Restart
docker compose logs -f            # View logs

# Rebuild after changes
docker compose build              # Rebuild derived image
docker compose build --no-cache   # Force complete rebuild

# Update base image
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
docker compose build --no-cache
docker compose restart
```

## 🐛 Troubleshooting Claude Code Container on TrueNAS

### Container Won't Start

**Check logs:**
```bash
docker compose logs -f
```

**Common causes:**
- Missing NET_ADMIN/NET_RAW capabilities
- Volume mount permissions issues
- Firewall initialization failed

### Firewall Not Working

**Verify capabilities:**
```bash
grep -A 3 "cap_add" compose.yaml
# Should show: NET_ADMIN and NET_RAW
```

### Permission Denied Errors

**Fix UID/GID mapping:**
```bash
# Check container UID
docker exec claude-code id

# Update compose.yaml environment variables
# Then restart container
docker compose restart
```

## 🔐 Security Considerations

- **Required Capabilities:** NET_ADMIN and NET_RAW for iptables operations
- **Privilege Separation:** Firewall runs as root, then drops to unprivileged user
- **Credential Protection:** Non-recursive ownership prevents permission changes on credentials
- **Network Isolation:** DEFAULT DENY policy with explicit whitelist
- **Updates:** Regularly rebuild base image to get latest security patches

## 📋 System Requirements

- **OS:** Linux-based Docker host (TrueNAS Scale, Ubuntu, Debian, etc.)
- **Docker:** Version 20.10 or higher
- **Docker Compose:** Version 2.0 or higher
- **Capabilities:** NET_ADMIN and NET_RAW support
- **Memory:** 512MB minimum, 1GB recommended
- **Storage:** 5GB for images and workspace

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is provided as-is for personal and commercial use.

## 🙏 Acknowledgments

- **Anthropic** - For Claude Code and the official devcontainer firewall implementation
- **Docker** - For containerization technology

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/richtt02/Dockers/issues)
- **Documentation:** See [CLAUDE.md](claude-build/CLAUDE.md) for detailed technical documentation
- **Quick Start:** See [QUICK_START.md](claude-build/QUICK_START.md) for deployment guide

## 🔄 Version History

See commit history for changes and updates.

---

**Built with ❤️ for secure Claude Code deployments**
