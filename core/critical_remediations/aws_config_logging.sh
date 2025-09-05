#!/usr/bin/env bash
set -euo pipefail

# This script:
# 1) Ensures the AWS Config service-linked role exists
# 2) Sets the recorder to record ALL supported types and GLOBAL types (incl. IAM)
# 3) Starts the recorder
# Nothing else (no proxies/creds/region are touched)

# --- Helpers
err() { echo "ERROR: $*" >&2; }

# --- Discover existing recorder
RECORDER_NAME=$(aws configservice describe-configuration-recorders \
  --query 'ConfigurationRecorders[0].name' --output text 2>/dev/null || true)

if [[ -z "${RECORDER_NAME:-}" || "${RECORDER_NAME}" == "None" ]]; then
  err "No configuration recorder found in this Region. If you truly have Config set up here, make sure your AWS_REGION is correct."
  exit 1
fi

# --- Ensure AWS Config service-linked role exists; capture its ARN
ROLE_JSON=$(aws iam get-role --role-name AWSServiceRoleForConfig 2>/dev/null || true)
if [[ -z "$ROLE_JSON" ]]; then
  echo "[Info] Creating AWS Config service-linked role..."
  aws iam create-service-linked-role --aws-service-name config.amazonaws.com 1>/dev/null
  ROLE_JSON=$(aws iam get-role --role-name AWSServiceRoleForConfig)
fi
ROLE_ARN=$(printf '%s' "$ROLE_JSON" | jq -r '.Role.Arn' 2>/dev/null || true)

if [[ -z "${ROLE_ARN:-}" || "${ROLE_ARN}" == "null" ]]; then
  err "Could not determine AWSServiceRoleForConfig ARN (need iam:GetRole)."
  exit 1
fi

# --- Set recording group to ALL supported + include global (IAM) resources
RG_JSON='{
  "allSupported": true,
  "includeGlobalResourceTypes": true,
  "recordingStrategy": { "useOnly": "ALL_SUPPORTED_RESOURCE_TYPES" }
}'

echo "[Info] Updating recorder '$RECORDER_NAME' to record ALL + GLOBAL (IAM) resource types…"
set +e
PUT_OUT=$(aws configservice put-configuration-recorder \
  --configuration-recorder "name=${RECORDER_NAME},roleARN=${ROLE_ARN}" \
  --recording-group "$RG_JSON" 2>&1)
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "$PUT_OUT" >&2
  if grep -qi 'iam:PassRole' <<<"$PUT_OUT"; then
    err "Denied on iam:PassRole for ${ROLE_ARN}. Your caller needs iam:PassRole with Condition iam:PassedToService=config.amazonaws.com."
  fi
  exit $RC
fi

# --- Start the recorder (idempotent)
aws configservice start-configuration-recorder --configuration-recorder-name "$RECORDER_NAME"

# --- Quick confirmation
echo "[Info] Current recording group:"
aws configservice describe-configuration-recorders \
  --query "ConfigurationRecorders[?name=='$RECORDER_NAME'].recordingGroup" --output json

echo "[Done] IAM (global) resources will be recorded. Per-type 'Exclude from recording' overrides are effectively cleared."

