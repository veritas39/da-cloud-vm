# da-cloud — Multi-Project Docker Infrastructure on a Single VM

A lightweight monorepo template for hosting multiple **public web applications** and **private background services** (bots, workers, cron jobs) on a single Linux VM (Ubuntu/Debian or Oracle Linux/RHEL, `x86_64` or `ARM64`) using:

- **Docker & Docker Compose** for per-project container isolation
- **Caddy 2 Reverse Proxy** for automatic HTTPS/SSL and central domain routing
- **Strict `.env` Secret Management** (live secrets stay only on the VM, never in Git)
- **Selective CI/CD Deployment** via a self-hosted GitLab Runner (or manual CLI script)

---

## Directory Structure

```text
da-cloud/
├── .gitlab-ci.yml                 # Selective path-based CI/CD pipeline
├── .gitattributes                 # Enforces LF line endings so Windows edits don't break Linux scripts
├── .gitignore                     # Blocks committing real .env files and volume data
├── .env.example                   # Optional global environment template
│
├── docs/
│   └── ARCHITECTURE.md            # Detailed network diagrams & operational playbooks
│
├── infra/
│   ├── proxy/                     # Caddy Reverse Proxy (ports 80/443, automatic HTTPS)
│   │   ├── docker-compose.yml
│   │   ├── Caddyfile              # Central domain routing map (driven by .env)
│   │   └── .env.example
│   └── scripts/
│       ├── bootstrap-vm.sh        # One-time VM setup script (Docker, Firewall, GitLab Runner)
│       └── deploy.sh              # Per-service deployment script (rsync + docker compose)
│
├── apps/                          # Public web apps (attached to external proxy-net)
│   └── web1/                      # Starter web app (minimal blank status page)
│       ├── Dockerfile
│       ├── docker-compose.yml
│       ├── .env.example
│       └── src/index.html
│
└── services/                      # Non-web projects (isolated from public HTTP ingress)
    └── _template-service/         # Blueprint for background workers, bots, or cron jobs
```

---

## Configuring Environment Variables (`.env`)

> [!IMPORTANT]
> **`.env` files are strictly required on the VM.**
> Both `deploy.sh` and `docker-compose.yml` (`required: true`) enforce that a `.env` file exists for every deployed service. There are **no hardcoded fallback domains or secrets**—if a `.env` file is missing on your VM, Docker will refuse to start that service.

### How `.env` Files Work in `da-cloud`

1. **Never committed to Git:** `.gitignore` ignores all `.env` files (only `.env.example` templates are tracked).
2. **Stored directly on your VM:** Live `.env` files live inside `/opt/da-cloud/<service-path>/.env` on your server.
3. **Safe across redeployments:** `infra/scripts/deploy.sh` uses `rsync --exclude='.env'`, so pushing code updates never overwrites or deletes your VM's `.env` files.

### Required `.env` Files on the VM

| VM File Path | Template in Repo | Purpose & Required Variables |
| :--- | :--- | :--- |
| `/opt/da-cloud/infra/proxy/.env` | `infra/proxy/.env.example` | Controls Caddy reverse proxy & SSL:<br>• `ACME_EMAIL=you@example.com` *(Let's Encrypt notifications)*<br>• `WEB1_DOMAIN=example.com` *(Domain routed to `web1`)* |
| `/opt/da-cloud/apps/web1/.env` | `apps/web1/.env.example` | Injected into the `web1` container:<br>• `APP_ENV=production`<br>• `APP_NAME=web1`<br>• *(Add any API keys or database URLs your app needs here)* |
| `/opt/da-cloud/services/<name>/.env` | `services/_template-service/.env.example` | Injected into your background service container:<br>• `WORKER_INTERVAL_SECONDS=60`<br>• `SERVICE_NAME=my-worker` |

---

## Step-by-Step Setup Guide

### Step 1: Clone & Push to Your Own Repository

Download or clone this repository, initialize your own Git remote (GitLab if using the included `.gitlab-ci.yml`, or GitHub):

```bash
git init -b main
git add .
git commit -m "Initial da-cloud setup"
git remote add origin https://gitlab.com/<your-username>/<your-repo>.git
git push -u origin main
```

*(Optional)* To keep an automatic backup on GitHub while using GitLab CI/CD, go to **GitLab -> Settings -> Repository -> Mirroring repositories** and add your GitHub repo URL with a GitHub Personal Access Token (`Push` direction).

---

### Step 2: Point Your Domain & Cloud Firewall to the VM

1. **DNS Setup (e.g., Cloudflare `DNS -> Records`):**
   - Add an `A` record: **Name:** `@` -> **IPv4 address:** `<YOUR_VM_PUBLIC_IP>`
   - Add a `CNAME` record: **Name:** `www` -> **Target:** `<your-domain.com>`
   - If using Cloudflare Proxy (Orange Cloud), set **SSL/TLS -> Overview** encryption mode to **Full (strict)**.
2. **Cloud Provider Firewall / Security List (AWS, Oracle Cloud, GCP, DigitalOcean, etc.):**
   - Allow inbound **TCP** ports `80` and `443` from `0.0.0.0/0`
   - Allow inbound **UDP** port `443` from `0.0.0.0/0` *(for HTTP/3)*

---

### Step 3: Bootstrap Your Linux VM

Copy `infra/scripts/bootstrap-vm.sh` to your VM (supports **Ubuntu/Debian** and **Oracle Linux/RHEL**) and run it once as root:

```bash
scp infra/scripts/bootstrap-vm.sh <ssh-user>@<YOUR_VM_IP>:/tmp/bootstrap-vm.sh
ssh <ssh-user>@<YOUR_VM_IP>
```

On the VM:

```bash
sudo bash /tmp/bootstrap-vm.sh
rm -f /tmp/bootstrap-vm.sh
```

What `bootstrap-vm.sh` does:
- Installs **Docker Engine** & **Docker Compose** plugin
- Installs **GitLab Runner** and grants it Docker permissions
- Opens ports `80/tcp`, `443/tcp`, and `443/udp` in `ufw` or `firewalld` (prompts whether to keep or reset existing custom ports)
- Creates the external `proxy-net` Docker network and `/opt/da-cloud` directory

---

### Step 4: Create Required `.env` Files on the VM

Before deploying, create the `.env` files on your VM and replace the example values with your real email and domain:

```bash
sudo mkdir -p /opt/da-cloud/infra/proxy /opt/da-cloud/apps/web1

sudo tee /opt/da-cloud/infra/proxy/.env >/dev/null <<EOF
ACME_EMAIL=you@example.com
WEB1_DOMAIN=example.com
EOF

sudo tee /opt/da-cloud/apps/web1/.env >/dev/null <<EOF
APP_ENV=production
APP_NAME=web1
EOF

sudo chown -R gitlab-runner:docker /opt/da-cloud
```

---

### Step 5: Deploy (Automatic CI/CD or Manual CLI)

#### Option A: Automatic Deployment with Self-Hosted GitLab Runner (Recommended)

> [!WARNING]
> **Security Requirement:** Keep your GitLab repository **PRIVATE** when using a self-hosted runner with the `shell` executor. Because the runner executes directly on your VM and has Docker privileges, anyone who can push or open a Merge Request on a public repository could execute arbitrary code on your server.

1. In your GitLab project, go to **Settings -> CI/CD -> Runners**:
   - Turn **OFF** *"Enable instance runners for this project"*.
   - Click **Create project runner** -> Platform: **Linux** -> check **Run untagged jobs** -> copy the token (`glrt-...`).
2. Register the runner on your VM:
   ```bash
   sudo gitlab-runner register \
     --non-interactive \
     --url "https://gitlab.com/" \
     --token "<YOUR_GLRT_RUNNER_TOKEN>" \
     --executor "shell" \
     --description "da-cloud-vm"
   sudo rm -f /home/gitlab-runner/.bash_logout
   sudo systemctl restart gitlab-runner
   ```
3. In GitLab **Build -> Pipelines**, trigger **`deploy:proxy`** and **`deploy:web1`**. Future `git push` commits will automatically deploy only the folder you changed!

#### Option B: Manual Deployment Without GitLab CI/CD

If you host your code on GitHub or prefer deploying directly on the VM without GitLab Runner:

```bash
git clone https://github.com/<your-username>/<your-repo>.git ~/da-cloud-src
cd ~/da-cloud-src
sudo ./infra/scripts/deploy.sh infra/proxy
sudo ./infra/scripts/deploy.sh apps/web1
```

Visit `https://<your-domain.com>` — you will see the minimal **"Deployment is working"** status page from `apps/web1`.

---

## Customizing & Adding Your Own Projects

### 1. Replacing `apps/web1` With Your Real Web App (Next.js, React, Node, Go, etc.)

1. Replace `apps/web1/src/index.html` and `apps/web1/Dockerfile` with your application code and Dockerfile.
2. Add any environment variables your app requires to `/opt/da-cloud/apps/web1/.env` on the VM.
3. If your app listens on a port other than `80` inside its container (for example, port `3000`):
   - Update `infra/proxy/Caddyfile`:
     ```caddyfile
     {$WEB1_DOMAIN} {
         import web_defaults
         reverse_proxy web1:3000
     }
     ```
4. Commit and push (or run `./infra/scripts/deploy.sh infra/proxy` and `./infra/scripts/deploy.sh apps/web1`).

### 2. Hosting a Second Website or Subdomain (`apps/web2`)

1. Point your second domain or subdomain (`app.example.com`) to your VM's IP in DNS.
2. Copy `apps/web1` to `apps/web2` and change `name: web2-app`, `container_name: web2`, and `web2-internal` in `apps/web2/docker-compose.yml`.
3. On the VM:
   - Add `WEB2_DOMAIN=app.example.com` to `/opt/da-cloud/infra/proxy/.env`.
   - Create `/opt/da-cloud/apps/web2/.env` with your app's variables.
   - Run `sudo chown -R gitlab-runner:docker /opt/da-cloud`.
4. Add the route to `infra/proxy/Caddyfile`:
   ```caddyfile
   {$WEB2_DOMAIN} {
       import web_defaults
       reverse_proxy web2:80
   }
   ```
5. Add a `deploy:web2` block in `.gitlab-ci.yml` watching `apps/web2/**/*`.

### 3. Adding a Non-Web Background Service (`services/my-bot`)

1. Copy `services/_template-service` to `services/my-bot` and update `container_name: my-bot` in `services/my-bot/docker-compose.yml`.
2. Create `/opt/da-cloud/services/my-bot/.env` on the VM (`sudo chown -R gitlab-runner:docker /opt/da-cloud`).
3. Add a `deploy:my-bot` block in `.gitlab-ci.yml` watching `services/my-bot/**/*`.

---

## Useful VM Maintenance Commands

```bash
# View running containers and health status
sudo docker ps

# View live Caddy or app logs
sudo docker logs -f --tail 100 caddy-proxy
sudo docker logs -f --tail 100 web1

# Edit live .env files on the VM and restart the container
sudo nano /opt/da-cloud/apps/web1/.env
cd /opt/da-cloud/apps/web1 && sudo docker compose up -d
```
