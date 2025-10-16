# Projects Directory

This directory contains configurations and examples for apps to be deployed via the infrastructure setup.

## Structure

Each app has its own folder with branch-based environments:

```
my-app/
├── Dockerfile                    # Shared build context
├── deploy.sh                     # Base deploy script (optional)
├── production/                   # Production env (main branch)
│   └── docker-compose.yml
├── staging/                      # Staging env (staging branch)
│   └── docker-compose.yml
└── development/                  # Dev env (develop branch)
    └── docker-compose.yml
```

**Supported branches/environments:**
- `main` → `production/` 
- `staging` → `staging/`
- `develop` → `development/`

## Integration with Traefik

For your apps to be automatically accessible via Traefik reverse proxy, use these labels in your `docker-compose.yml`:

```yaml
services:
  app:
    # ... your service configuration
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.example.com`)"  # Use your actual domain
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
    networks:
      - web
```

### Multiple Domain Examples

**Option 1: Specific Domain**
```yaml
labels:
  - "traefik.http.routers.myapp.rule=Host(`www.mycompany.com`)"
```

**Option 2: Multiple Domains**
```yaml
labels:
  - "traefik.http.routers.myapp.rule=Host(`myapp.com`) || Host(`www.myapp.com`)"
```

**Option 3: Using Environment Variable (Project-Specific)**
```yaml
labels:
  - "traefik.http.routers.myapp.rule=Host(`${APP_DOMAIN}`)"
```

Then in your project's `.env` file:
```bash
APP_DOMAIN=myapp.com
```

### Redirects and SSL Configuration

**HTTP to HTTPS Redirect (Automatic)**
Traefik automatically redirects HTTP to HTTPS when TLS is enabled. No additional configuration needed!

**WWW vs Non-WWW Redirects**

**Option A: Redirect www to non-www**
```yaml
labels:
  # Main router (non-www)
  - "traefik.http.routers.myapp.rule=Host(`myapp.com`)"
  - "traefik.http.routers.myapp.tls=true"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  
  # WWW redirect router
  - "traefik.http.routers.myapp-www.rule=Host(`www.myapp.com`)"
  - "traefik.http.routers.myapp-www.tls=true"
  - "traefik.http.routers.myapp-www.tls.certresolver=letsencrypt"
  - "traefik.http.routers.myapp-www.middlewares=redirect-to-non-www"
  - "traefik.http.middlewares.redirect-to-non-www.redirectregex.regex=^https://www\\.(.+)"
  - "traefik.http.middlewares.redirect-to-non-www.redirectregex.replacement=https://$${1}"
  - "traefik.http.middlewares.redirect-to-non-www.redirectregex.permanent=true"
```

**Option B: Redirect non-www to www**
```yaml
labels:
  # Main router (www)
  - "traefik.http.routers.myapp.rule=Host(`www.myapp.com`)"
  - "traefik.http.routers.myapp.tls=true"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  
  # Non-WWW redirect router
  - "traefik.http.routers.myapp-redirect.rule=Host(`myapp.com`)"
  - "traefik.http.routers.myapp-redirect.tls=true"
  - "traefik.http.routers.myapp-redirect.tls.certresolver=letsencrypt"
  - "traefik.http.routers.myapp-redirect.middlewares=redirect-to-www"
  - "traefik.http.middlewares.redirect-to-www.redirectregex.regex=^https://(?:www\\.)?(.+)"
  - "traefik.http.middlewares.redirect-to-www.redirectregex.replacement=https://www.$${1}"
  - "traefik.http.middlewares.redirect-to-www.redirectregex.permanent=true"
```

### HTTPS Behind Proxy

**Important:** Your application will receive HTTP traffic from Traefik, even though the client connection is HTTPS. This can cause issues with:
- URL generation pointing to HTTP instead of HTTPS
- Asset URLs being HTTP
- CSRF tokens not working properly
- Mixed content warnings

**Solutions by Framework:**

- **Laravel**: See `LARAVEL.md` for detailed configuration

The key is configuring your application to trust proxy headers and force HTTPS URL generation.

## Networks

Your apps can connect to:
- `web` network - to be accessible via reverse proxy
- `database` network - to access shared database services
- `database` network - to access shared MariaDB and project Redis

## Domain Configuration

### Infrastructure vs App Domains

**Important distinction:**
- **Infrastructure Domain** (`${INFRASTRUCTURE_DOMAIN}`): Used for management interfaces (Traefik dashboard, Grafana, etc.)
- **App Domains**: Completely independent domains for your applications

### Setting Up App Domains

1. **In your project's `.env` file:**
```bash
APP_DOMAIN=myapp.com
# or for staging
APP_DOMAIN=staging.myapp.com
```

2. **In your `docker-compose.yml`:**
```yaml
labels:
  - "traefik.http.routers.myapp.rule=Host(`${APP_DOMAIN}`)"
```

3. **DNS Configuration:**
   - Point your domain's A record to your server's IP
   - Let's Encrypt will automatically generate SSL certificates

### Domain Examples

- ✅ `myapp.com` → Your production app
- ✅ `staging.myapp.com` → Your staging environment  
- ✅ `api.mycompany.net` → Your API service
- ✅ `blog.example.org` → Your blog

**Note:** App domains are completely independent from your infrastructure domain (`your-infrastructure-domain.com`).

## Examples

Projects are now created using the project creation wizard:

```bash
# Create any framework project
./scripts/create-project.sh

# Quick Laravel setup  
./scripts/create-project.sh quick laravel my-app myapp.com

# See all available frameworks
./scripts/create-project.sh quick
```

- **`LARAVEL.md`** - Laravel-specific configuration guide for HTTPS detection and deployment

## Framework-Specific Guides

- **Laravel**: See `LARAVEL.md` for detailed Laravel configuration
- **Other frameworks**: Configure trusted proxies and HTTPS detection as shown above

## Deployment

### Automatic Deployment Flow

1. **Push to main branch** on GitHub
2. **GitHub webhook** sends signal to infrastructure server
3. **Webhook dispatcher** finds your project directory
4. **Deploy script** runs:
   - If `deploy.sh` exists → runs project-specific deployment
   - Otherwise → generic Docker Compose deployment
5. **App is live** with automatic HTTPS

### Deploy Script (Recommended)

Create a `deploy.sh` in your project directory for custom deployment logic:

```bash
#!/bin/bash
set -e

# Environment variables available:
# - REPOSITORY_NAME: GitHub repo name
# - PROJECT_DIR: Path to project directory  
# - COMMIT_SHA: Git commit hash
# - PUSHER_NAME: Who pushed

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [MY-APP] $1"
}

log "Starting deployment for $REPOSITORY_NAME"

# Git update (if it's a git repo)
if [ -d ".git" ]; then
    git fetch origin
    git reset --hard origin/main
fi

# Custom deployment steps
docker compose pull
docker compose build --no-cache
docker compose up -d

# App-specific commands (e.g. Laravel migrations)
docker compose exec -T app php artisan migrate --force

log "Deployment completed!"
```

### Webhook Configuration

Make sure to configure webhook secrets in `../hooks.json` and in your GitHub repository.