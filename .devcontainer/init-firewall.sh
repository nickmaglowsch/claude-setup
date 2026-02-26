#!/usr/bin/env bash
# init-firewall.sh — Optional network firewall for Claude Code dev containers
#
# Restricts outbound traffic to only the services Claude Code needs.
# This enables safely running `claude --dangerously-skip-permissions` for
# unattended operation.
#
# Adapted from Anthropic's reference implementation.
# Usage: sudo /usr/local/bin/init-firewall.sh

set -euo pipefail

echo "Initializing container firewall..."

# Flush existing rules
iptables -F OUTPUT
iptables -F INPUT

# Allow loopback (localhost)
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow established/related connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (needed to resolve all domains below)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# --- Allowed domains ---

resolve_and_allow() {
  local domain="$1"
  local ips
  ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
  for ip in $ips; do
    iptables -A OUTPUT -d "$ip" -j ACCEPT
  done
  if [ -z "$ips" ]; then
    echo "  Warning: Could not resolve $domain"
  else
    echo "  Allowed: $domain ($ips)"
  fi
}

# Claude API
resolve_and_allow "api.anthropic.com"

# Telemetry
resolve_and_allow "statsig.anthropic.com"
resolve_and_allow "statsig.com"

# npm registry (for package installs)
resolve_and_allow "registry.npmjs.org"

# VS Code extensions marketplace
resolve_and_allow "marketplace.visualstudio.com"
resolve_and_allow "vscode.blob.core.windows.net"

# GitHub — fetch IP ranges from their meta API
echo "  Fetching GitHub IP ranges..."
GITHUB_IPS=$(curl -fsSL https://api.github.com/meta 2>/dev/null | \
  grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+"' | tr -d '"' || true)

if [ -n "$GITHUB_IPS" ]; then
  for cidr in $GITHUB_IPS; do
    iptables -A OUTPUT -d "$cidr" -j ACCEPT
  done
  echo "  Allowed: GitHub ($(echo "$GITHUB_IPS" | wc -l | tr -d ' ') CIDR ranges)"
else
  echo "  Warning: Could not fetch GitHub IPs, allowing github.com directly"
  resolve_and_allow "github.com"
  resolve_and_allow "api.github.com"
fi

# --- Default deny ---
iptables -A OUTPUT -j DROP

echo "Firewall initialized. Only whitelisted domains are reachable."
echo "To verify: curl -s https://api.anthropic.com (should work)"
echo "To verify: curl -s https://example.com (should fail)"
