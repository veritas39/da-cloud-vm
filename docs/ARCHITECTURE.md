# `da-cloud` — Architecture & Operations Reference

## 1. Architecture Overview

```mermaid
flowchart TB
    subgraph Local["Developer Machine"]
        Code["Code Edits & git push"]
    end

    subgraph Repo["Git Hosting"]
        GitLab["GitLab Repository
(CI/CD Pipeline)"]
        GitHub["Optional GitHub Mirror"]
    end

    subgraph Edge["DNS / Edge Proxy"]
        CF["Cloudflare / DNS Provider
SSL: Full (strict)"]
    end

    subgraph VM["Linux VM (Oracle Linux / Ubuntu)"]
        Runner["Self-Hosted GitLab Runner
(shell executor)"]
        DeployScript["/opt/da-cloud/infra/scripts/deploy.sh"]

        subgraph Docker["Docker Engine"]
            subgraph ProxyNet["External Bridge: proxy-net"]
                Caddy["caddy-proxy (Ports 80, 443)"]
                Web1["web1 (apps/web1)"]
            end

            subgraph Web1Internal["Internal Network: web1-internal"]
                DB["(Optional App DB / Cache)"]
            end

            subgraph IsolatedNet["Isolated Service Networks (No Public Ingress)"]
                Workers["services/* (Bots / Workers / Cron)"]
            end
        end
    end

    Code -->|"git push"| GitLab
    GitLab -.->|"Push Mirror"| GitHub
    GitLab -->|"Path-filtered Job"| Runner
    Runner -->|"Executes"| DeployScript
    DeployScript -->|"rsync + docker compose up -d --build"| Docker
    CF -->|"HTTPS 443"| Caddy
    Caddy -->|"Reverse Proxy"| Web1
    Web1 -.-> Web1Internal
```

### Design Principles

1. **Strict `.env` Enforcement:** Every `docker-compose.yml` sets `required: true` on its `.env` file, and `deploy.sh` checks that `/opt/da-cloud/<service-path>/.env` exists before building or starting containers.
2. **Network Segmentation:**
   - `proxy-net` is an external bridge network shared only between `caddy-proxy` and public-facing web containers (`apps/*`).
   - Each web app also has its own `internal: true` bridge network (e.g., `web1-internal`) so databases or Redis instances are only reachable by their parent web app, never by other apps on the VM.
   - Background workers (`services/*`) are never attached to `proxy-net`, preventing accidental public HTTP exposure.
3. **Selective Redeployment:** Modifying `apps/web1` only rebuilds and restarts `web1` without interrupting `caddy-proxy` or other running containers.
