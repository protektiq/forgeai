#!/usr/bin/env bash
# E2E smoke test: create workflow run -> generate -> process -> index -> verify asset exists -> verify search finds it.
# Requires: all services running (Rails, Sidekiq, Python gen, C++ media, Rust index).
# Usage: E2E=1 ./scripts/e2e_smoke.sh
# Optional: RAILS_URL=http://localhost:3000 RAILS_INTERNAL_API_KEY=secret ./scripts/e2e_smoke.sh

set -e

if [[ "${E2E}" != "1" ]]; then
  echo "E2E smoke test skipped. Set E2E=1 to run."
  exit 0
fi

RAILS_URL="${RAILS_URL:-http://localhost:3000}"
RAILS_URL="${RAILS_URL%/}"
API_KEY_HEADER=""
if [[ -n "${RAILS_INTERNAL_API_KEY}" ]]; then
  API_KEY_HEADER="-H X-Internal-Api-Key: ${RAILS_INTERNAL_API_KEY}"
fi

# Unique prompt so search can find this asset later
PROMPT="e2e smoke test unique phrase $(date +%s)"
SEARCH_TERM="e2e smoke"

echo "Creating generation (prompt=${PROMPT})..."
# Use wrapped path (no workflow_slug) so response includes job_id for polling
CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "${RAILS_URL}/api/v1/generate" \
  -H "Content-Type: application/json" \
  $API_KEY_HEADER \
  -d "{\"prompt\": \"${PROMPT}\"}")

HTTP_BODY=$(echo "$CREATE_RESP" | head -n -1)
HTTP_CODE=$(echo "$CREATE_RESP" | tail -n 1)

if [[ "$HTTP_CODE" != "201" ]]; then
  echo "Create failed: HTTP $HTTP_CODE"
  echo "$HTTP_BODY"
  exit 1
fi

JOB_ID=$(echo "$HTTP_BODY" | jq -r '.job_id')
if [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; then
  echo "Response missing job_id."
  echo "$HTTP_BODY"
  exit 1
fi

echo "Job ID: $JOB_ID. Polling for completion (timeout 120s)..."
DEADLINE=$(($(date +%s) + 120))
while true; do
  JOB_RESP=$(curl -s "${RAILS_URL}/api/v1/jobs/${JOB_ID}" $API_KEY_HEADER)
  STATUS=$(echo "$JOB_RESP" | jq -r '.status')
  if [[ "$STATUS" == "completed" ]]; then
    ASSET_ID=$(echo "$JOB_RESP" | jq -r '.asset_id')
    echo "Job completed. Asset ID: $ASSET_ID"
    break
  fi
  if [[ "$STATUS" == "failed" ]]; then
    echo "Job failed:"
    echo "$JOB_RESP" | jq '.'
    exit 1
  fi
  if [[ $(date +%s) -ge $DEADLINE ]]; then
    echo "Timeout waiting for job completion."
    exit 1
  fi
  sleep 3
done

echo "Verifying asset exists (GET /api/v1/assets/${ASSET_ID})..."
ASSET_RESP=$(curl -s -w "\n%{http_code}" "${RAILS_URL}/api/v1/assets/${ASSET_ID}" $API_KEY_HEADER)
ASSET_HTTP_CODE=$(echo "$ASSET_RESP" | tail -n 1)
if [[ "$ASSET_HTTP_CODE" != "200" ]]; then
  echo "Asset fetch failed: HTTP $ASSET_HTTP_CODE"
  exit 1
fi

echo "Verifying search finds the asset (GET /api/v1/assets?search=${SEARCH_TERM})..."
SEARCH_RESP=$(curl -s "${RAILS_URL}/api/v1/assets?search=${SEARCH_TERM}" $API_KEY_HEADER)
FOUND=$(echo "$SEARCH_RESP" | jq --arg aid "$ASSET_ID" '[.[] | select(.id == ($aid | tonumber))] | length')
if [[ "${FOUND:-0}" -lt 1 ]]; then
  echo "Search did not return the created asset (asset_id=$ASSET_ID)."
  echo "Search response (first 500 chars): ${SEARCH_RESP:0:500}"
  exit 1
fi

echo "E2E smoke test passed: asset $ASSET_ID created and found via search."
