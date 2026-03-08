#!/usr/bin/env bash
# Lightweight "are services up?" check. Curls health endpoints (no full generation).
# Usage: ./scripts/smoke_test.sh
# For full E2E (create job -> poll -> asset + search), use: E2E=1 ./scripts/e2e_smoke.sh
# Optional: set GENERATOR_URL, CPP_MEDIA_URL, INDEX_SERVICE_URL, DOTNET_API_URL to override defaults.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

# Default URLs (strip trailing slash for consistency)
GENERATOR_URL="${GENERATOR_URL:-http://localhost:5000}"
GENERATOR_URL="${GENERATOR_URL%/}"
CPP_MEDIA_URL="${CPP_MEDIA_URL:-http://localhost:8080}"
CPP_MEDIA_URL="${CPP_MEDIA_URL%/}"
INDEX_SERVICE_URL="${INDEX_SERVICE_URL:-http://localhost:3132}"
INDEX_SERVICE_URL="${INDEX_SERVICE_URL%/}"
RAILS_URL="${RAILS_URL:-http://localhost:3000}"
RAILS_URL="${RAILS_URL%/}"
DOTNET_API_URL="${DOTNET_API_URL:-http://localhost:5001}"
DOTNET_API_URL="${DOTNET_API_URL%/}"

FAILED=()

check() {
  local name="$1"
  local url="$2"
  local extra="${3:-}"
  if curl -sf $extra "$url" >/dev/null; then
    echo "OK $name"
    return 0
  fi
  echo "FAIL $name ($url)"
  FAILED+=("$name")
  return 1
}

echo "Smoke test (health checks only)..."
check "python_gen" "${GENERATOR_URL}/health"
check "cpp_media" "${CPP_MEDIA_URL}/health"
check "rust_index" "${INDEX_SERVICE_URL}/health"
check "dotnet_api" "${DOTNET_API_URL}/health"
# Rails has no /health; expect 302 redirect or 200 from root
if curl -sf -o /dev/null -w "%{http_code}" "$RAILS_URL/" | grep -qE '^(200|302)$'; then
  echo "OK rails"
else
  echo "FAIL rails ($RAILS_URL/)"
  FAILED+=("rails")
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo ""
  echo "Failed: ${FAILED[*]}"
  exit 1
fi

echo ""
echo "All services reachable."
