# 🚀 Project Creation Examples

## Quick Laravel Setup

This example shows how to create a complete Laravel project with all necessary services:

```bash
# Create Laravel project with production and staging environments
./scripts/create-project.sh quick laravel my-laravel-app myapp.com
```

**What gets created:**
- ✅ Production environment (myapp.com) with Redis persistence
- ✅ Staging environment (staging.myapp.com) with ephemeral Redis  
- ✅ Database isolation (my-laravel-app_production, my-laravel-app_staging)
- ✅ Queue worker containers
- ✅ Scheduler containers for cron tasks
- ✅ Auto-configured domains and mail settings
- ✅ Auto-generated secure database passwords
- ✅ Laravel-specific post-deployment hooks (migrations, cache clearing)
- ✅ Proper Dockerfile with PHP 8.2, Composer, Nginx

**Domain Configuration:**
- Production: `myapp.com`
- Staging: `staging.myapp.com`
- Mail: `noreply@myapp.com`, `support@myapp.com`

**Generated docker-compose.yml services:**
- `app` - Main Laravel application
- `queue-worker` - Background job processing  
- `scheduler` - Laravel task scheduler
- `redis` - Project-specific Redis instance

**Environment files created:**
- `.env` - Base Laravel configuration
- `production/.env` - Production-specific settings
- `production/.env.database` - Auto-generated DB credentials
- `staging/.env` - Staging-specific settings  
- `staging/.env.database` - Auto-generated DB credentials

## Custom Interactive Setup

```bash
# Start interactive wizard
./scripts/create-project.sh
```

**Interactive prompts:**
1. **Project name**: `my-custom-app` (validates naming)
2. **Environments**: Choose production, staging, development
3. **Domain**: `myapp.com` (auto-configures staging.myapp.com, develop.myapp.com)
4. **Framework/Services**: 
   - Laravel (database + redis + queue + scheduler)
   - Static sites (React, Vue, Angular build output)
   - Custom (choose individual services)

**Automatic Domain Configuration:**
- **Production**: Uses provided domain exactly (e.g., `myapp.com`)
- **Staging**: Adds staging subdomain (e.g., `staging.myapp.com`)
- **Development**: Adds develop subdomain (e.g., `develop.myapp.com`)
- **Mail**: Configures mail settings using main domain (e.g., `noreply@myapp.com`)

## Framework-Specific Features

### 🎯 Laravel Projects
- **Queue Processing**: Automatic `php artisan queue:work` containers
- **Task Scheduling**: Cron-like scheduler with `php artisan schedule:run`
- **Database Migrations**: Auto-run on deployment with `php artisan migrate --force`
- **Storage Links**: Automatic `php artisan storage:link`

### 🎯 Static Site Projects
- **Build Process**: Multi-stage Docker build for frontend assets
- **Web Server**: Nginx serving optimized static files
- **CDN Ready**: Proper caching headers and compression

## Next Steps After Project Creation

1. **Update domains** in environment `.env` files
2. **Add your code** to the project directory
3. **Setup Git repository** with webhook pointing to your infrastructure
4. **Test locally**: `cd projects/my-app/production && docker compose up -d`
5. **Deploy via Git**: Push to main branch for automatic deployment

## Multiple Environment Files Example

Your project will use environment files in this precedence order:

```yaml
# In docker-compose.yml
env_file:
  - ../.env              # Base: APP_NAME, APP_KEY, timezone settings
  - .env                 # Env-specific: APP_ENV, APP_DEBUG, APP_DOMAIN
  - .env.database        # Auto-generated: DB_DATABASE, DB_USERNAME, DB_PASSWORD
```

This allows you to:
- **Share common config** across environments (../.env)
- **Override per environment** (production/.env vs staging/.env)  
- **Keep secrets separate** (.env.database with auto-generated passwords)
- **Version control safely** (exclude .env.database from git)

## Domain Management Features

### 🌐 Automatic Subdomain Configuration

The project creation system automatically configures domains for different environments:

```bash
# Input domain: myapp.com
# Results in:
# - Production: myapp.com
# - Staging: staging.myapp.com  
# - Development: develop.myapp.com
```

### 📧 Mail Configuration

Mail settings are automatically configured using your main domain:

```properties
MAIL_USERNAME=your-email@myapp.com
MAIL_FROM_ADDRESS=noreply@myapp.com
```

### 🔗 Traefik Labels

Docker Compose files include proper Traefik labels for automatic SSL and routing:

```yaml
labels:
  - "traefik.http.routers.myapp-prod.rule=Host(`myapp.com`)"
  - "traefik.http.routers.myapp-staging.rule=Host(`staging.myapp.com`)"
```

### 🚀 DNS Setup Required

After project creation, configure these DNS records:

```
A    myapp.com              → YOUR_SERVER_IP
A    staging.myapp.com      → YOUR_SERVER_IP  
A    develop.myapp.com      → YOUR_SERVER_IP
```

Or use a wildcard record:
```
A    *.myapp.com            → YOUR_SERVER_IP
```