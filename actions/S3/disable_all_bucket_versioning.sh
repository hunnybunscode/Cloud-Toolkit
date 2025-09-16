#!/usr/bin/env bash
set -euo pipefail

disable_all_bucket_versioning() {
  print_header() { echo -e "\n━━━━━━━━━━━━━━━━ Disabling S3 Bucket Versioning ━━━━━━━━━━━━━━━━"; }
  print_header

  # Get all bucket names
  bucket_list=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

  if [[ -z "$bucket_list" ]]; then
    echo "⚠️  No buckets found in this account."
    return 0
  fi

  for bucket in $bucket_list; do
    current_status=$(aws s3api get-bucket-versioning --bucket "$bucket" --query "Status" --output text 2>/dev/null || echo "Disabled")

    if [[ "$current_status" == "Enabled" || "$current_status" == "Suspended" ]]; then
      echo "🔧 Disabling versioning on: $bucket"
      aws s3api put-bucket-versioning \
        --bucket "$bucket" \
        --versioning-configuration Status=Suspended
    else
      echo "✅ Versioning already disabled on: $bucket"
    fi
  done

  echo -e "\n✅ All buckets processed."
  return 0
}



