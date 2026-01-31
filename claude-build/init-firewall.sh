#!/bin/sh
#
# init-firewall.sh - Egress Firewall for Claude Code Container
#
# Adapted from Anthropic's official devcontainer firewall:
# https://github.com/anthropics/claude-code/.devcontainer/init-firewall.sh
#
# Modified for Alpine Linux (uses 'dig' instead of requiring 'aggregate')
#
# This script implements a whitelist-based egress firewall:
# - Default DENY all outbound connections
# - Allow only specific domains required for Claude Code operation
# - Allow DNS, SSH, and local network access
#
# Required capabilities: NET_ADMIN, NET_RAW
#

set -e

echo "=== Claude Code Firewall Setup ==="

# --- Cleanup function ---
cleanup() {
    ipset destroy allowed-domains-tmp 2>/dev/null || true
}
trap cleanup EXIT

# --- Helper: Add IP to ipset with error handling ---
add_to_ipset() {
    local ip="$1"
    local setname="$2"
    # Validate IP format (basic check)
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
        ipset add "$setname" "$ip" 2>/dev/null || true
    fi
}

# --- 1. Save Docker DNS rules before flushing ---
echo "Preserving Docker DNS rules..."
DOCKER_DNS_RULES=$(iptables-save -t nat 2>/dev/null | grep "127\.0\.0\.11" || true)

# --- 2. Reset iptables (allow traffic during setup) ---
echo "Resetting iptables..."
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Flush rules (filter table only to preserve Docker networking)
iptables -F
iptables -X

# --- 3. Restore Docker DNS if present ---
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | while read -r rule; do
        iptables -t nat $rule 2>/dev/null || true
    done
fi

# --- 4. Allow essential traffic before restrictions ---
echo "Setting up base rules..."

# Allow DNS (UDP 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT

# Allow SSH (TCP 22) for git operations
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Allow loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# --- 5. Create ipset for allowed domains ---
echo "Creating IP whitelist..."
ipset create allowed-domains-tmp hash:net 2>/dev/null || ipset flush allowed-domains-tmp

# --- 6. Fetch and add GitHub IP ranges ---
echo "Fetching GitHub IP ranges..."
gh_meta=$(curl -sf --connect-timeout 10 https://api.github.com/meta 2>/dev/null || echo "")

if [ -n "$gh_meta" ]; then
    # Extract web, api, and git IP ranges
    for range in $(echo "$gh_meta" | jq -r '(.web + .api + .git)[]' 2>/dev/null); do
        echo "  Adding GitHub: $range"
        add_to_ipset "$range" "allowed-domains-tmp"
    done
else
    echo "  WARNING: Could not fetch GitHub IPs, adding known ranges..."
    # Fallback GitHub IP ranges (may become outdated)
    add_to_ipset "140.82.112.0/20" "allowed-domains-tmp"
    add_to_ipset "143.55.64.0/20" "allowed-domains-tmp"
    add_to_ipset "192.30.252.0/22" "allowed-domains-tmp"
fi

# --- 7. Resolve and add required domains ---
# These are the domains Claude Code needs to function:
# - api.anthropic.com: Claude API
# - registry.npmjs.org: npm packages
# - sentry.io: error reporting
# - statsig.anthropic.com: feature flags
# - statsig.com: feature flags CDN

ALLOWED_DOMAINS="
api.anthropic.com
registry.npmjs.org
sentry.io
statsig.anthropic.com
statsig.com
o1137031.ingest.sentry.io
"

for domain in $ALLOWED_DOMAINS; do
    if [ -n "$domain" ]; then
        echo "Resolving $domain..."
        # Use dig to resolve A records
        ips=$(dig +short +timeout=5 A "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
        for ip in $ips; do
            echo "  Adding $ip"
            add_to_ipset "$ip" "allowed-domains-tmp"
        done
    fi
done

# --- 8. Atomic swap to live ipset ---
echo "Activating IP whitelist..."
ipset create allowed-domains hash:net 2>/dev/null || true
ipset swap allowed-domains-tmp allowed-domains
ipset destroy allowed-domains-tmp 2>/dev/null || true

# --- 9. Detect and allow host/local network ---
HOST_IP=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
    echo "Allowing local network: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# --- 10. Apply default DROP policy ---
echo "Applying DROP policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# --- 11. Allow established/related connections ---
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- 12. Allow traffic to whitelisted IPs ---
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# --- 13. Explicit reject for better debugging ---
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# --- 14. Verification ---
echo ""
echo "=== Verifying Firewall ==="

# Test blocked domain (should fail)
echo -n "Testing BLOCKED (example.com)... "
if curl -sf --connect-timeout 3 https://example.com >/dev/null 2>&1; then
    echo "FAILED - Firewall not working!"
    exit 1
else
    echo "BLOCKED ✓"
fi

# Test allowed domain (should succeed)
echo -n "Testing ALLOWED (api.github.com)... "
if curl -sf --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ALLOWED ✓"
else
    echo "WARNING - GitHub may be temporarily unavailable"
fi

echo ""
echo "=== Firewall Active ==="
echo "ALLOWED: GitHub, npm, Anthropic API, Sentry, Statsig, local network"
echo "BLOCKED: Everything else"
echo ""
