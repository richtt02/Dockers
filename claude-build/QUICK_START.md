# Quick Start: Deploy to TrueNAS

## Prerequisites
✅ Docker installed on TrueNAS
✅ SSH access to TrueNAS
✅ Files transferred to TrueNAS

## 5-Step Deployment

### Step 1: Transfer Files
```powershell
# From Windows PowerShell
scp -r C:\Users\Richard\Desktop\docker\* root@<truenas-ip>:/mnt/tank1/configs/claude/docker/
```

### Step 2: SSH to TrueNAS
```bash
ssh root@<truenas-ip>
cd /mnt/tank1/configs/claude/docker/
```

### Step 3: Build Base Image
```bash
chmod +x build-base.sh
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
```
⏱️ Build time: ~3-5 minutes

### Step 4: Build & Start Container
```bash
docker compose build
docker compose up -d
```

### Step 5: Verify
```bash
# Check logs
docker compose logs -f

# Test firewall (should FAIL)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com

# Test firewall (should SUCCEED)
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com

# Access container
docker exec -it claude-code bash
```

## All-in-One Command

```bash
cd /mnt/tank1/configs/claude/docker/ && \
chmod +x *.sh && \
docker build -f Dockerfile.base -t richtt02/claude-base:latest . && \
docker compose build && \
docker compose up -d && \
echo "✅ Deployment complete! Access via: docker exec -it claude-code bash"
```

## Common Commands

### Container Management
```bash
docker compose up -d          # Start container
docker compose down           # Stop container
docker compose restart        # Restart container
docker compose logs -f        # View logs
docker compose build          # Rebuild derived image
```

### Base Image Management
```bash
# Rebuild base image
docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Push to Docker Hub (optional)
docker login
docker push richtt02/claude-base:latest

# Pull from Docker Hub (if pushed)
docker pull richtt02/claude-base:latest
```

### Testing
```bash
# Firewall tests
docker exec claude-code curl -sf --connect-timeout 3 https://example.com      # BLOCKED
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com   # ALLOWED

# View firewall rules
docker exec claude-code iptables -L -v -n
docker exec claude-code ipset list allowed-domains

# Check user mapping
docker exec claude-code id
docker exec claude-code ls -la /workspace

# Interactive shell
docker exec -it claude-code bash
```

### Claude Code Setup
```bash
# Interactive shell
docker exec -it claude-code bash

# Inside container
claude auth login    # Login to Claude
claude               # Start Claude Code
```

## Troubleshooting

### Container won't start
```bash
docker compose logs -f           # Check error logs
docker compose down              # Stop container
docker compose build --no-cache  # Rebuild
docker compose up -d             # Start again
```

### Firewall not working
```bash
# Verify capabilities in compose.yaml
grep -A 3 "cap_add" compose.yaml
# Should show: NET_ADMIN and NET_RAW

# Check firewall rules
docker exec claude-code iptables -L -v -n
```

### Permission issues
```bash
# Check container UID/GID
docker exec claude-code id

# Fix host permissions
chown -R 1000:1000 /mnt/tank1/configs/claude/claude-code/workspace
chown -R 1000:1000 /mnt/tank1/configs/claude/claude-code/config

# Or set in compose.yaml
# environment:
#   - USER_UID=4000
#   - USER_GID=4000
```

### Web terminal not accessible
```bash
# Check container is running
docker ps | grep claude-code

# Check container is accessible
docker exec -it claude-code bash
```

## File Structure
```
/mnt/tank1/configs/claude/docker/
├── Dockerfile.base              ← Base image definition
├── Dockerfile                   ← Derived image (scripts only)
├── entrypoint.sh                ← Container initialization
├── init-firewall.sh             ← Firewall setup
├── compose.yaml                 ← Docker Compose config
├── build-base.sh                ← Base image build helper
├── CLAUDE.md                    ← Full documentation
├── IMPLEMENTATION_SUMMARY.md    ← Deployment guide
├── TRANSFER_GUIDE.md            ← Transfer instructions
├── CHANGELOG.md                 ← Version history
└── QUICK_START.md               ← This file

/mnt/tank1/configs/claude/claude-code/
├── workspace/                   ← Your projects (mounted to /workspace)
└── config/                      ← Claude config (mounted to /claude)
```

## Success Indicators

✅ Container running: `docker ps | grep claude-code`
✅ Shell access: `docker exec -it claude-code bash` works
✅ Firewall blocking: `curl https://example.com` fails
✅ Firewall allowing: `curl https://api.github.com` succeeds
✅ Claude CLI: `claude --version` shows version

## What's Different from Alpine Version?

| Aspect | Old (Alpine) | New (Debian) |
|--------|-------------|--------------|
| Base Image | nezhar/claude-container | richtt02/claude-base |
| OS | Alpine Linux | Debian 12 Bookworm |
| Size | ~90MB | ~355MB |
| Build Steps | 1 (compose build) | 2 (base + compose) |
| Compatibility | Limited | Full Anthropic support |

## Need More Help?

📖 **Full Documentation:** See `CLAUDE.md`
🚀 **Deployment Guide:** See `IMPLEMENTATION_SUMMARY.md`
📦 **Transfer Guide:** See `TRANSFER_GUIDE.md`
📝 **Version History:** See `CHANGELOG.md`

## Optional: Push Base Image to Docker Hub

Benefits:
- Faster deployment on new machines
- No need to rebuild base image
- Can be reused in other projects

```bash
# One-time setup
docker login
# Username: richtt02
# Password: <your-password>

# Push base image
docker push richtt02/claude-base:latest

# On other machines (skip base build)
docker pull richtt02/claude-base:latest
docker compose build
docker compose up -d
```

## Maintenance

### Update Base Image
```bash
# Edit Dockerfile.base as needed
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
docker push richtt02/claude-base:latest  # If using Docker Hub
docker compose build --no-cache
docker compose restart
```

### Update Scripts Only
```bash
# Edit entrypoint.sh or init-firewall.sh
docker compose build
docker compose restart
```

### Update Whitelisted Domains
```bash
# Edit init-firewall.sh (lines 107-114)
# Add domains to ALLOWED_DOMAINS list
docker compose build
docker compose restart
```

---

**Ready to deploy!** Follow Step 1-5 above to get started.
