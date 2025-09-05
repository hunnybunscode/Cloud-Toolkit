#!/usr/bin/env bash
set -euo pipefail
print_header() { echo -e "\n━━━━━━━━━━━━━━━━ $1 ━━━━━━━━━━━━━━━━"; }
ok()           { echo "✅ $*"; }

action_test() {
  print_header "Test / No-op"
  aws sts get-caller-identity --output table || true
  ok "Test action completed"
}

