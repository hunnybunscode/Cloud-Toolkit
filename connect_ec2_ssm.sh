#!/usr/bin/env bash
set -euo pipefail

connect_ec2_ssm() {
  local history_file="$HOME/.ec2_instance_history.txt"
  local LOCAL_BIN="$HOME/.local/bin"
  local PLUGIN_PATH="$LOCAL_BIN/session-manager-plugin"

  mkdir -p "$LOCAL_BIN"

  # ─── STEP 0: INSTALL SESSION MANAGER PLUGIN LOCALLY ─────── #
  if ! command -v session-manager-plugin >/dev/null 2>&1; then
    echo "🛠 Session Manager Plugin not found. Installing locally..."

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    (
      cd "$TMPDIR"
      echo "📥 Downloading Session Manager Plugin..."
      curl --fail --proxy "${https_proxy:-}" \
        -o plugin.zip \
        "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.zip"

      if [[ ! -s plugin.zip ]]; then
        echo "❌ Download failed or zip is empty. Check your proxy settings."
        return 1
      fi

      unzip -q plugin.zip
      mv session-manager-plugin/bin/session-manager-plugin "$PLUGIN_PATH"
    )

    chmod +x "$PLUGIN_PATH"

    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      export PATH="$HOME/.local/bin:$PATH"
      echo "🔁 Added ~/.local/bin to PATH in .bashrc and updated current shell"
    fi

    if ! command -v session-manager-plugin >/dev/null 2>&1; then
      echo "❌ Plugin installation failed or not in PATH."
      return 1
    fi

    echo "✅ Session Manager Plugin installed locally."
  fi

  # ─── STEP 1: LIST ALL RUNNING EC2 INSTANCES WITH SSM ─────── #
  echo
  echo "━━━━━━━━━━━━━━━━ EC2 Instances with SSM Enabled ━━━━━━━━━━━━━━━━"

  mapfile -t ec2_list < <(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
              "Name=tag:Name,Values=*" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[?State.Name=='running'].[InstanceId, Tags[?Key=='Name']|[0].Value]" \
    --output text | sort)

  if [[ ${#ec2_list[@]} -eq 0 ]]; then
    echo "❌ No running EC2 instances with SSM found."
    return 1
  fi

  for i in "${!ec2_list[@]}"; do
    id=$(echo "${ec2_list[$i]}" | awk '{print $1}')
    name=$(echo "${ec2_list[$i]}" | cut -f2- -d' ')
    printf "[%d] %s\t| %s\n" "$((i+1))" "$name" "$id"
  done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  read -rp "Select an EC2 to connect [1-${#ec2_list[@]}]: " selection

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#ec2_list[@]} )); then
    echo "❌ Invalid selection"
    return 1
  fi

  instance_entry="${ec2_list[$((selection-1))]}"
  instance_id=$(echo "$instance_entry" | awk '{print $1}')
  name_tag=$(echo "$instance_entry" | cut -f2- -d' ')

  echo
  echo "🔗 Connecting to: $name_tag ($instance_id)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  aws ssm start-session --target "$instance_id"
}

