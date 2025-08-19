#!/usr/bin/env bash
set -euo pipefail

connect_ec2_ssm() {
  local history_file="$HOME/.ec2_instance_history.txt"

  # Step 0: Ensure Session Manager plugin is installed
  if ! command -v session-manager-plugin >/dev/null 2>&1; then
    echo "AWS Session Manager Plugin not found. Installing..."
    echo "PLEASE BE PATIENT FOR FIRST TIME SETUP"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o /tmp/session-manager-plugin.rpm
      sudo yum install -y /tmp/session-manager-plugin.rpm || sudo dnf install -y /tmp/session-manager-plugin.rpm
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      brew install --cask session-manager-plugin
    else
      echo "Unsupported OS. Install manually: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
      return 1
    fi

    if ! command -v session-manager-plugin >/dev/null 2>&1; then
      echo "Install failed or plugin not in PATH. Exiting."
      return 1
    fi

    echo "Session Manager Plugin installed."
  fi

  touch "$history_file"

  # Step 1: Show saved instance IDs with names
  if [[ -s "$history_file" ]]; then
    echo "Saved instance targets:"
    nl -w2 -s'. ' "$history_file"
    echo "--------------------------"
    read -rp "Select your EC2 with its associated number, or press [Enter] to enter new instance ID: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      selected_line=$(sed "${choice}q;d" "$history_file")
      instance_id=$(echo "$selected_line" | cut -d'|' -f1 | xargs)
    else
      read -rp "Enter new EC2 Instance ID: " instance_id
    fi
  else
    read -rp "Enter EC2 Instance ID: " instance_id
  fi

  # Step 2: If new, fetch instance Name tag and optionally save
  if ! grep -q "^$instance_id" "$history_file" 2>/dev/null; then
    name_tag=$(aws ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" \
      --output text 2>/dev/null)

    read -rp "Would you like to save this ID for future use? (y/n): " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
      echo "$instance_id | $name_tag" >> "$history_file"
      echo "Saved: $instance_id | $name_tag"
    fi
  fi

  # Step 3: Start the SSM session
  echo "Connecting to $instance_id..."
  aws ssm start-session --target "$instance_id"
}

