#!/usr/bin/env bash
# Usage: ./infra/scripts/deploy.sh <relative-service-path> (e.g., infra/proxy or apps/web1)

set -euo pipefail

SERVICE_REL_PATH="${1:-}"
DEPLOY_ROOT="${DEPLOY_PATH:-/opt/da-cloud}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -z "${SERVICE_REL_PATH}" || "${SERVICE_REL_PATH}" =~ \.\. ]]; then
    echo "Error: Invalid or missing service path argument."
    echo "Usage: $0 <relative-service-path> (e.g., apps/web1)"
    exit 1
fi

SOURCE_DIR="${REPO_ROOT}/${SERVICE_REL_PATH}"
TARGET_DIR="${DEPLOY_ROOT}/${SERVICE_REL_PATH}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "Error: Source directory does not exist: ${SOURCE_DIR}"
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/docker-compose.yml" ]]; then
    echo "Error: No docker-compose.yml found in ${SOURCE_DIR}"
    exit 1
fi

echo "==> [1/4] Ensuring proxy-net Docker network exists..."
if ! docker network inspect proxy-net >/dev/null 2>&1; then
    docker network create proxy-net
fi

echo "==> [2/4] Syncing ${SERVICE_REL_PATH} to ${TARGET_DIR}..."
mkdir -p "${TARGET_DIR}"
# Exclude .env files and volume directories so live VM secrets and data are never overwritten
rsync -av --delete \
    --exclude='.env*' \
    --exclude='*.env' \
    --exclude='data/' \
    --exclude='volumes/' \
    "${SOURCE_DIR}/" "${TARGET_DIR}/"

# .env is strictly required; abort deployment if missing on the VM
if [[ ! -f "${TARGET_DIR}/.env" ]]; then
    echo "ERROR: Missing required ${TARGET_DIR}/.env file on the VM!"
    echo "Create ${TARGET_DIR}/.env before deploying (see ${TARGET_DIR}/.env.example)."
    exit 1
fi

echo "==> [3/4] Deploying containers in ${TARGET_DIR}..."
cd "${TARGET_DIR}"
docker compose config >/dev/null
docker compose up -d --build --remove-orphans

if [[ "${SERVICE_REL_PATH}" == "infra/proxy" ]]; then
    if docker ps --format '{{.Names}}' | grep -q '^caddy-proxy$'; then
        echo "    Reloading Caddy configuration..."
        docker exec caddy-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
    fi
fi

echo "==> [4/4] Cleaning up dangling Docker images..."
docker image prune -f >/dev/null 2>&1 || true

echo "==> Deployment of ${SERVICE_REL_PATH} completed!"
docker compose ps
