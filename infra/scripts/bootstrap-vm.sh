#!/usr/bin/env bash
# One-time VM provisioning script (supports Oracle Linux / RHEL via dnf and Ubuntu / Debian via apt-get).
# Usage: sudo bash bootstrap-vm.sh

set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-/opt/da-cloud}"
PROXY_NETWORK="proxy-net"

echo "==> [1/5] Detecting OS & installing base packages..."
if command -v dnf >/dev/null 2>&1; then
    OS_FAMILY="rhel"
    dnf install -y ca-certificates curl git rsync dnf-plugins-core
elif command -v apt-get >/dev/null 2>&1; then
    OS_FAMILY="debian"
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release git ufw rsync
else
    echo "Error: Unsupported package manager (expected dnf or apt-get)."
    exit 1
fi

echo "==> [2/5] Installing Docker Engine & Docker Compose plugin..."
if ! command -v docker >/dev/null 2>&1; then
    if [[ "${OS_FAMILY}" == "rhel" ]]; then
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        curl -fsSL https://get.docker.com | sh
    fi
    systemctl enable --now docker
else
    echo "    Docker is already installed: $(docker --version)"
    systemctl enable --now docker
fi

echo "==> [3/5] Installing Self-Hosted GitLab Runner..."
if ! command -v gitlab-runner >/dev/null 2>&1; then
    if [[ "${OS_FAMILY}" == "rhel" ]]; then
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash
        dnf install -y gitlab-runner
    else
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
        apt-get install -y gitlab-runner
    fi
    usermod -aG docker gitlab-runner
    systemctl enable --now gitlab-runner
else
    echo "    GitLab Runner is already installed: $(gitlab-runner --version | head -n 1)"
    usermod -aG docker gitlab-runner || true
    systemctl enable --now gitlab-runner
fi

echo "==> [4/5] Configuring Firewall (HTTP 80, HTTPS 443)..."
echo ""
echo "How should existing firewall ports be handled?"
echo "  [1] Just ADD ports 80 & 443 (keep existing custom ports open) [Default]"
echo "  [2] CLOSE all existing custom ports first, then open ONLY SSH (22) + Web (80/443)"
read -r -p "Select option [1 or 2, default=1]: " FW_MODE </dev/tty || FW_MODE="1"
FW_MODE="${FW_MODE:-1}"

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    if [[ "${FW_MODE}" == "2" ]]; then
        echo "    Closing all existing custom ports and extra services in firewalld..."
        for port in $(firewall-cmd --zone=public --list-ports); do
            firewall-cmd --permanent --zone=public --remove-port="${port}"
        done
        for svc in $(firewall-cmd --zone=public --list-services); do
            if [[ "${svc}" != "ssh" && "${svc}" != "dhcpv6-client" ]]; then
                firewall-cmd --permanent --zone=public --remove-service="${svc}"
            fi
        done
    else
        echo "    Keeping existing firewalld ports: $(firewall-cmd --zone=public --list-ports)"
    fi

    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
    firewall-cmd --permanent --zone=public --add-port=443/udp
    firewall-cmd --reload
    firewall-cmd --zone=public --list-all
elif command -v ufw >/dev/null 2>&1; then
    if [[ "${FW_MODE}" == "2" ]]; then
        echo "    Resetting UFW to close all existing custom ports..."
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow OpenSSH
    fi
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    ufw --force enable
    ufw status verbose
else
    echo "    No active firewalld or ufw detected; skipping OS firewall rules."
fi

echo "==> [5/5] Creating external Docker network (${PROXY_NETWORK}) and ${DEPLOY_PATH}..."
if ! docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1; then
    docker network create "${PROXY_NETWORK}"
    echo "    Created Docker network: ${PROXY_NETWORK}"
else
    echo "    Docker network ${PROXY_NETWORK} already exists."
fi

mkdir -p "${DEPLOY_PATH}"
if id "gitlab-runner" >/dev/null 2>&1; then
    chown -R gitlab-runner:docker "${DEPLOY_PATH}"
    chmod -R 750 "${DEPLOY_PATH}"
fi

echo ""
echo "Bootstrap complete."
echo "Next steps:"
echo "  1. Register GitLab Runner (if using GitLab CI/CD):"
echo "     sudo gitlab-runner register --non-interactive --url https://gitlab.com/ --token <YOUR_RUNNER_TOKEN> --executor shell --description da-cloud-vm"
echo "  2. Create required .env files in ${DEPLOY_PATH}/infra/proxy/.env and ${DEPLOY_PATH}/apps/web1/.env"
