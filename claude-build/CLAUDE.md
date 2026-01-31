# Claude Code Docker Container Documentation for TrueNAS Scale

## Project Overview

Docker containerization stack for running Claude Code on TrueNAS Scale with security-focused egress filtering. Combines Debian Bookworm base (richtt02/claude-base with Node.js 22) and whitelist-based DEFAULT DENY firewall.

**Key Components:**
- Base: richtt02/claude-base (Node.js 22 Debian Bookworm + Claude CLI + Anthropic Tools)
- Access: Shell access via `docker exec -it claude-code bash`
- Security: Whitelist-based egress firewall (DEFAULT DENY)
- Integration: Dynamic UID/GID mapping for TrueNAS filesystem permissions
- Initialization: Two-stage (firewall setup as root → privilege drop to user)

## Build & Deployment Commands

### First-Time Setup

```bash
# Step 1: Build base image (one-time, ~3-5 minutes)
docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Step 2: Build derived image
docker compose build

# Step 3: Start container
docker compose up -d

# Step 4: Verify deployment
docker compose logs -f
```

### One-Liner Deployment

```bash
cd /path/to/docker && \
chmod +x *.sh && \
docker build -f Dockerfile.base -t richtt02/claude-base:latest . && \
docker compose build && \
docker compose up -d && \
docker compose logs -f
```

### Common Operations

```bash
# Container management
docker compose up -d          # Start container
docker compose down           # Stop container
docker compose restart        # Restart container
docker compose logs -f        # View logs

# Rebuild after changes
docker compose build          # Rebuild derived image only
docker compose build --no-cache  # Force complete rebuild

# Update base image
docker build -f Dockerfile.base -t richtt02/claude-base:latest .
docker compose build --no-cache
docker compose restart

# Update scripts only
docker compose build && docker compose restart

# Update whitelisted domains
# Edit init-firewall.sh, then:
docker compose build && docker compose up -d
```

**Access Container:**
```bash
docker exec -it claude-code bash
```

## Custom Base Image

This project uses a custom Debian-based image (`richtt02/claude-base:latest`) following Anthropic's official recommendations.

**Base Image Contents (Debian Bookworm):**
- Debian 12 (Bookworm) - Anthropic's recommended OS
- Node.js 22 - Latest LTS runtime
- Claude Code CLI (@anthropic-ai/claude-code)
- **Firewall tools:** iptables, ipset, dnsutils, iproute2
- **Developer tools:** git, gh (GitHub CLI), vim, nano, zsh, fzf, git-delta
- **Utilities:** jq, curl, gosu, procps, aggregate, man-db

**Why Debian over Alpine:**
- Official Anthropic recommendation for Claude Code
- Better compatibility with Node.js native modules
- More complete package ecosystem (git-delta, aggregate available)
- Matches Anthropic's devcontainer setup exactly

**Building the Base Image:**
```bash
# Build locally
docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Push to Docker Hub (requires login)
docker login
docker push richtt02/claude-base:latest

# Or use the helper script
chmod +x build-base.sh
./build-base.sh         # Build only
./build-base.sh push    # Build and push
```

**Updating the Base Image:**
1. Modify Dockerfile.base
2. Build: `docker build -f Dockerfile.base -t richtt02/claude-base:latest .`
3. Push: `docker push richtt02/claude-base:latest`
4. Rebuild derived image: `docker compose build --no-cache`

**Image Size:**
- Base image: ~350MB (Debian + Node.js + all tools)
- Derived image: ~355MB (just adds scripts)
- Compare to Alpine: ~80MB base, but less compatible

**Alpine to Debian Package Mapping:**

| Alpine Package | Debian Package | Notes |
|---------------|----------------|-------|
| apk | apt-get | Package manager |
| bind-tools | dnsutils | DNS utilities (nslookup, dig) |
| su-exec | gosu | Privilege dropping utility |
| adduser -D | useradd -m | User creation command |
| addgroup | groupadd | Group creation command |
| /bin/sh | /bin/bash | Default shell |

**Migration Benefits:**
- Official Anthropic recommendation (matches their devcontainer)
- Better Node.js native module compatibility
- Complete package ecosystem (git-delta, aggregate, fzf available)
- Standardized development environment
- Full control over base image versions

## Development & Testing Commands

```bash
# Test firewall rules (inside container)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com  # Should FAIL
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com  # Should SUCCEED

# View active firewall rules
docker exec claude-code iptables -L -v -n
docker exec claude-code ipset list allowed-domains

# Test UID/GID mapping
docker exec claude-code id
docker exec claude-code ls -la /workspace

# Interactive shell access
docker exec -it claude-code bash

# View initialization logs
docker logs claude-code | grep -A 20 "Firewall"
```

## Architecture Deep-Dive

### Two-Stage Initialization Pattern

The container uses a two-stage initialization to handle privileged firewall setup followed by unprivileged user execution:

**Stage 1: Firewall Setup (Root)**
- Runs as root with NET_ADMIN/NET_RAW capabilities
- Executes `/usr/local/bin/init-firewall.sh` (entrypoint.sh:10-13)
- Sets up iptables rules and ipset whitelists
- Must run in same container (shares network namespace with Claude Code)

**Stage 2: User Mapping & Privilege Drop**
- Detects/creates user based on USER_UID/USER_GID environment variables (entrypoint.sh:42-50)
- Sets ownership on /claude directory (non-recursive to preserve credential permissions)
- Drops privileges via `gosu` to unprivileged user (entrypoint.sh:72)
- Keeps container running for interactive shell access as non-root

**Critical Note:** Firewall cannot be initialized in a separate container because iptables rules are network namespace-specific. Running as sidecar would create isolated rulesets.

### Whitelist-Based Egress Firewall

Implements DEFAULT DENY security model adapted from Anthropic's official devcontainer:

**Always Allowed:**
- DNS queries (UDP port 53)
- SSH connections (TCP port 22) for git operations
- Loopback traffic (localhost)
- Local network (detected via default gateway, typically /24)

**Domain Whitelist Resolution:**
1. DNS lookup resolves domain to IP addresses (init-firewall.sh:116-126)
2. IPs added to `allowed-domains` ipset (init-firewall.sh:129-132)
3. iptables rule matches outbound traffic against ipset (init-firewall.sh:154)

**Whitelisted Domains (init-firewall.sh:107-114):**
- `api.anthropic.com` - Claude API
- `registry.npmjs.org` - npm package downloads
- `sentry.io` + `o1137031.ingest.sentry.io` - error reporting
- `statsig.anthropic.com` + `statsig.com` - feature flags
- GitHub IPs (fetched from api.github.com/meta) (init-firewall.sh:82-97)

**Adding New Domains:**
Edit init-firewall.sh:107-114 and add domain to `ALLOWED_DOMAINS` list:
```bash
ALLOWED_DOMAINS="
api.anthropic.com
registry.npmjs.org
your-new-domain.com
"
```
Then rebuild: `docker compose build && docker compose up -d`

**Default Policy:**
All outbound traffic not explicitly whitelisted is REJECTED with icmp-admin-prohibited (init-firewall.sh:144-157).

### Dynamic UID/GID Mapping

Enables seamless file permission integration with TrueNAS host filesystem:

**Default Behavior:**
- Defaults to UID=1000, GID=1000 if USER_UID/USER_GID not set (entrypoint.sh:15-17)
- Creates `claude` user/group with specified IDs

**TrueNAS Integration:**
Set environment variables in compose.yaml:
```yaml
environment:
  - USER_UID=4000
  - USER_GID=4000
```

**How It Works (entrypoint.sh:42-50):**
1. Check if UID already exists in container
2. If not, create user with `useradd -u $USER_UID`
3. If exists, reuse existing username
4. Set ownership of /claude directory (non-recursive)
5. Drop privileges via `gosu` to execute as that user

**Special Case (entrypoint.sh:19-22):**
If USER_UID=0, bypasses user creation and runs as root (not recommended for production).

### Volume Mount Structure

**`/workspace` (compose.yaml:25):**
- Working directory for projects and code
- Mounted from TrueNAS host (e.g., `/mnt/tank1/configs/claude/claude-code/workspace`)
- Files created automatically have correct ownership (USER_UID:USER_GID)

**`/claude` (compose.yaml:26):**
- Configuration and credential storage (CLAUDE_CONFIG_DIR)
- Contains API keys, session tokens, settings
- Ownership set on directory only (entrypoint.sh:54-59), not recursively
- Preserves credential file permissions created by Claude CLI

## Critical Files with Line References

**Dockerfile.base:**
- Lines 1-13: Debian Bookworm + Node.js 22 base with environment setup
- Lines 15-45: Install core packages (git, firewall tools, shells, utilities)
- Lines 47-55: Install GitHub CLI (gh) via official method
- Lines 57-60: Install fzf (fuzzy finder) from official repo
- Lines 62-68: Install git-delta v0.18.2 (syntax-highlighting pager)
- Lines 70-71: Install Claude Code CLI globally via npm
- Lines 73-75: Configure zsh with fzf integration
- Lines 77-78: Create workspace and config directories

**Dockerfile:**
- Line 4: FROM richtt02/claude-base:latest (custom base image)
- Lines 8-9: Copy scripts with explicit chmod=755
- Line 12: Fix Windows CRLF line endings (critical for shell script execution)
- Lines 15-19: Build-time verification that scripts are executable

**entrypoint.sh:**
- Lines 10-13: Execute firewall initialization as root
- Lines 19-22: Root bypass (UID=0 stays as root)
- Lines 42-50: Detect/create user with specified UID/GID
- Lines 54-59: Set /claude directory ownership (non-recursive)
- Line 72: Drop privileges via gosu and execute CMD

**init-firewall.sh:**
- Lines 38-60: Preserve Docker DNS rules during iptables reset
- Lines 82-97: Fetch GitHub IP ranges from api.github.com/meta (with fallback)
- Lines 107-126: Resolve whitelisted domains to IPs and add to ipset
- Lines 144-157: Apply DEFAULT DROP policy with ipset whitelist
- Lines 163-178: Verification tests (example.com blocked, api.github.com allowed)

**compose.yaml:**
- Lines 18-20: Required capabilities (NET_ADMIN, NET_RAW) for firewall setup
- Lines 21-23: Environment variables (CLAUDE_CONFIG_DIR, TERM)
- Lines 24-26: Volume mounts (/workspace for projects, /claude for config)

## TrueNAS-Specific Configuration

### Creating TrueNAS User

**IMPORTANT:** See [TRUENAS_SETUP.md](TRUENAS_SETUP.md) for comprehensive setup guide including security considerations.

Quick reference:
```bash
# Create group and user with UID/GID 4000
pw groupadd claude -g 4000
pw useradd claude -u 4000 -g claude -m -s /bin/bash -c "Claude Code Container Manager"

# Setup sudo permissions (NEVER use docker group)
# See TRUENAS_SETUP.md for complete sudoers configuration
```

### Setting UID/GID in compose.yaml

Edit compose.yaml and add environment variables:
```yaml
environment:
  - CLAUDE_CONFIG_DIR=/claude
  - TERM=xterm-256color
  - USER_UID=4000  # Match TrueNAS user UID
  - USER_GID=4000  # Match TrueNAS user GID
```

### Adjusting Volume Paths

Modify compose.yaml:24-26 to match your TrueNAS pool:
```yaml
volumes:
  - /mnt/YOUR_POOL/path/to/workspace:/workspace:rw
  - /mnt/YOUR_POOL/path/to/config:/claude:rw
```

### Setting Host Filesystem Ownership

On TrueNAS host (match UID/GID from container):
```bash
chown -R 4000:4000 /mnt/tank1/configs/claude/claude-code/workspace
chown -R 4000:4000 /mnt/tank1/configs/claude/claude-code/config
```

## Security Considerations

**Required Capabilities:**
- `NET_ADMIN`: Required for iptables rule manipulation
- `NET_RAW`: Required for ipset operations and raw socket access
- Without these, firewall initialization fails with "Operation not permitted"

**Firewall Verification:**
After container start, verify firewall is active:
```bash
docker exec claude-code curl -sf --connect-timeout 3 https://example.com
# Should output: curl: (7) Failed to connect... or similar (BLOCKED)

docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com
# Should succeed (ALLOWED)
```

**Line Ending Issues:**
Windows editors may save scripts with CRLF line endings, causing `/bin/sh^M: not found` errors. Dockerfile:22 automatically converts CRLF→LF, but if editing scripts directly in mounted volumes, manually fix:
```bash
dos2unix entrypoint.sh init-firewall.sh
# Or using sed:
sed -i 's/\r$//' entrypoint.sh init-firewall.sh
```

**Credential Protection:**
The /claude directory ownership is set non-recursively (entrypoint.sh:54-59) to avoid changing permissions on credential files created by Claude CLI with specific permissions.

## Deployment Verification

After deployment, verify everything is working correctly:

```bash
# 1. Container is running
docker ps | grep claude-code

# 2. Firewall blocks example.com (should FAIL)
docker exec claude-code curl -sf --connect-timeout 3 https://example.com

# 3. Firewall allows api.github.com (should SUCCEED)
docker exec claude-code curl -sf --connect-timeout 3 https://api.github.com

# 4. Claude CLI is functional
docker exec claude-code claude --version

# 5. UID/GID mapping is correct
docker exec claude-code id

# 6. Interactive shell access works
docker exec -it claude-code bash
```

**Success Indicators:**
- ✅ Container shows "Up" status in `docker ps`
- ✅ Firewall blocks example.com (curl fails with connection error)
- ✅ Firewall allows api.github.com (curl succeeds)
- ✅ Claude CLI shows version number
- ✅ Container user has correct UID/GID
- ✅ Interactive shell access works
- ✅ Files created in /workspace have correct ownership

## Common Issues

### Permission Denied on /workspace or /claude

**Symptom:** Claude Code cannot read/write files, errors like "EACCES: permission denied"

**Cause:** UID/GID mismatch between container user and host filesystem ownership

**Solution:**
1. Check container UID: `docker exec claude-code id`
2. Check host ownership: `ls -la /mnt/tank1/configs/claude/claude-code/workspace`
3. Set USER_UID/USER_GID environment variables to match host
4. Or fix host ownership: `chown -R <UID>:<GID> /mnt/.../workspace`

### Firewall Blocks Required Domain

**Symptom:** Claude Code fails to connect to API, npm install fails, etc.

**Cause:** Domain not in whitelist (init-firewall.sh:107-114)

**Solution:**
1. Identify blocked domain from error messages
2. Add to ALLOWED_DOMAINS in init-firewall.sh:
   ```bash
   ALLOWED_DOMAINS="
   api.anthropic.com
   your-required-domain.com
   "
   ```
3. Rebuild: `docker compose build && docker compose up -d`

### Container Fails: "Operation not permitted"

**Symptom:** Container exits immediately, logs show iptables errors

**Cause:** Missing NET_ADMIN or NET_RAW capabilities

**Solution:**
Ensure compose.yaml:16-18 includes:
```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW
```
Some container platforms (e.g., Kubernetes) may restrict capabilities. Verify platform supports these capabilities.

### Firewall Verification Fails During Build

**Symptom:** Build fails at init-firewall.sh verification (lines 163-178)

**Cause:** Network issues during build, or DNS resolution failure

**Solution:**
1. Ensure Docker build has internet access
2. Check DNS resolution: `docker run --rm alpine nslookup api.github.com`
3. Temporarily disable verification for debugging (not recommended for production):
   - Comment out lines 163-178 in init-firewall.sh
