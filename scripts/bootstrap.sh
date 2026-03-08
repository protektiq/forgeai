#!/usr/bin/env bash
# Bootstrap: one-shot setup so a new clone can run the platform without hunting through each service's README.
# Run from repo root: ./scripts/bootstrap.sh
# Idempotent where possible (e.g. skips copying .env if it exists).
# Redis is required for Sidekiq; start it separately (e.g. redis-server) or use config.active_job.queue_adapter = :async in development.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MISSING=()
WARN=()

check_cmd() {
  if command -v "$1" &>/dev/null; then
    return 0
  fi
  return 1
}

# Required tools
check_cmd ruby       || MISSING+=(ruby)
check_cmd bundle     || MISSING+=(bundler)
check_cmd python3    || MISSING+=(python3)
check_cmd cargo      || MISSING+=(rust/cargo)
check_cmd dotnet     || MISSING+=(dotnet)
check_cmd make       || MISSING+=(make)

# Optional (warn only)
check_cmd redis-cli  || WARN+=("redis-cli (optional; needed for Sidekiq)")
# libvips: pkg-config is often used to detect it
if ! pkg-config --exists vips 2>/dev/null && ! check_cmd vips; then
  WARN+=("libvips (optional; needed for cpp_media)")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing required tools: ${MISSING[*]}"
  echo "Install them and run bootstrap again. See root README for prerequisites."
  exit 1
fi

if [[ ${#WARN[@]} -gt 0 ]]; then
  echo "Optional tools not found (you can continue): ${WARN[*]}"
fi

# .env from .env.example if missing
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example. Edit .env if you need to change URLs or secrets."
else
  echo ".env exists; skipping copy from .env.example"
fi

echo "--- Rails (rails_app) ---"
cd "$REPO_ROOT/rails_app"
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed
echo "Rails ready."

echo "--- Python gen (python_gen) ---"
cd "$REPO_ROOT/python_gen"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate
pip install -r requirements.txt
echo "Python gen ready."

echo "--- C++ media (cpp_media) ---"
cd "$REPO_ROOT/cpp_media"
make
echo "cpp_media ready."

echo "--- Rust index (rust_index) ---"
cd "$REPO_ROOT/rust_index"
cargo build
echo "rust_index ready."

echo "--- .NET API (dotnet_api) ---"
cd "$REPO_ROOT/dotnet_api"
dotnet restore
dotnet build
echo "dotnet_api ready."

echo ""
echo "Bootstrap complete. Next:"
echo "  1. Start Redis if you use Sidekiq: redis-server"
echo "  2. Run the stack: ./scripts/run_all.sh"
echo "  Or run each service in its own terminal (see docs/runbook.md)."
echo "  3. Quick health check: ./scripts/smoke_test.sh"
