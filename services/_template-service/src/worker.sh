#!/bin/sh
set -eu

INTERVAL="${WORKER_INTERVAL_SECONDS:-60}"
NAME="${SERVICE_NAME:-template-worker}"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting service: ${NAME}"

while true; do
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [${NAME}] Heartbeat OK — sleeping ${INTERVAL}s..."
    sleep "${INTERVAL}"
done
