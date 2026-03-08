#!/usr/bin/env bash
# Run the full stack in the correct order. Start all services in the background with logs under logs/.
# Usage: ./scripts/run_all.sh          # start all
#        ./scripts/run_all.sh stop     # stop services started by this script
# For debugging, run each service in a separate terminal (see docs/runbook.md).
# Requires: bootstrap has been run (./scripts/bootstrap.sh).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$REPO_ROOT/logs"
PID_FILE="$LOGS_DIR/run_all.pids"

mkdir -p "$LOGS_DIR"

# Load .env so service URLs/ports are available to processes we start
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

stop_services() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "No PID file found. Services may not be running under run_all.sh."
    return 0
  fi
  echo "Stopping services..."
  while read -r pid _; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done < "$PID_FILE"
  rm -f "$PID_FILE"
  echo "Done. If a service did not exit, kill by port (e.g. lsof -i :3000)."
  exit 0
}

if [[ "${1:-}" == "stop" ]]; then
  stop_services
fi

# Append a PID to the pid file and log file for a given label
run_background() {
  local label="$1"
  local logfile="$LOGS_DIR/${label}.log"
  shift
  echo "[$(date -Iseconds)] Starting $label" >> "$logfile"
  "$@" >> "$logfile" 2>&1 &
  echo "$! $label" >> "$PID_FILE"
  echo "Started $label (PID $!, log: $logfile)"
}

# Clear previous PIDs so we don't kill old processes on next stop
rm -f "$PID_FILE"

# Redis: required for Sidekiq. Start if not already running.
if command -v redis-cli &>/dev/null; then
  if redis-cli ping &>/dev/null; then
    echo "Redis already running."
  else
    if command -v redis-server &>/dev/null; then
      run_background "redis" redis-server
      sleep 1
    else
      echo "Warning: redis-server not found. Start Redis manually or Sidekiq will fail."
    fi
  fi
else
  echo "Warning: redis-cli not found. Assuming Redis is running."
fi

cd "$REPO_ROOT"

# Python gen (port 5000)
cd "$REPO_ROOT/python_gen"
if [[ -d .venv ]]; then
  run_background "python_gen" .venv/bin/uvicorn main:app --host 0.0.0.0 --port 5000
else
  run_background "python_gen" python3 -m uvicorn main:app --host 0.0.0.0 --port 5000
fi

# C++ media (port 8080)
cd "$REPO_ROOT/cpp_media"
run_background "cpp_media" ./cpp_media 8080

# Rust index (port 3132)
cd "$REPO_ROOT/rust_index"
export PORT="${PORT:-3132}"
run_background "rust_index" cargo run

# Give optional services a moment to bind
sleep 2

# Rails (port 3000)
cd "$REPO_ROOT/rails_app"
run_background "rails" bundle exec rails s -p 3000 -b 0.0.0.0

# Sidekiq
cd "$REPO_ROOT/rails_app"
run_background "sidekiq" bundle exec sidekiq

# .NET API (port 5001)
cd "$REPO_ROOT/dotnet_api"
run_background "dotnet_api" dotnet run

echo ""
echo "All services started. Logs: $LOGS_DIR/*.log"
echo "To stop: ./scripts/run_all.sh stop"
echo "Health check: ./scripts/smoke_test.sh"
