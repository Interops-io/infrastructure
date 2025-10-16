# 🚀 Docker Infrastructure for Hosting Services

This repository contains a complete Docker-based infrastructure for hosting various services with automatic deployment, reverse proxy, monitoring, and status dashboard.

## ✨ Features

- **🌐 Reverse Proxy**: Traefik v3.0 with automatic SSL certificates via Let's Encrypt
- **🗄️ Databases**: MariaDB and Redis for your applications with secure user isolation
- **🔄 Webhooks**: Git provider agnostic deployment system (GitHub, GitLab, etc.)
- **📊 Monitoring**: Prometheus + Grafana with status dashboard
- **🌍 Multi-environment**: Branch-based deployment (main→production, staging→staging, develop→development)
- **🔒 Security**: VPN-restricted infrastructure access + isolated database users
- **🎯 Hook System**: Pre/post deployment hooks for service-specific actions
- **📈 Status Dashboard**: Grafana-based deployment status via `status.domain.com` (VPN-restricted)

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Git Repos     │───▶│  Webhook System  │───▶│  Docker Stack   │
│ (GitHub/GitLab) │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                ▲                        │
                                │                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Status Dashboard│◀───│    Traefik       │◀───│   Your Apps     │
│   (Grafana)     │    │  Reverse Proxy   │    │ (Auto-deployed) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🚀 Installation & Setup

### 🎯 **Complete Server Setup (New Server)**

For new servers without Docker or infrastructure, use the automated setup:

```bash
# Option 1: Clone repo and run installer (recommended)
git clone https://github.com/yourusername/infrastructure.git
cd infrastructure
./install.sh

# Option 2: Direct download and run
curl -fsSL https://raw.githubusercontent.com/yourusername/infrastructure/main/install.sh | bash

# Option 3: Download script first (if you want to inspect it)
wget https://raw.githubusercontent.com/yourusername/infrastructure/main/install.sh
chmod +x install.sh
./install.sh
```

The installer will:
- ✅ Check system requirements (RAM, disk space, OS)
- ✅ Create dedicated `infrastructure` user
- ✅ Install Docker + Docker Compose
- ✅ Generate SSH keys for Git access
- ✅ Clone infrastructure repository
- ✅ Create `.env` file with secure passwords
- ✅ Set up proper permissions and directories

**After installation:** Update domains in `.env`, add SSH key to Git provider, configure DNS, and optionally configure firewall.

---

### ⚡ **Quick Start (Existing Docker Setup)**

If you already have Docker installed and just want to start the infrastructure:

```bash
# Clone and start infrastructure
git clone https://github.com/yourusername/infrastructure.git
cd infrastructure

# Setup environment variables
cp .env.example .env
nano .env  # Update domains and passwords

# Start services
docker-compose up -d

# Test deployment (optional)
./test-deployment.sh
```

---

###  **System Requirements**
- **OS**: Ubuntu 20.04+ (or Debian 11+)
- **RAM**: Minimum 1GB, recommended 2GB+ (depends on your applications)
- **Storage**: Minimum 20GB SSD (for infrastructure only - add storage based on your apps)
- **Network**: Static IP with port 80, 443, and SSH access

**Note**: These are requirements for the infrastructure stack only. Add additional resources based on your specific applications.

---

### 🔨 **Manual Installation (If Automated Fails)**

Use these steps if the automated installer doesn't work for your environment:

### 👤 **1. User Setup**
```bash
# Create dedicated user for infrastructure
sudo useradd -m -s /bin/bash -G docker infrastructure
sudo usermod -aG sudo infrastructure

# Switch to infrastructure user
sudo su - infrastructure
```

### 🐳 **2. Docker Installation**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Restart to activate Docker group
sudo reboot
```

### 🔑 **3. SSH Keys Setup (For Private Repositories)**
```bash
# Generate SSH key for Git access
ssh-keygen -t ed25519 -C "infrastructure@your-infrastructure-domain.com" -f ~/.ssh/id_ed25519_git

# Display public key (add to Git provider)
cat ~/.ssh/id_ed25519_git.pub

# Configure SSH config
cat >> ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_git
    AddKeysToAgent yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_git
    AddKeysToAgent yes
EOF

chmod 600 ~/.ssh/config
```

### 📁 **4. Repository Setup**
```bash
# Recommended location for infrastructure
cd /home/infrastructure
git clone git@github.com:yourusername/infrastructure.git
cd infrastructure

# Set correct permissions
sudo chown -R infrastructure:infrastructure /home/infrastructure/infrastructure
chmod +x scripts/*.sh
chmod +x test-deployment.sh
```

### 🔥 **5. Firewall Configuration**
```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

### 🌐 **6. DNS Configuration**
Configure the following DNS records with your DNS provider:

**DNS Records:**
```
A    your-infrastructure-domain.com              → SERVER_IP
A    *.your-infrastructure-domain.com           → SERVER_IP
```

**Endpoints:**
- `status.your-infrastructure-domain.com` → Status Dashboard (Grafana - VPN Only)
- `traefik.your-infrastructure-domain.com` → Traefik Dashboard (VPN Only)  
- `webhook.your-infrastructure-domain.com` → Webhook Endpoint (Public)
- `yourproject.your-infrastructure-domain.com` → Your Apps (Public)

### 🔗 **Setup Git Webhooks**
Add webhook URL in your Git repository:
- **URL**: `https://webhook.your-infrastructure-domain.com/hooks/deploy`
- **Events**: Push events
- **Content-Type**: `application/json`

---

## 🎯 Project Creation & Management

### 🚀 **Creating New Projects**

Use the interactive project creation wizard to set up new projects with proper structure and configuration:

```bash
# Interactive mode - full wizard
./scripts/create-project.sh

# Quick setup modes for any configured framework
./scripts/create-project.sh quick laravel my-app myapp.com      # Laravel with DB, Redis, Queue, Scheduler
./scripts/create-project.sh quick react my-site mysite.com     # React SPA with static serving
./scripts/create-project.sh quick vue my-vue vue.example.com    # Vue.js SPA with static serving

# See all available frameworks
./scripts/create-project.sh quick
```

#### **🎮 Interactive Mode Features:**
- **Project Name Validation**: Ensures valid naming conventions
- **Environment Selection**: Choose production, staging, development
- **Domain Configuration**: Automatic subdomain setup (staging.domain.com, develop.domain.com)
- **Configurable Framework Presets**: Laravel and static sites from config file
- **Service Selection**: Database, Redis, Queue worker, Scheduler, WebSockets
- **Auto-generated Structure**: Complete docker-compose, .env files, and Dockerfile

#### **📋 Available Framework Presets:**
- **Laravel**: Full-stack PHP with database, redis, queue workers, scheduler
- **React/Vue**: Static SPA serving with Nginx
- **WordPress**: PHP CMS with database and redis caching
- **Static**: Pure HTML/CSS/JS websites

> 💡 **Extensible**: Add new frameworks by editing `config/quick-setups.conf` - See [QUICK-SETUPS.md](docs/QUICK-SETUPS.md) for configuration guide

#### **📦 What Gets Created:**
```
projects/your-project/
├── .env                     # Base configuration
├── Dockerfile              # Framework-specific container
├── pre_deploy.sh           # Pre-deployment hooks
├── post_deploy.sh          # Post-deployment hooks (framework-specific tasks)
├── production/
│   ├── docker-compose.yml  # Production services configuration
│   ├── .env                # Production environment variables
│   ├── .env.database       # Auto-generated database credentials
│   └── logs/               # Application logs directory
└── staging/
    ├── docker-compose.yml  # Staging services configuration  
    ├── .env                # Staging environment variables
    ├── .env.database       # Auto-generated database credentials
    └── logs/               # Application logs directory
```

### 🔧 **Environment File Strategy**

The system uses **multiple environment files** with precedence order:

```yaml
env_file:
  - ../.env              # Base project configuration (shared)
  - .env                 # Environment-specific overrides  
  - .env.database        # Auto-generated database credentials
```

**Benefits:**
- **🔒 Security**: Database credentials separate from main config
- **🔄 Automation**: Database passwords auto-generated during setup
- **🌍 Flexibility**: Easy environment-specific customization
- **🔐 Isolation**: Each project gets isolated database users

### 📊 **Database Management**

Database setup is **automated during project creation**, but can be run manually:

```bash
# Setup database for specific project/environment
./scripts/setup-database.sh setup ./projects/my-app production

# Setup databases for all projects  
./scripts/setup-database.sh setup-all ./projects staging
```

**Database Isolation Features:**
- **🔒 Per-project Users**: Each project gets isolated database user
- **🎯 Environment Separation**: `myapp_production`, `myapp_staging` databases
- **🔐 Auto-generated Passwords**: Secure random passwords in `.env.database`
- **⚡ Shared Infrastructure**: Single MariaDB instance with proper isolation

> 📖 **More Examples**: See [PROJECT-CREATION.md](docs/PROJECT-CREATION.md) for detailed examples and framework-specific features.

---

## 🎯 Hook System & Deployment Customization

### 🔄 **How Deployment Hooks Work**

The system supports **pre-deploy** and **post-deploy** hooks that run automatically during deployment. Hooks can be **general** (run for the entire project) or **service-specific** (run only for specific services).

#### **Hook Execution Order:**
```
1. 🔍 Git Webhook received
2. 📝 Pre-deploy hooks executed
3. 🚀 Main deployment (docker-compose up -d)  
4. ✅ Post-deploy hooks executed
5. 🧹 Cleanup (image pruning)
```

### 📂 **Hook File Structure**

Hooks are placed in your project folder and follow the naming convention:
```
projects/your-project/
├── production/
│   ├── docker-compose.yml
│   ├── .env
│   ├── pre_deploy.sh              # General pre-deploy hook
│   ├── pre_deploy.app.sh          # Pre-deploy hook for 'app' service
│   ├── post_deploy.sh             # General post-deploy hook
│   ├── post_deploy.app.sh         # Post-deploy hook for 'app' service
│   └── post_deploy.redis.sh       # Post-deploy hook for 'redis' service
├── staging/
│   └── ... (samme struktur)
└── .env                           # Base environment variables
```

### 🛠️ **Hook Examples**

#### **Pre-Deploy Hook** (`pre_deploy.app.sh`)
Runs **before** deployment - typically for backup or preparation:
```bash
#!/bin/bash
# Pre-deploy hook for app service

echo "🔄 Running pre-deploy tasks for app..."

# Backup database before deployment
docker exec mariadb-shared mysqldump -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} > /backup/$(date +%Y%m%d_%H%M%S)_pre_deploy.sql

# Stop specific services gracefully
docker compose stop app

echo "✅ Pre-deploy completed"
```

#### **Post-Deploy Hook** (`post_deploy.app.sh`) 
Runs **after** deployment - typically for migrations and cache clearing:
```bash
#!/bin/bash
# Post-deploy hook for app service

echo "🚀 Running post-deploy tasks for app..."

# Wait for app to be ready
sleep 10

# Run Laravel migrations and optimizations
docker compose exec -T app php artisan migrate --force
docker compose exec -T app php artisan config:cache
docker compose exec -T app php artisan route:cache
docker compose exec -T app php artisan view:cache

# Restart queue workers
docker compose restart queue-worker

# Health check
if curl -f http://localhost:8080/health; then
    echo "✅ App health check passed"
else
    echo "❌ App health check failed"
    exit 1
fi

echo "✅ Post-deploy completed"
```

#### **Database Migration Hook** (`post_deploy.db.sh`)
Service-specific hook for database operations:
```bash
#!/bin/bash
# Post-deploy hook for database operations

echo "🗄️ Running database post-deploy tasks..."

# Wait for MariaDB to be ready
until docker compose exec -T mariadb-shared mysqladmin ping -h"localhost" --silent; do
    echo "Waiting for MariaDB..."
    sleep 2
done

# Create additional database users if needed
docker compose exec -T mariadb-shared mysql -u root -p${MYSQL_ROOT_PASSWORD} << EOF
CREATE USER IF NOT EXISTS '${PROJECT_USER}'@'%' IDENTIFIED BY '${PROJECT_PASSWORD}';
GRANT ALL PRIVILEGES ON ${PROJECT_DATABASE}.* TO '${PROJECT_USER}'@'%';
FLUSH PRIVILEGES;
EOF

echo "✅ Database setup completed"
```

### 🔧 **Available Environment Variables in Hooks**

All hooks have access to the following environment variables:
```bash
# Repository information
$REPOSITORY_NAME       # "your-project"
$BRANCH_NAME          # "main", "staging", "develop"  
$ENVIRONMENT          # "production", "staging", "development"
$COMMIT_SHA           # "abc123..."
$PUSHER_NAME          # "john.doe"

# Directories
$PROJECT_DIR          # "/projects/your-project/production"
$BASE_PROJECT_DIR     # "/projects/your-project"
$PROJECTS_DIR         # "/projects"

# Deployment info
$BUILD_DATE           # "2025-10-16T10:30:00Z"
$REF                  # "refs/heads/main"

# Plus all variables from .env files
```

### 🎯 **Hook Best Practices**

#### ✅ **DO:**
- **Make hooks idempotent** - safe to run multiple times
- **Use service-specific hooks** for targeted operations
- **Include error handling** and proper exit codes
- **Log operations** for debugging
- **Test hooks** in staging environment first

#### ❌ **DON'T:**
- Don't make hooks dependent on external services being up
- Don't use hooks for long-running operations (use background jobs)
- Don't forget to make hooks executable (`chmod +x`)
- Don't hardcode values - use environment variables

### 🧪 **Testing Hooks Locally**

```bash
# Navigate to your project directory
cd /home/infrastructure/infrastructure/projects/your-project/production

# Set up test environment
export REPOSITORY_NAME="your-project"
export ENVIRONMENT="production"
export BRANCH_NAME="main"
export PROJECT_DIR="$(pwd)"

# Test individual hooks
./pre_deploy.app.sh
./post_deploy.app.sh
```

## 📁 Project Structure

```
infrastructure/
├── install.sh                      # Automated installation script (main setup)
├── docker-compose.yml              # Main infrastructure services
├── .env.example                    # Environment variables template  
├── test-deployment.sh              # Infrastructure test script
│
├── traefik/                        # Reverse proxy configuration
│   ├── dynamic/
│   │   └── middleware.yml          # Security headers, CORS, etc.
│   └── acme.json                   # Let's Encrypt certificates (auto-generated)
│
├── hooks.json                      # Git webhook configuration
│
├── config/                         # Configuration files
│   └── quick-setups.conf           # Framework presets for project creation
│
├── scripts/                        # Deployment and utility scripts  
│   ├── create-project.sh           # 🚀 Interactive project creation wizard
│   ├── webhook-dispatcher.sh       # Git provider agnostic deployment handler
│   ├── setup-database.sh           # Database user setup utility
│   └── backup.sh                   # Backup utility script
│
├── projects/                       # Your application configurations
│   ├── README.md                   # Project setup guide
│   ├── LARAVEL.md                  # Laravel-specific configuration
│   └── your-projects/              # Created via ./scripts/create-project.sh
│
├── monitoring/                     # Monitoring and observability
│   ├── prometheus.yml              # Prometheus configuration
│   └── grafana/
│       ├── provisioning/           # Auto-provisioning config
│       └── dashboards/
│           └── status-dashboard.json
│
├── status/                         # Public status dashboard
│   ├── index.html                  # Status page wrapper
│   └── nginx.conf                  # Nginx configuration
│
└── volumes/                        # Database initialization
    └── mariadb/init/
        └── create-users.sql        # Database user setup
```

## 🔧 Environment Configuration

### Main Infrastructure (.env)
```bash
# Infrastructure Domain (where all infrastructure runs)
INFRASTRUCTURE_DOMAIN=your-infrastructure-domain.com

# Project Domain (where your apps run)  
DOMAIN=your-infrastructure-domain.com

# Database credentials
MYSQL_ROOT_PASSWORD=your_secure_root_password_here
MYSQL_DATABASE=laravel
MYSQL_USER=laravel
MYSQL_PASSWORD=your_secure_user_password_here

# Grafana credentials
GRAFANA_USER=admin
GRAFANA_PASSWORD=your_secure_grafana_password_here
```

## 🚀 Deployment Flow

### Branch-Based Environments
- `main` branch → Production environment
- `staging` branch → Staging environment  
- `develop` branch → Development environment

### Hook System
Each project kan have pre/post deployment hooks:

```bash
# projects/yourproject/production/hooks/pre-deploy.sh
#!/bin/bash
echo "Preparing deployment..."
docker-compose down

# projects/yourproject/production/hooks/post-deploy.sh  
#!/bin/bash
echo "Running post-deployment tasks..."
docker-compose exec app php artisan migrate --force
docker-compose exec app php artisan cache:clear
```

## 📊 Monitoring & Status

### Status Dashboard
Public status page tilgængelig på `status.your-infrastructure-domain.com` viser:
- Deployment status (Running, Deploying, Stopped)
- Latest changes og commit info
- Service health status

### Monitoring Stack
- **Prometheus**: Metrics collection på `prometheus.your-infrastructure-domain.com` (VPN Only)
- **Grafana**: Dashboards og alerting på `monitoring.your-infrastructure-domain.com` (VPN Only)

## 🔒 Security Features

### VPN-Only Infrastructure Access
Infrastructure endpoints er kun tilgængelige via VPN:
- Traefik Dashboard
- Prometheus  
- Grafana Admin
- Database access

### Database Security
- Isolated database users per project/environment
- No direct external database access
- Automatic user creation via init scripts

## 🆕 Adding New Projects

### 1. Create Project Structure
```bash
mkdir -p projects/my-new-app/{production,staging,development}
```

### 2. Add Docker Compose for Each Environment
```yaml
# projects/my-new-app/production/docker-compose.yml
version: '3.8'

services:
  my-app:
    build: 
      context: ../../../../my-app-repo
      dockerfile: Dockerfile
    restart: unless-stopped
    environment:
      - APP_ENV=production
      - DB_HOST=mariadb-shared
      - REDIS_HOST=redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp-prod.rule=Host(\`myapp.${DOMAIN}\`)"
      - "traefik.http.routers.myapp-prod.tls=true"
      - "traefik.http.routers.myapp-prod.tls.certresolver=letsencrypt"
    networks:
      - web
      - database
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    container_name: myapp-redis-prod
    restart: unless-stopped
    command: redis-server --save 60 1000 --loglevel warning --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - database
    labels:
      - "traefik.enable=false"

networks:
  web:
    external: true
    name: traefik_web
  database:
    external: true
    name: database_access

volumes:
  redis_data:
```

### 🔄 **Redis Persistence Configuration**

Each project gets its own Redis instance with **environment-specific persistence**:

**✅ Production (Persistent):**
- **Named volume**: `redis_data_prod` - Docker manages storage location
- **Auto-save**: `--save 60 1000` - saves every 60 seconds if 1000+ keys changed  
- **Memory limit**: `--maxmemory 256mb`
- **Data survives**: deployments, container restarts, server reboots

**🚀 Staging (Ephemeral):**
- **No persistence** - fresh Redis on each deployment
- **Memory limit**: `--maxmemory 128mb` 
- **Perfect for testing** - clean state every deploy

**� What persists in production:**
- User sessions (stay logged in across deployments)
- Application cache (performance data retained)
- Queue jobs (Laravel queues survive deployments)
- Any custom Redis data

**📍 Where is the data stored?**
- Docker manages named volumes at `/var/lib/docker/volumes/redis_data_prod/_data`
- Included in `docker volume ls` and standard Docker backup tools

### 3. Add Deployment Hooks (Optional)
```bash
mkdir -p projects/my-new-app/production/hooks
# Create pre-deploy.sh and post-deploy.sh as needed
```

### 4. Configure Git Webhook
Push til dit repository og webhook systemet deployer automatisk baseret på branch.

## 🔧 Management Commands

### View Logs
```bash
# All infrastructure logs
docker-compose logs -f

# Specific service logs
docker-compose logs -f traefik
docker-compose logs -f webhook
docker-compose logs -f grafana
```

### Backup Database
```bash
# Backup all databases
docker-compose exec mariadb-shared mysqldump -u root -p --all-databases > backup-$(date +%Y%m%d).sql
```

### Restart Services
```bash
# Restart specific service
docker-compose restart webhook

# Restart everything
docker-compose down && docker-compose up -d
```

### Update Infrastructure
```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose down && docker-compose up -d
```

## 🐛 Troubleshooting

### Common Issues

**Webhook not accessible**
- Check DNS configuration
- Verify Traefik routing and certificates
- Check firewall rules

**App doesn't deploy**
- Check webhook logs: `docker-compose logs webhook`
- Verify Git repository has access to webhook URL
- Check project docker-compose.yml format

**Database connection error**
- Verify database credentials in .env
- Check if database users are created
- Verify network connectivity

### Debug Commands
```bash
# Check service health
docker-compose ps

# Check Traefik routes
curl -s http://localhost:8080/api/http/routers | jq

# Test webhook endpoint
curl -X POST https://webhook.your-infrastructure-domain.com/hooks/deploy \
  -H "Content-Type: application/json" \
  -d '{"ref": "refs/heads/main", "repository": {"clone_url": "https://github.com/user/repo.git"}}'
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🆘 Support

## 🔧 Troubleshooting

### 🚨 **Common Issues**

#### **Docker Permission Denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again, or:
sudo reboot
```

#### **Webhook Not Triggering**
```bash
# Check webhook logs
docker logs webhook -f

# Test webhook manually
curl -X POST https://webhook.your-infrastructure-domain.com/hooks/deploy \
  -H "Content-Type: application/json" \
  -d '{"repository":{"name":"your-project"},"ref":"refs/heads/main"}'
```

#### **SSL Certificate Issues**
```bash
# Check Traefik logs
docker logs traefik -f

# Verify acme.json permissions
sudo chmod 600 traefik/acme.json
sudo chown root:root traefik/acme.json
```

#### **Database Connection Failed**
```bash
# Check MariaDB logs
docker logs mariadb-shared -f

# Test database connection
docker exec -it mariadb-shared mysql -u root -p
```

#### **Git Clone Failed in Hooks**
```bash
# Check SSH key permissions
chmod 600 ~/.ssh/id_ed25519_git
chmod 644 ~/.ssh/id_ed25519_git.pub

# Test Git access
ssh -T git@github.com
```

### 📋 **Log Locations**

```bash
# Infrastructure logs
docker logs traefik
docker logs webhook  
docker logs prometheus
docker logs grafana

# Application logs
docker logs your-app-container

# Webhook dispatcher logs
docker exec webhook tail -f /var/log/webhook/dispatcher.log

# System logs
sudo journalctl -u docker
```

### 🔍 **Health Checks**

```bash
# Run infrastructure test
./test-deployment.sh

# Check all services
docker-compose ps

# Check resource usage
docker stats

# Check disk space
df -h
docker system df
```

### 🆘 **Emergency Procedures**

#### **Rollback Deployment**
```bash
# Stop current deployment
cd /home/infrastructure/infrastructure/projects/your-project/production
docker-compose down

# Restore from backup (if available)
# ... restore database backup ...

# Deploy previous version
git checkout <previous-commit>
docker-compose up -d
```

#### **Complete Infrastructure Reset**
```bash
# ⚠️ WARNING: This will destroy all data!
cd /home/infrastructure/infrastructure
docker-compose down -v
docker system prune -a --volumes -f
rm -rf volumes/
git pull origin main
./test-deployment.sh
```

---

For support and questions:
- Create an issue in this repository  
- Check logs using the commands above
- Test with `./test-deployment.sh` first

**Made with ❤️ for easy Docker hosting**