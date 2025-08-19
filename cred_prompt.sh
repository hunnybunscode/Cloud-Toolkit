#!/usr/bin/env bash
set -euo pipefail

echo "🔐 Paste your AWS credentials block (Ctrl+D to finish):"
echo "  export AWS_ACCESS_KEY_ID=..."
echo "  export AWS_SECRET_ACCESS_KEY=..."
echo "  export AWS_SESSION_TOKEN=..."
echo "  export AWS_TOKEN_EXPIRATION=...   # optional"
echo

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# Read pasted block
cat > "$TMPFILE"

# Filter to the four vars only, strip leading 'export ' and CRs
FILTERED="$(sed -E 's/^[[:space:]]*export[[:space:]]+//; s/\r$//' "$TMPFILE" \
  | grep -E '^(AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN|TOKEN_EXPIRATION))=' || true)"

echo "$FILTERED" | grep -q '^AWS_ACCESS_KEY_ID='     || { echo "Missing AWS_ACCESS_KEY_ID"; exit 1; }
echo "$FILTERED" | grep -q '^AWS_SECRET_ACCESS_KEY=' || { echo "Missing AWS_SECRET_ACCESS_KEY"; exit 1; }
echo "$FILTERED" | grep -q '^AWS_SESSION_TOKEN='     || { echo "Missing AWS_SESSION_TOKEN"; exit 1; }

# Export into *current* shell only if this script is sourced
# Otherwise, it still validates & runs STS in a subshell.
# shellcheck disable=SC2046
eval $(echo "$FILTERED" | sed -E 's/^([A-Z0-9_]+)=["]?([^"]*)["]?$/export \1="\2"/')

echo "✅ AWS credentials have been set (in this process)."
echo "  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:0:4}****${AWS_ACCESS_KEY_ID: -4}"
echo "  AWS_SECRET_ACCESS_KEY=************"
echo "  AWS_SESSION_TOKEN=************"
[ -n "${AWS_TOKEN_EXPIRATION:-}" ] && echo "  AWS_TOKEN_EXPIRATION=$AWS_TOKEN_EXPIRATION"

# Optional region prompt + STS verify
DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-gov-west-1}}"
read -rp "AWS Region [${DEFAULT_REGION}]: " _region_input
export AWS_REGION="${_region_input:-$DEFAULT_REGION}"
export AWS_DEFAULT_REGION="$AWS_REGION"

echo
echo "🔎 Verifying with STS..."
aws sts get-caller-identity --output table

