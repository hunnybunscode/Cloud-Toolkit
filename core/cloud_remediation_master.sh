#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────
# Visual Header
# ──────────────────────────────
cat <<EOF

       (\_(\              HunnyBuns Code               /)_/)
       ( -.-)        Cloud Remediation Toolkit        (o.o )
      o(_(")(")                                      (")_(")o
─────────────────────────────────────────────────────
EOF

# ─── Bracketed Paste Protection ───
disable_bp() { printf '\e[?2004l' > /dev/tty; }
enable_bp()  { printf '\e[?2004h' > /dev/tty; }
disable_bp
trap enable_bp EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"   # Repo root

print_header() { echo -e "\n━━━━━━━━━━━━━━━━ $1 ━━━━━━━━━━━━━━━━"; }
ok()           { echo "✅ $*"; }
warn()         { echo "⚠️  $*" >&2; }
fail()         { echo "❌ $*" >&2; exit 1; }

# 0) Dependency check — only run setup if required
print_header "Checking dependencies"

missing=0
for cmd in aws jq session-manager-plugin; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing=1
    break
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "Missing required tools. Running setup_dependencies.sh..."
  bash "$SCRIPT_ROOT/setup/setup_dependencies.sh" || warn "setup_dependencies.sh returned non-zero; continuing"
else
  ok "All required dependencies are present"
fi

print_header "Refreshing environment"
set +u
source "$HOME/.bashrc" 2>/dev/null || true
set -u
hash -r
ok "Environment refreshed"

# 1) Check for valid AWS credentials before prompting
print_header "Validating AWS credentials"

caller_arn=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "")

if [[ "$caller_arn" != "" && "$caller_arn" != "None" && "$caller_arn" != "null" ]]; then
  echo "✅ Valid AWS credentials found:"
  echo "    $caller_arn"
else
  warn "AWS credentials not found or expired — attempting to prompt"
  echo
  echo "🔐 Paste your AWS credentials block (Ctrl+D to finish):"
  echo "  export AWS_ACCESS_KEY_ID=..."
  echo "  export AWS_SECRET_ACCESS_KEY=..."
  echo "  export AWS_SESSION_TOKEN=..."
  echo "  export AWS_TOKEN_EXPIRATION=...   # optional"

  creds=$(</dev/stdin)

  if [[ -z "$creds" ]]; then
    fail "❌ No credentials received. Exiting."
  fi

  eval "$creds"

  masked_key="${AWS_ACCESS_KEY_ID:0:4}****${AWS_ACCESS_KEY_ID: -4}"
  echo
  echo "✅ AWS credentials have been set (in this process)."
  echo "  AWS_ACCESS_KEY_ID=$masked_key"
  echo "  AWS_SECRET_ACCESS_KEY=************"
  echo "  AWS_SESSION_TOKEN=************"
  echo "  AWS_TOKEN_EXPIRATION=${AWS_TOKEN_EXPIRATION:-(not set)}"
  echo

  echo "🔎 Verifying with STS..."
  aws sts get-caller-identity --output table || fail "❌ STS failed after setting credentials"

  caller_arn=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "")
  if [[ "$caller_arn" != "" && "$caller_arn" != "None" && "$caller_arn" != "null" ]]; then
    echo "✅ AWS credentials are now valid:"
    echo "    $caller_arn"
  else
    fail "❌ AWS credentials are still invalid after prompting"
  fi
fi

# 2) Action launcher (now with subfolder awareness)
run_action() {
  local script="$1" func="$2"
  if [[ ! -f "$SCRIPT_ROOT/$script" ]]; then fail "Action script not found: $script"; fi
  source "$SCRIPT_ROOT/$script"
  if ! declare -F "$func" >/dev/null 2>&1; then fail "Function '$func' not found in $script"; fi
  "$func"
}

# 3) Menu loop (action scripts moved to subfolders)
print_menu() {
  print_header "Select a cloud remediation action"
  cat <<'MENU'
[1] Encrypt/Read EBS volumes  
[2] Connect to EC2 (SSM)
[3] Enable EBS Default Encryption (account/region)           # placeholder
[4] Audit S3 buckets for public access                       # placeholder
[5] Audit Security Groups for wide-open ports                # placeholder
[6] Test / No-op (STS echo)
[0] Exit
MENU
}

while true; do
  print_menu
  read -rp "Enter choice [0-6]: " choice
  case "${choice:-}" in
    1) run_action "actions/action_encrypt_ebs.sh"         "action_encrypt_ebs" ;;
    2) run_action "core/connect_ec2_ssm.sh"               "connect_ec2_ssm"    ;;
    3) run_action "actions/action_enable_ebs_default.sh"  "action_enable_ebs_default" ;;
    4) run_action "actions/action_audit_s3_public.sh"     "action_audit_s3_public" ;;
    5) run_action "actions/action_audit_open_sg_rules.sh" "action_audit_open_sg_rules" ;;
    6) run_action "actions/action_test.sh"                "action_test" ;;
    0) echo "Bye."; exit 0 ;;
    *) warn "Invalid selection: ${choice:-<empty>}";;
  esac
done

