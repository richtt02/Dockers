# TrueNAS User/Group Setup Guide

## Overview

This guide explains how to create and configure a dedicated TrueNAS user/group for managing the Claude Code Docker container. Proper user setup is critical for:

- **Security:** Following the principle of least privilege
- **File Ownership:** Ensuring correct permissions on mounted volumes
- **Access Control:** Limiting what the user can do on the TrueNAS system

## Security Approach: Sudo Whitelist (Least Privilege)

### ❌ Why NOT Docker Group

Adding a user to the `docker` group is **root-equivalent access** and violates security best practices:

**Security problems with docker group membership:**
- Can run containers with `--privileged` flag (full kernel access)
- Can mount any host path including `/root`, `/etc`, `/boot`
- Can run containers as UID 0 and modify the host filesystem
- Can escape to root access on the host system
- No audit trail of actions performed
- If user account is compromised, entire host is compromised

**Example attack scenario:**
```bash
# User in docker group can become root like this:
docker run -it --privileged --pid=host alpine nsenter -t 1 -m -u -n -i sh
# Now has full root shell on the host
```

### ✅ The Secure Approach: Sudo Whitelist

**Benefits of using sudo with specific commands:**
- ✅ Follows principle of least privilege
- ✅ Limits access to ONLY necessary docker commands
- ✅ Audit trail via sudo logs (`/var/log/auth.log`)
- ✅ Passwordless for convenience
- ✅ Cannot escalate to full root access
- ✅ Can be further restricted to specific containers if needed

**What gets logged:**
```
Jan 31 10:23:45 truenas sudo: claude : TTY=pts/0 ; PWD=/home/claude ; USER=root ; COMMAND=/bin/docker compose up -d
```

## Setup Instructions

### Step 1: Create TrueNAS User/Group

SSH to your TrueNAS system and run:

```bash
# Create group with GID 4000
pw groupadd claude -g 4000

# Create user with UID 4000
pw useradd claude -u 4000 -g claude -m -s /bin/bash -c "Claude Code Container Manager"

# Set a password for the user (for SSH login)
passwd claude
# Enter password when prompted
```

**Notes:**
- UID/GID 4000 is chosen to avoid conflicts with standard system users
- You can use any UID/GID >= 1000, just ensure it matches across all configurations
- The `-m` flag creates a home directory at `/home/claude`
- The `-s /bin/bash` gives the user a proper shell for interactive use

**Verification:**
```bash
# Verify user was created correctly
id claude
# Should show: uid=4000(claude) gid=4000(claude) groups=4000(claude)
```

### Step 2: Configure Sudo Permissions via TrueNAS GUI (Least Privilege)

**IMPORTANT:** Do NOT add the user to the docker group. Use the TrueNAS GUI to configure sudo permissions instead.

**Why GUI over manual sudoers file?**
- GUI settings persist across TrueNAS system updates
- Manual sudoers files in `/usr/local/etc/sudoers.d/` may be overwritten during upgrades
- Easier to audit and modify through the web interface

**Steps:**

1. Navigate to **Credentials > Local Users** in the TrueNAS web interface
2. Click the **Edit** (pencil icon) button on the `claude` user
3. Scroll down to the **Sudo** section
4. Configure the following settings:
   - Enable **Sudo Commands** checkbox
   - In the **Allowed sudo commands** field, enter (one command per line):
     ```
     /bin/docker compose up *
     /bin/docker compose down *
     /bin/docker compose build *
     /bin/docker compose restart *
     /bin/docker compose logs *
     /bin/docker compose pull *
     /bin/docker compose ps
     /bin/docker exec *
     /bin/docker ps
     /bin/docker logs *
     /bin/docker build *
     /bin/docker images
     ```

   > **Tip:** For easy copy-paste, open [sudo-commands.txt](sudo-commands.txt) and copy the entire contents. On GitHub, click "Raw" to get plain text that preserves line breaks.

   - Enable **Sudo Commands No Password** checkbox for passwordless execution
5. Click **Save**

**Understanding the command whitelist:**

| Command | Wildcard | Effect |
|---------|----------|--------|
| `/bin/docker compose up *` | Yes | Allows `docker compose up -d`, `docker compose up --build`, etc. |
| `/bin/docker compose ps` | No | Only allows `docker compose ps` with no arguments |
| `/bin/docker ps` | No | Only allows `docker ps` (not `docker ps -a`) |
| `/bin/docker images` | No | Only allows `docker images` (no filtering flags) |

**Note:** Commands without `*` only work with no arguments. Add `*` if you need to pass flags or arguments.

**Verification:**
```bash
# Switch to claude user
su - claude

# Test sudo permissions (should work without password)
sudo docker ps

# Test a command NOT in the whitelist (should fail)
sudo docker network create test
# Should show: Sorry, user claude is not allowed to execute...

# Exit back to root
exit
```

### Step 3: Setup File Ownership

Create directories for the container volumes and set correct ownership:

```bash
# Create directories (as root)
mkdir -p /mnt/tank1/configs/claude/claude-code/workspace
mkdir -p /mnt/tank1/configs/claude/claude-code/config

# Set ownership (UID:GID must match container environment variables)
chown -R 4000:4000 /mnt/tank1/configs/claude/claude-code/workspace
chown -R 4000:4000 /mnt/tank1/configs/claude/claude-code/config

# Set permissions
chmod 755 /mnt/tank1/configs/claude/claude-code/workspace
chmod 755 /mnt/tank1/configs/claude/claude-code/config
```

**Verification:**
```bash
# Check ownership
ls -la /mnt/tank1/configs/claude/claude-code/
# Should show directories owned by UID 4000, GID 4000

# Test access as claude user
su - claude
touch /mnt/tank1/configs/claude/claude-code/workspace/test.txt
ls -la /mnt/tank1/configs/claude/claude-code/workspace/test.txt
# Should show file owned by claude:claude
rm /mnt/tank1/configs/claude/claude-code/workspace/test.txt
exit
```

### Step 4: Configure compose.yaml

Edit your `compose.yaml` to set the UID/GID environment variables:

```yaml
# Security Note: Set USER_UID and USER_GID to match your TrueNAS user
# For user creation and permission setup, see TRUENAS_SETUP.md
environment:
  - CLAUDE_CONFIG_DIR=/claude
  - TERM=xterm-256color
  - USER_UID=4000  # Must match TrueNAS user UID
  - USER_GID=4000  # Must match TrueNAS user GID
```

**Important:** The UID/GID values here MUST match:
1. The UID/GID used when creating the TrueNAS user (Step 1)
2. The ownership of the volume directories (Step 3)

### Step 5: Setup SSH Access (Optional but Recommended)

For easier remote management, configure SSH access for the claude user:

```bash
# As root, allow SSH for claude user (if not already allowed)
# Edit /etc/ssh/sshd_config and ensure:
# - PermitRootLogin no (disable root SSH for security)
# - AllowUsers claude (whitelist specific users)

# Restart SSH service
service sshd restart
```

**For password-less SSH access (more secure):**
```bash
# On your client machine (Windows/Linux/Mac)
ssh-keygen -t ed25519 -C "claude@truenas"
# Press Enter to accept defaults

# Copy public key to TrueNAS
ssh-copy-id claude@your-truenas-ip
# Enter password when prompted

# Test SSH access (should not ask for password)
ssh claude@your-truenas-ip
```

### Step 6: Verification

Complete verification of the setup:

```bash
# SSH to TrueNAS as claude user
ssh claude@your-truenas-ip

# Verify user identity
id
# Should show: uid=4000(claude) gid=4000(claude)

# Verify sudo permissions work
sudo docker ps
# Should execute without password and show running containers

# Verify file access
ls -la /mnt/tank1/configs/claude/claude-code/workspace
# Should be able to read directory

# Test container management
cd /mnt/tank1/configs/claude/docker/
sudo docker compose up -d
sudo docker compose ps

# Test container access
sudo docker exec -it claude-code bash
# Inside container:
id
# Should show uid=4000(claude) gid=4000(claude)
whoami
# Should show: claude
exit
```

## Usage Examples

### Daily Operations

```bash
# SSH to TrueNAS as claude user
ssh claude@your-truenas-ip

# Navigate to docker directory
cd /mnt/tank1/configs/claude/docker/

# Start container
sudo docker compose up -d

# View logs
sudo docker compose logs -f

# Stop container
sudo docker compose down

# Restart container
sudo docker compose restart

# Access Claude Code interactively
sudo docker exec -it claude-code bash
# Inside container:
claude auth login
claude
```

### Building and Updating

```bash
# SSH to TrueNAS
ssh claude@your-truenas-ip
cd /mnt/tank1/configs/claude/docker/

# Build base image (first time or after updates)
sudo docker build -f Dockerfile.base -t richtt02/claude-base:latest .

# Build derived image
sudo docker compose build

# Rebuild with no cache
sudo docker compose build --no-cache

# Start/restart after build
sudo docker compose up -d
```

### Maintenance

```bash
# View running containers
sudo docker ps

# View all containers
sudo docker ps -a

# View logs for specific container
sudo docker logs claude-code

# View container resource usage
sudo docker stats claude-code

# Access container shell for debugging
sudo docker exec -it claude-code bash
```

## Security Best Practices

### 1. ✅ NEVER Add User to Docker Group

**Don't do this:**
```bash
# INSECURE - DO NOT DO THIS
pw groupmod docker -m claude
```

This gives root-equivalent access and violates the principle of least privilege.

### 2. ✅ Use Sudo Whitelist Instead

Only allow the specific docker commands needed, as shown in Step 2.

### 3. ✅ Regularly Audit Sudo Logs

```bash
# View sudo command history for claude user
grep claude /var/log/auth.log | grep sudo

# View recent docker commands
grep "docker" /var/log/auth.log | tail -20
```

### 4. ✅ Use SSH Key Authentication

Disable password authentication for SSH once keys are set up:

```bash
# Edit /etc/ssh/sshd_config
PasswordAuthentication no
PubkeyAuthentication yes

# Restart SSH
service sshd restart
```

### 5. ✅ Limit SSH Access by IP (If Possible)

If you always connect from the same IP or network:

```bash
# Edit /etc/ssh/sshd_config
# Add:
AllowUsers claude@192.168.1.0/24

# Or for specific IP:
AllowUsers claude@192.168.1.100
```

### 6. ✅ Keep System Updated

```bash
# Regularly update TrueNAS
# Use the TrueNAS web UI: System > Update

# Update Docker images
sudo docker pull richtt02/claude-base:latest
sudo docker compose pull
sudo docker compose up -d
```

### 7. ✅ Monitor Container Activity

```bash
# Check what containers are running
sudo docker ps

# View container logs regularly
sudo docker logs --since 24h claude-code

# Monitor resource usage
sudo docker stats --no-stream
```

### 8. ✅ Backup Configuration

```bash
# Backup Claude configuration and credentials
tar -czf claude-backup-$(date +%Y%m%d).tar.gz \
  /mnt/tank1/configs/claude/claude-code/config

# Store backup in a separate location
mv claude-backup-*.tar.gz /mnt/tank1/backups/
```

## UID/GID Mapping Explanation

Understanding how UID/GID mapping works is crucial for proper file permissions:

### How It Works

1. **Container creates files with USER_UID:USER_GID**
   - Inside container, process runs as user with UID 4000, GID 4000
   - Files created inherit this ownership

2. **Host filesystem sees numeric UID/GID**
   - Host doesn't care about usernames
   - Only numeric UID/GID values matter
   - Files created by container appear owned by UID 4000 on host

3. **TrueNAS user matches the UID/GID**
   - TrueNAS user `claude` has UID 4000, GID 4000
   - Therefore, TrueNAS user can read/write container files
   - Usernames don't have to match (though it's clearer if they do)

### Example

```bash
# Inside container
$ id
uid=4000(claude) gid=4000(claude)

$ touch /workspace/myfile.txt
$ ls -la /workspace/myfile.txt
-rw-r--r-- 1 claude claude 0 Jan 31 10:00 myfile.txt

# On TrueNAS host
$ ls -la /mnt/tank1/configs/claude/claude-code/workspace/myfile.txt
-rw-r--r-- 1 claude claude 0 Jan 31 10:00 myfile.txt

# Same file, same ownership, because UIDs match
```

### Why Usernames Don't Matter

```bash
# Even if you named the TrueNAS user differently:
pw useradd bob -u 4000 -g 4000 -m -s /bin/bash

# The user "bob" could still access files created by container user "claude"
# because they both have UID 4000

$ id bob
uid=4000(bob) gid=4000(bob)

$ ls -la /workspace/myfile.txt
-rw-r--r-- 1 bob bob 0 Jan 31 10:00 myfile.txt
# Shows "bob" because TrueNAS maps UID 4000 to username "bob"
```

### Common Pitfall: Mismatched UIDs

```bash
# If you create TrueNAS user with wrong UID:
pw useradd claude -u 5000 -g 5000  # WRONG - doesn't match container

# Container creates files as UID 4000
# TrueNAS user claude is UID 5000
# Result: Permission denied when claude tries to access files

$ ls -la /workspace/myfile.txt
-rw-r--r-- 1 4000 4000 0 Jan 31 10:00 myfile.txt
# Shows numeric UID because no user with UID 4000 exists

$ cat /workspace/myfile.txt
cat: /workspace/myfile.txt: Permission denied
```

## Troubleshooting

### Problem: "Permission denied" when running docker commands

**Symptom:**
```bash
$ docker ps
Got permission denied while trying to connect to the Docker daemon socket
```

**Cause:** User not in docker group and sudo not configured

**Solution:** Follow Step 2 to configure sudo, then use `sudo docker ps`

### Problem: Files created in container have wrong ownership

**Symptom:** Files owned by UID 1000 instead of 4000, or permission denied errors

**Cause:** USER_UID/USER_GID not set in compose.yaml

**Solution:**
1. Add environment variables to compose.yaml (Step 4)
2. Restart container: `sudo docker compose down && sudo docker compose up -d`
3. Fix existing file ownership: `sudo chown -R 4000:4000 /mnt/tank1/.../workspace`

### Problem: Cannot access workspace from container

**Symptom:** `/workspace` is empty or shows "Permission denied" inside container

**Cause:** Host directory not owned by USER_UID:USER_GID

**Solution:**
```bash
# On TrueNAS host
sudo chown -R 4000:4000 /mnt/tank1/configs/claude/claude-code/workspace
sudo chmod -R 755 /mnt/tank1/configs/claude/claude-code/workspace

# Restart container
sudo docker compose restart
```

### Problem: Sudo asks for password

**Symptom:** `sudo docker ps` prompts for password

**Cause:** Sudo permissions not configured correctly in TrueNAS GUI

**Solution:**
1. Navigate to **Credentials > Local Users** in the TrueNAS web interface
2. Click **Edit** on the `claude` user
3. Scroll to the **Sudo** section
4. Verify **Sudo Commands No Password** is enabled
5. Verify **Allowed sudo commands** contains the required commands
6. Click **Save**

### Problem: "User is not allowed to execute" error

**Symptom:** `sudo: Sorry, user claude is not allowed to execute '/bin/docker xyz'`

**Cause:** Command not in sudo whitelist

**Solution:**
1. Identify exact command path: `which docker` → `/bin/docker`
2. Navigate to **Credentials > Local Users** in the TrueNAS web interface
3. Click **Edit** on the `claude` user
4. Add the missing command to **Allowed sudo commands** (use `*` wildcard if arguments are needed)
5. Click **Save**

### Problem: Cannot SSH to TrueNAS as claude user

**Symptom:** SSH connection refused or "Permission denied"

**Cause:** SSH not configured for user, or firewall blocking

**Solution:**
```bash
# Verify SSH service is running
service sshd status

# Check if user can login
grep claude /etc/passwd

# Check SSH configuration
grep -E "AllowUsers|DenyUsers" /etc/ssh/sshd_config

# Test from TrueNAS console first
su - claude
# If this works, SSH is a network/firewall issue
```

## Migration from Docker Group (If Currently Using)

If you previously added the user to the docker group and want to migrate to the secure sudo approach:

```bash
# 1. Remove user from docker group
pw groupmod docker -d claude

# 2. Verify removal
id claude
# Should NOT show docker in groups list
```

3. **Setup sudo permissions via TrueNAS GUI** (follow Step 2 above)

```bash
# 4. Test with sudo
su - claude
sudo docker ps
# Should work without password

# 5. Update any scripts or aliases
# Change: docker ps
# To:     sudo docker ps
```

## Additional Resources

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Principle of Least Privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)
- [FreeBSD pw Command Reference](https://www.freebsd.org/cgi/man.cgi?query=pw)
- [Sudo Manual](https://www.sudo.ws/docs/man/sudoers.man/)

## Summary

**Key Takeaways:**

1. ✅ **Create dedicated user** with specific UID/GID (e.g., 4000:4000)
2. ✅ **Use sudo whitelist** for docker commands (NOT docker group)
3. ✅ **Match UIDs across** TrueNAS user, compose.yaml, and file ownership
4. ✅ **Enable SSH key auth** for password-less access
5. ✅ **Audit regularly** via sudo logs
6. ✅ **Keep system updated** for security patches

Following this guide ensures your Claude Code container runs securely with proper permission boundaries and follows the principle of least privilege.
