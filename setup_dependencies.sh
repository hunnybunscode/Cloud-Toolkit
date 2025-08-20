0~#!/usr/bin/env bash
set -euo pipefail

### ─────────────────────────────
### Config (edit if needed)
### ─────────────────────────────
AWSCLI_INSTALL_DIR="$HOME/.aws-cli"
USER_LOCAL_BIN="$HOME/.local/bin"
VENV_DIR="$HOME/venvs/ebs-tools"

### ─────────────────────────────
### Helpers
### ─────────────────────────────
append_once() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}
need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing required command: $cmd"
    echo "   Please install it (no sudo in this script)."
    exit 1
  fi
}
print_header() { echo -e "\n━━━━━━━━━━━━━━━━ $1 ━━━━━━━━━━━━━━━━"; }

### 1) Preflight
print_header "Preflight checks (no sudo)"
need_cmd curl
need_cmd unzip
need_cmd python3
echo "✅ curl, unzip, python3 present."
python3 -m ensurepip --upgrade >/dev/null 2>&1 || true

### 2) PATH
print_header "Configuring PATH"
mkdir -p "$USER_LOCAL_BIN"
append_once 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"
echo "✅ PATH updated for this session and persisted."

### 3) AWS CLI (idempotent)
print_header "Installing AWS CLI v2 (user-level)"
AWS_BIN_CANDIDATE_1="$USER_LOCAL_BIN/aws"
AWS_BIN_CANDIDATE_2="$AWSCLI_INSTALL_DIR/v2/current/bin/aws"
if command -v aws >/dev/null 2>&1 || [[ -x "$AWS_BIN_CANDIDATE_1" ]] || [[ -x "$AWS_BIN_CANDIDATE_2" ]]; then
  echo -n "AWS CLI already present: "
  if command -v aws >/dev/null 2>&1; then aws --version
  elif [[ -x "$AWS_BIN_CANDIDATE_1" ]]; then "$AWS_BIN_CANDIDATE_1" --version
  else "$AWS_BIN_CANDIDATE_2" --version; fi

  if [[ "${UPDATE_AWSCLI:-false}" == "true" ]]; then
    echo "Updating AWS CLI..."
    TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
    (
      set +e
      cd "$TMPDIR"
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
      unzip -q awscliv2.zip
      ./aws/install -i "$AWSCLI_INSTALL_DIR" -b "$USER_LOCAL_BIN" --update
      rc=$?
      set -e
      if [[ $rc -ne 0 ]]; then echo "⚠️  AWS CLI updater returned $rc; continuing."; fi
    )
    echo -n "AWS CLI after update: "; aws --version || true
    echo "✅ AWS CLI update complete"
  else
    echo "✅ Skipping AWS CLI install (set UPDATE_AWSCLI=true to force update)"
  fi
else
  echo "AWS CLI not found; installing..."
  TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
  (
    set +e
    cd "$TMPDIR"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -q awscliv2.zip
    ./aws/install -i "$AWSCLI_INSTALL_DIR" -b "$USER_LOCAL_BIN"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then echo "⚠️  Installer returned $rc; continuing."; fi
  )
  echo -n "AWS CLI installed: "; aws --version || true
  echo "✅ AWS CLI installed to $AWSCLI_INSTALL_DIR and linked in $USER_LOCAL_BIN"
fi

### 4) Python venv + boto (NO 'source activate')
print_header "Creating Python virtualenv + installing boto3/botocore"
mkdir -p "$(dirname "$VENV_DIR")"
python3 -m venv "$VENV_DIR"

# Use venv binaries directly to avoid sourcing (safe with set -u)
"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install boto3 botocore >/dev/null

append_once "alias ebsenv='source $VENV_DIR/bin/activate'" "$HOME/.bashrc"
echo "✅ Virtualenv at $VENV_DIR with boto3/botocore installed."

### 5) Verification (no sourcing)
print_header "Verifying installations"
if command -v aws >/dev/null 2>&1; then
  echo -n "AWS CLI: "; aws --version
else
  echo "⚠️  AWS CLI not found in PATH after install"
fi
echo -n "Python: "; "$VENV_DIR/bin/python" -V
"$VENV_DIR/bin/python" - <<'PY'
import boto3, botocore
print("boto3:", boto3.__version__)
print("botocore:", botocore.__version__)
PY

echo -e "\n✅ All set!"
echo "• AWS CLI in: $AWSCLI_INSTALL_DIR (symlinked in ~/.local/bin)"
echo "• Virtualenv: $VENV_DIR  (use 'ebsenv' to activate if you want, not required)"
echo "• PATH includes ~/.local/bin (persisted)"
1~
