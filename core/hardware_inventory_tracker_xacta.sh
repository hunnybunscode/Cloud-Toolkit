#!/usr/bin/env bash
set -euo pipefail

hardware_inventory_tracker_xacta() {
  local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local ACTIONS_DIR="$SCRIPT_DIR/../actions/hardware_inventory_tracker_xacta"

  echo
  echo "━━━━━━━━━━━━━━ Hardware Inventory Tracker (Xacta) ━━━━━━━━━━━━━━"
  cat <<MENU
[1] List all assets
[2] Export all assets to CSV (Xacta format)
[0] Return to main menu
MENU

  read -rp "Select an action [0-2]: " xacta_choice

  case "${xacta_choice:-}" in
    1) source "$ACTIONS_DIR/list_assets.sh";   list_assets ;;
    2) source "$ACTIONS_DIR/export_assets_csv.sh"; export_assets_csv ;;
    0|"") echo "Returning to main menu."; return 0 ;;
    *) echo "❌ Invalid selection";;
  esac
}

