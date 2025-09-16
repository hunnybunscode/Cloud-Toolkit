#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob  # Prevent glob patterns from expanding to literal strings

# ================================================= #
cat <<EOF

       (\_(\              HunnyBuns Code               /)_/)
       ( -.-)        Cloud Remediation Toolkit        (o.o )
      o(_(")(")                                      (")_(")o
─────────────────────────────────────────────────────
EOF

disable_bp() { printf '\e[?2004l' > /dev/tty; }
enable_bp()  { printf '\e[?2004h' > /dev/tty; }
disable_bp
trap enable_bp EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIONS_DIR="$SCRIPT_ROOT/actions"

print_header() { echo -e "\n━━━━━━━━━━━━━━━━ $1 ━━━━━━━━━━━━━━━━"; }
ok()           { echo "✅ $*"; }
warn()         { echo "⚠️  $*" >&2; }
fail()         { echo "❌ $*" >&2; exit 1; }

# ───────────────────────────────────────────────────────────── #
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

print_header "Validating AWS credentials"

caller_arn=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "")
if [[ "$caller_arn" != "" && "$caller_arn" != "None" && "$caller_arn" != "null" ]]; then
  echo "✅ Valid AWS credentials found:"
  echo "    $caller_arn"
else
  warn "AWS credentials not found or expired — attempting to prompt"
  echo
  echo "🔐 Paste your AWS credentials block (Ctrl+D to finish):"
  creds=$(</dev/stdin)

  if [[ -z "$creds" ]]; then fail "❌ No credentials received. Exiting."; fi
  eval "$creds"

  masked_key="${AWS_ACCESS_KEY_ID:0:4}****${AWS_ACCESS_KEY_ID: -4}"
  echo "✅ AWS credentials have been set:"
  echo "  AWS_ACCESS_KEY_ID=$masked_key"
  echo "  AWS_SECRET_ACCESS_KEY=************"
  echo "  AWS_SESSION_TOKEN=************"
  echo "  AWS_TOKEN_EXPIRATION=${AWS_TOKEN_EXPIRATION:-(not set)}"

  echo "🔎 Verifying with STS..."
  aws sts get-caller-identity --output table || fail "❌ STS failed after setting credentials"
fi

# ───────────────────────────────────────────────────────────── #
declare -gA MENU_MAP=()
declare -a NAV_STACK=()

print_menu() {
  local current_dir="$1"
  local index=1
  MENU_MAP=()

  if [[ ! -d "$current_dir" ]]; then
    warn "Invalid directory: $current_dir"
    return
  fi

  local dir_name="$(basename "$current_dir")"
  print_header "Contents of $dir_name"

  # Show breadcrumb trail
  local breadcrumb=""
  for path in "${NAV_STACK[@]}"; do
    breadcrumb+="/$(basename "$path")"
  done
  echo "📍 Path:${breadcrumb:-/Root}"

  local found=0

  for dir in "$current_dir"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    echo "[$index] 📁 $name"
    MENU_MAP["$index"]="folder:$dir"
    ((index++))
    found=1
  done

  for file in "$current_dir"/*.sh; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    echo "[$index] 🧩 $name"
    MENU_MAP["$index"]="file:$file"
    ((index++))
    found=1
  done

  if [[ "$found" -eq 0 ]]; then
    echo "⚠️  No actions or folders found in this directory."
  fi

  echo "[0] Back"
}

run_action() {
  local script="$1"
  local func="$(basename "$script" .sh)"

  if [[ ! -f "$script" ]]; then
    fail "Action script not found: $script"
  fi

  (
    source "$script"

    if ! declare -F "$func" >/dev/null 2>&1; then
      fail "Function '$func' not found in $script"
    fi

    "$func"
  )
}

navigate() {
  local current_dir="$1"
  NAV_STACK=("$current_dir")

  while true; do
    print_menu "$current_dir"
    read -rp "Enter choice: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      warn "Invalid input: must be a number"
      continue
    fi

    if [[ "$choice" == "0" ]]; then
      if [[ "${#NAV_STACK[@]}" -gt 1 ]]; then
        unset 'NAV_STACK[-1]'
        current_dir="${NAV_STACK[-1]}"
      else
        break
      fi
      continue
    fi

    entry="${MENU_MAP[$choice]:-}"
    if [[ -z "$entry" ]]; then
      warn "Invalid selection"
      continue
    fi

    type="${entry%%:*}"
    path="${entry#*:}"

    if [[ "$type" == "file" ]]; then
      run_action "$path"
    elif [[ "$type" == "folder" ]]; then
      [[ -d "$path" ]] || { warn "Invalid folder path: $path"; continue; }
      NAV_STACK+=("$path")
      current_dir="$path"
    fi
  done
}

# ───────────────────────────────────────────────────────────── #
navigate "$ACTIONS_DIR"
NAV_STACK=()
shopt -u nullglob
echo "Bye."

