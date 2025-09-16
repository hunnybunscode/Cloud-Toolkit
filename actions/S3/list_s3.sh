#!/usr/bin/env bash
set -euo pipefail

list_s3() {
  print_header() { echo -e "\n━━━━━━━━━━━━━━━━ S3 Bucket Inventory ━━━━━━━━━━━━━━━━"; }

  format_date() {
    date -d "$1" +"%b-%d-%Y" 2>/dev/null || echo "$1"
  }

  print_header

  # Table header
  printf "%-45s %-15s %-20s %-10s\n" "Bucket Name" "Creation Date" "Versioning Enabled" "Encrypted"
  printf "%s\n" "---------------------------------------------------------------------------------------------------------------"

  # Get bucket list as JSON
  bucket_json="$(aws s3api list-buckets --output json)"

  # Parse and loop through each bucket
  echo "$bucket_json" | jq -c '.Buckets[]' | while read -r bucket; do
    name="$(echo "$bucket" | jq -r '.Name')"
    raw_date="$(echo "$bucket" | jq -r '.CreationDate')"
    created="$(format_date "$raw_date")"

    # Versioning check
    versioning_status="$(aws s3api get-bucket-versioning --bucket "$name" --query 'Status' --output text 2>/dev/null || echo "Disabled")"
    [[ "$versioning_status" == "Enabled" ]] && versioning="✔" || versioning="✘"

    # Encryption check
    if aws s3api get-bucket-encryption --bucket "$name" \
      --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
      --output text 2>/dev/null | grep -q .; then
      encrypted="✔"
    else
      encrypted="✘"
    fi

    # Print row
    printf "%-45s %-15s %-20s %-10s\n" "$name" "$created" "$versioning" "$encrypted"
  done

  return 0
}


