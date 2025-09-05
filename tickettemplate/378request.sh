#!/usr/bin/env bash

Thing=""
BASE="https://jira.odin.dso.mil"
PORTAL="5"
RT="378"
ISSM_USER="alex.ortizmarrero.ctr"   # Jira username for your ISSM

# 1) Create the request
CREATE_RESP=$(
  curl -s -k \
    -H "Authorization: Bearer $PAT" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST "$BASE/rest/servicedeskapi/request" \
    -d '{
      "serviceDeskId": "'"$PORTAL"'",
      "requestTypeId": "'"$RT"'",
      "requestFieldValues": {
        "components": [{ "id": "27205" }],
        "summary": "Update IAM role ProjAdmin",
        "customfield_27000": { "id": "32801" },
        "description": "Looping in ISSM: [~'"$ISSM_USER"']\n\nRequesting an update to IAM role `ProjAdmin`:\n- Add Bedrock* to `ProjAdmin`\n- JSON template attached\n",
        "customfield_11401": "123456789012",
        "customfield_14900": "SIA-12345",
        "customfield_15202": null
      }
    }'
)

ISSUE_KEY=$(echo "$CREATE_RESP" | jq -r '.issueKey // .issueId // empty')

if [ -z "$ISSUE_KEY" ]; then
  echo "❌ Ticket creation failed. Raw response:"
  echo "$CREATE_RESP" | jq .
  exit 1
fi

echo "✅ Created: $ISSUE_KEY"
echo "🔗 $BASE/browse/$ISSUE_KEY"

# 2) Add ISSM as a Request Participant
curl -s -k \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/rest/servicedeskapi/request/$ISSUE_KEY/participant" \
  -d '{ "usernames": ["'"$ISSM_USER"'"] }' | jq .

# 3) Add a comment that @-mentions the ISSM
curl -s -k \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/rest/api/2/issue/$ISSUE_KEY/comment" \
  -d '{ "body": "[~'"$ISSM_USER"'] — Please approve." }' | jq .

