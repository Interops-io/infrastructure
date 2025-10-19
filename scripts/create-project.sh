#!/bin/bash

# Project Creation Wizard
# Creates new projects with proper structure, docker-compose files, and environment setup

set -e

# Ensure we're using bash (associative arrays require bash 4+)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "This script requires Bash 4.0 or higher for associative arrays"
    echo "Current version: $BASH_VERSION"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$INFRASTRUCTURE_DIR/projects"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Track assigned ports to prevent conflicts
declare -A ASSIGNED_PORTS

# Find next available port starting from 30000
find_available_port() {
    local port=30000
    
    # Check if we have port checking tools available
    local has_netstat=false
    local has_ss=false
    command -v netstat >/dev/null 2>&1 && has_netstat=true
    command -v ss >/dev/null 2>&1 && has_ss=true
    
    while true; do
        # Check if port is already assigned in this session
        if [[ -n "${ASSIGNED_PORTS[$port]}" ]]; then
            ((port++))
            continue
        fi
        
        # Check if port is in use by system (if tools available)
        local port_in_use=false
        if $has_netstat && netstat -tuln 2>/dev/null | grep -q ":$port "; then
            port_in_use=true
        elif $has_ss && ss -tuln 2>/dev/null | grep -q ":$port "; then
            port_in_use=true
        fi
        
        if ! $port_in_use; then
            break
        fi
        
        ((port++))
    done
    
    ASSIGNED_PORTS[$port]=1  # Mark as assigned
    echo $port
}

# Show banner
show_banner() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "🚀 Project Creation Wizard"
    echo "=========================================="
    echo -e "${NC}"
    echo
}

# Available services
declare -A SERVICES
SERVICES[database]="MariaDB database (uses shared infrastructure DB)"
SERVICES[database-own]="MariaDB database (project-specific with debug port)"
SERVICES[redis]="Redis cache/sessions/queues (per-project instance)"
SERVICES[queue]="Background job processing"
SERVICES[scheduler]="Cron-like task scheduling"
SERVICES[websockets]="WebSocket server (e.g., Laravel Broadcasting)"

# Configuration files
QUICK_SETUPS_CONFIG="$INFRASTRUCTURE_DIR/config/quick-setups.conf"

# Load quick setup presets from config file
declare -A QUICK_SETUPS
load_quick_setups() {
    if [[ ! -f "$QUICK_SETUPS_CONFIG" ]]; then
        log_warning "Quick setups config file not found: $QUICK_SETUPS_CONFIG"
        return 1
    fi
    
    local current_preset=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Parse preset section headers
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            current_preset="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse key=value pairs
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]] && [[ -n "$current_preset" ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            QUICK_SETUPS["${current_preset}_${key}"]="$value"
        fi
    done < "$QUICK_SETUPS_CONFIG"
}

# Get available quick setups
get_available_quick_setups() {
    local presets=()
    for key in "${!QUICK_SETUPS[@]}"; do
        if [[ "$key" =~ ^([^_]+)_description$ ]]; then
            presets+=("${BASH_REMATCH[1]}")
        fi
    done
    echo "${presets[@]}" | tr ' ' '\n' | sort | tr '\n' ' '
}

# Get project name
get_project_name() {
    while true; do
        read -p "📝 Enter project name (lowercase, no spaces): " PROJECT_NAME
        
        # Validate project name
        if [[ "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
            if [[ ! -d "$PROJECTS_DIR/$PROJECT_NAME" ]]; then
                break
            else
                log_error "Project '$PROJECT_NAME' already exists!"
            fi
        else
            log_error "Invalid project name. Use lowercase letters, numbers, and hyphens only."
        fi
    done
    
    log_success "Project name: $PROJECT_NAME"
}

# Get domain
get_domain() {
    echo
    while true; do
        read -p "🌐 Enter domain for production (e.g., myapp.com): " PROJECT_DOMAIN
        
        # Basic domain validation
        if [[ "$PROJECT_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] && [[ "$PROJECT_DOMAIN" == *.* ]]; then
            break
        else
            log_error "Invalid domain format. Please enter a valid domain (e.g., myapp.com, app.example.com)"
        fi
    done
    
    log_success "Production domain: $PROJECT_DOMAIN"
    if [[ " ${ENVIRONMENTS[*]} " =~ " staging " ]]; then
        log_info "Staging domain: staging.$PROJECT_DOMAIN"
    fi
    if [[ " ${ENVIRONMENTS[*]} " =~ " development " ]]; then
        log_info "Development domain: develop.$PROJECT_DOMAIN"
    fi
}

# Get environments
get_environments() {
    echo
    log_info "📦 Select environments to create:"
    echo "1) Production only"
    echo "2) Production + Staging"
    echo "3) Production + Staging + Development"
    
    while true; do
        read -p "Choose (1-3): " env_choice
        case $env_choice in
            1) ENVIRONMENTS=("production"); break ;;
            2) ENVIRONMENTS=("production" "staging"); break ;;
            3) ENVIRONMENTS=("production" "staging" "development"); break ;;
            *) log_error "Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done
    
    log_success "Environments: ${ENVIRONMENTS[*]}"
}

# Get framework or custom setup
get_framework_or_services() {
    echo
    log_info "🛠️  Choose setup type:"
    
    # Load quick setups from config
    if ! load_quick_setups; then
        log_error "Failed to load quick setup configurations"
        exit 1
    fi
    
    # Build menu from loaded presets
    local presets=($(get_available_quick_setups))
    local menu_counter=1
    declare -A menu_mapping
    
    # Show available presets
    for preset in "${presets[@]}"; do
        if [[ -n "${QUICK_SETUPS[${preset}_description]}" ]]; then
            echo "$menu_counter) ${preset^} - ${QUICK_SETUPS[${preset}_description]}"
            menu_mapping[$menu_counter]="$preset"
            ((menu_counter++))
        fi
    done
    
    echo "$menu_counter) Custom (choose individual services)"
    local custom_option=$menu_counter
    
    while true; do
        read -p "Choose (1-$menu_counter): " framework_choice
        
        if [[ "$framework_choice" == "$custom_option" ]]; then
            FRAMEWORK="custom"
            get_custom_services
            # For custom setup, default to Laravel-style volumes (can be customized later)
            FRAMEWORK_VOLUMES="./storage:/var/www/html/storage"
            break
        elif [[ -n "${menu_mapping[$framework_choice]}" ]]; then
            FRAMEWORK="${menu_mapping[$framework_choice]}"
            
            # Parse services from config
            local services_str="${QUICK_SETUPS[${FRAMEWORK}_services]}"
            if [[ -n "$services_str" ]]; then
                IFS=',' read -ra SELECTED_SERVICES <<< "$services_str"
                
                # If database is in the services, ask which type (only for setups that need it)
                if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
                    # Check if preset already specifies database type
                    if [[ -n "${QUICK_SETUPS[${FRAMEWORK}_database_type]}" ]]; then
                        # Use preset database type, replace 'database' with specific type
                        SELECTED_SERVICES=("${SELECTED_SERVICES[@]/database}")
                        SELECTED_SERVICES+=("${QUICK_SETUPS[${FRAMEWORK}_database_type]}")
                    else
                        # Remove generic 'database' from array and ask user
                        SELECTED_SERVICES=("${SELECTED_SERVICES[@]/database}")
                        # Ask for database type
                        get_database_type
                    fi
                fi
            else
                SELECTED_SERVICES=()
            fi
            
            # DON'T override user's environment selection with config
            # Parse environments from config only if user hasn't selected yet
            if [[ ${#ENVIRONMENTS[@]} -eq 0 ]]; then
                local env_str="${QUICK_SETUPS[${FRAMEWORK}_environments]}"
                if [[ -n "$env_str" ]]; then
                    IFS=',' read -ra ENVIRONMENTS <<< "$env_str"
                fi
            fi
            
            # Load volumes configuration
            FRAMEWORK_VOLUMES="${QUICK_SETUPS[${FRAMEWORK}_volumes]:-}"
            
            break
        else
            log_error "Invalid choice. Please enter a number between 1 and $menu_counter."
        fi
    done
    
    log_success "Framework: $FRAMEWORK"
    if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
        log_success "Services: ${SELECTED_SERVICES[*]}"
    fi
}

# Get database type choice
get_database_type() {
    echo
    log_info "📊 Choose database setup:"
    echo "1) Shared database (uses infrastructure MariaDB)"
    echo "2) Project-specific database (own container with debug port)"
    
    while true; do
        read -p "Choose (1-2): " db_choice
        case $db_choice in
            1) 
                SELECTED_SERVICES+=("database")
                log_success "Using shared database"
                break 
                ;;
            2) 
                SELECTED_SERVICES+=("database-own")
                log_success "Using project-specific database"
                break 
                ;;
            *) 
                log_error "Invalid choice. Please enter 1 or 2." 
                ;;
        esac
    done
}

# Get custom services
get_custom_services() {
    SELECTED_SERVICES=()
    
    echo
    log_info "🔧 Select services (press Enter when done):"
    
    local service_list=(redis queue scheduler websockets)
    
    # Ask about database first (special handling)
    read -p "Include database? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        get_database_type
    fi
    
    # Ask about other services
    for service in "${service_list[@]}"; do
        read -p "Include $service? (${SERVICES[$service]}) [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            SELECTED_SERVICES+=("$service")
        fi
    done
}

# Generate volume mounts based on framework configuration
generate_volumes_section() {
    if [[ -n "${FRAMEWORK_VOLUMES:-}" ]]; then
        echo "    volumes:"
        IFS=',' read -ra volume_array <<< "$FRAMEWORK_VOLUMES"
        for volume in "${volume_array[@]}"; do
            # Safely expand PROJECT_NAME and env variables only
            local expanded_volume="${volume//\$\{PROJECT_NAME\}/$PROJECT_NAME}"
            expanded_volume="${expanded_volume//\$\{env\}/$env}"
            echo "      - $expanded_volume"
        done
    fi
}

# Generate docker-compose.yml for environment
generate_docker_compose() {
    local env=$1
    local compose_file="$PROJECTS_DIR/$PROJECT_NAME/$env/docker-compose.yml"
    
    # Determine container suffix
    local suffix=""
    case $env in
        production) suffix="prod" ;;
        staging) suffix="staging" ;;
        development) suffix="dev" ;;
    esac
    
    log_info "Generating docker-compose.yml for $env environment..."
    
    cat > "$compose_file" << EOF
version: '3.8'

services:
  app:
    build:
      context: ./source  # Source code cloned by webhook dispatcher
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME}-app-${suffix}
    restart: unless-stopped
    env_file:
      - ../.env              # Base environment variables
      - .env                 # Environment-specific overrides
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - .env.database        # Database credentials (auto-generated)
ENVEOF
fi)
    environment:
      - APP_ENV=${env}
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb-shared
ENVEOF
elif [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb
ENVEOF
fi)
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
      - REDIS_HOST=redis
ENVEOF
fi)
$(generate_volumes_section)
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${PROJECT_NAME}-${suffix}.rule=Host(\`\$\${APP_DOMAIN:-${PROJECT_NAME}.localhost}\`)"
      - "traefik.http.routers.${PROJECT_NAME}-${suffix}.tls=true"
      - "traefik.http.routers.${PROJECT_NAME}-${suffix}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${PROJECT_NAME}-${suffix}.loadbalancer.server.port=80"
      - "traefik.http.routers.${PROJECT_NAME}-${suffix}.middlewares=secure-headers"
    networks:
      - web
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - database
ENVEOF
fi)
$(# Only add depends_on section if there are actual dependencies
if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " queue " ]]; then
cat << 'ENVEOF'
    depends_on:
ENVEOF
if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
      - redis
ENVEOF
fi
if [[ " ${SELECTED_SERVICES[*]} " =~ " queue " ]]; then
cat << 'ENVEOF'
      - queue-worker
ENVEOF
fi
fi)

EOF

    # Add queue worker if selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " queue " ]]; then
        cat >> "$compose_file" << EOF
  queue-worker:
    build:
      context: ./source  # Source code cloned by webhook dispatcher
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME}-queue-${suffix}
    restart: unless-stopped
    command: php artisan queue:work --sleep=3 --tries=3 --max-time=3600
    env_file:
      - ../.env
      - .env
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - .env.database
ENVEOF
fi)
    environment:
      - APP_ENV=${env}
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb-shared
ENVEOF
elif [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb
ENVEOF
fi)
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
      - REDIS_HOST=redis
ENVEOF
fi)
$(generate_volumes_section)
    networks:
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - database
ENVEOF
fi)
$(# Only add depends_on section if there are actual dependencies for queue worker
if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
    depends_on:
      - redis
ENVEOF
fi)

EOF
    fi

    # Add scheduler if selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " scheduler " ]]; then
        cat >> "$compose_file" << EOF
  scheduler:
    build:
      context: ./source  # Source code cloned by webhook dispatcher
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME}-scheduler-${suffix}
    restart: unless-stopped
    command: >
      sh -c "echo '* * * * * cd /var/www/html && php artisan schedule:run >> /proc/1/fd/1 2>/proc/1/fd/2' > /etc/cron.d/laravel-scheduler &&
             chmod 0644 /etc/cron.d/laravel-scheduler &&
             crontab /etc/cron.d/laravel-scheduler &&
             cron -f"
    working_dir: /var/www/html
    volumes:
      - ./source:/var/www/html
$(if [[ -n "${FRAMEWORK_VOLUMES:-}" ]]; then
IFS=',' read -ra volume_array <<< "$FRAMEWORK_VOLUMES"
for volume in "${volume_array[@]}"; do
  # Safely expand PROJECT_NAME and env variables only
  expanded_volume="${volume//\$\{PROJECT_NAME\}/$PROJECT_NAME}"
  expanded_volume="${expanded_volume//\$\{env\}/$env}"
  echo "      - $expanded_volume"
done
fi)
    env_file:
      - ../.env
      - .env
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - .env.database
ENVEOF
fi)
    environment:
      - APP_ENV=${env}
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb-shared
ENVEOF
elif [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - DB_HOST=mariadb
ENVEOF
fi)
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
      - REDIS_HOST=redis
ENVEOF
fi)
    networks:
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
      - database
ENVEOF
fi)
$(# Only add depends_on section if there are actual dependencies for scheduler
if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
    depends_on:
      - redis
ENVEOF
fi)

EOF
    fi

    # Add Redis if selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
        local redis_memory="256mb"
        local redis_persistence="--save 60 1000"
        
        # Different config for non-production
        if [[ "$env" != "production" ]]; then
            redis_memory="128mb"
            redis_persistence=""  # No persistence for staging/dev
        fi
        
        cat >> "$compose_file" << EOF
  redis:
    image: redis:7-alpine
    container_name: ${PROJECT_NAME}-redis-${suffix}
    restart: unless-stopped
    command: redis-server ${redis_persistence} --loglevel warning --maxmemory ${redis_memory} --maxmemory-policy allkeys-lru
$(if [[ "$env" == "production" ]]; then
cat << 'ENVEOF'
    volumes:
      - ${PROJECT_NAME}_${suffix}_redis_data:/data
ENVEOF
fi)
    networks:
      - database  # Always use database network for internal services
    labels:
      - "traefik.enable=false"

EOF
    fi

    # Add project-specific MariaDB if selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
        # Find available port for this project's database
        local db_port=$(find_available_port)
        log_info "Assigning port $db_port for $PROJECT_NAME database debugging"
        
        cat >> "$compose_file" << EOF
  mariadb:
    image: mariadb:10.11
    container_name: ${PROJECT_NAME}-mariadb-${suffix}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${db_port}:3306"  # Localhost-only access for debugging
    environment:
      MYSQL_ROOT_PASSWORD: \${DB_PASSWORD}
      MYSQL_DATABASE: \${DB_DATABASE}
      MYSQL_USER: \${DB_USERNAME}
      MYSQL_PASSWORD: \${DB_PASSWORD}
    volumes:
      - ${PROJECT_NAME}_${suffix}_mariadb_data:/var/lib/mysql
    networks:
      - database
    labels:
      - "traefik.enable=false"

EOF
    fi

    # Add networks section
    cat >> "$compose_file" << EOF
networks:
  web:
    external: true
    name: traefik_web
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
  database:
    external: true
    name: database_access
ENVEOF
fi)

EOF

    # Add volumes section if needed
    if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]] && [[ "$env" == "production" ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
        cat >> "$compose_file" << EOF
volumes:
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]] && [[ "$env" == "production" ]]; then
cat << 'ENVEOF'
  ${PROJECT_NAME}_${suffix}_redis_data:
ENVEOF
fi)
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
cat << 'ENVEOF'
  ${PROJECT_NAME}_${suffix}_mariadb_data:
ENVEOF
fi)
EOF
    fi
}

# Generate .env files
generate_env_files() {
    local env=$1
    local env_dir="$PROJECTS_DIR/$PROJECT_NAME/$env"
    
    log_info "Generating .env files for $env environment..."
    
    # Determine domain for environment
    local app_domain
    if [[ "$env" == "production" ]]; then
        app_domain="$PROJECT_DOMAIN"
    elif [[ "$env" == "staging" ]]; then
        app_domain="staging.$PROJECT_DOMAIN"
    elif [[ "$env" == "development" ]]; then
        app_domain="develop.$PROJECT_DOMAIN"
    else
        app_domain="$env.$PROJECT_DOMAIN"
    fi
    
    # Main .env file
    cat > "$env_dir/.env" << EOF
# ${PROJECT_NAME^} - $env environment
APP_NAME="${PROJECT_NAME^}"
APP_ENV=$env
APP_DEBUG=$(if [[ "$env" == "production" ]]; then echo "false"; else echo "true"; fi)
APP_DOMAIN=$app_domain

# Force HTTPS detection behind Traefik proxy
FORCE_HTTPS=true
ASSET_URL=https://\${APP_DOMAIN}

$(if [[ " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
cat << 'ENVEOF'
# Redis (Project-specific instance)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=null
REDIS_DB=0

# Cache & Sessions
CACHE_DRIVER=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

ENVEOF
fi)
$(if [[ " ${SELECTED_SERVICES[*]} " =~ " queue " ]]; then
cat << 'ENVEOF'
# Queue
QUEUE_CONNECTION=redis

ENVEOF
fi)
# Mail
MAIL_MAILER=smtp
MAIL_HOST=your-mail-server.com
MAIL_PORT=587
MAIL_USERNAME=your-email@$PROJECT_DOMAIN
MAIL_PASSWORD=your-email-password
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@$PROJECT_DOMAIN
MAIL_FROM_NAME="\${APP_NAME}"
EOF

    # Database .env file if database is selected
    if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
        cat > "$env_dir/.env.database" << EOF
# Database Configuration (Auto-generated by setup-database.sh)
# This file will be populated when the database is set up

DB_CONNECTION=mysql
DB_HOST=mariadb-shared
DB_PORT=3306
# DB_DATABASE will be auto-generated as: ${PROJECT_NAME}_${env}
# DB_USERNAME will be auto-generated as: ${PROJECT_NAME}_${env}
# DB_PASSWORD will be auto-generated
EOF
    elif [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
        cat > "$env_dir/.env.database" << EOF
# Project-Specific Database Configuration (Auto-generated)
# This database runs in its own container with debugging port access

DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=${PROJECT_NAME}_${env}
DB_USERNAME=${PROJECT_NAME}_${env}
DB_PASSWORD=$(openssl rand -base64 24)
EOF
    fi
}

# Create project structure
create_project_structure() {
    log_info "Creating project structure..."
    
    # Create base project directory
    if ! mkdir -p "$PROJECTS_DIR/$PROJECT_NAME"; then
        log_error "Failed to create project directory: $PROJECTS_DIR/$PROJECT_NAME"
        exit 1
    fi
    
    # Create volume directories with proper permissions
    log_info "Creating local storage directories...")
    for env in "${ENVIRONMENTS[@]}"; do
        local env_dir="$PROJECTS_DIR/$PROJECT_NAME/$env"
        
        # Create storage directory in the environment directory
        if ! mkdir -p "$env_dir/storage"; then
            log_error "Failed to create storage directory: $env_dir/storage"
            exit 1
        fi
        
        # Set proper permissions for Laravel storage directories
        chmod 755 "$env_dir/storage"
        
        # Ensure www-data can write (if running as different user)
        if [[ $(id -u) -eq 0 ]]; then
            chown -R 33:33 "$env_dir/storage" 2>/dev/null || true  # www-data UID/GID
        fi
    done
    
    # Create environment directories
    for env in "${ENVIRONMENTS[@]}"; do
        local env_dir="$PROJECTS_DIR/$PROJECT_NAME/$env"
        mkdir -p "$env_dir/logs"
        
        # Generate docker-compose and env files
        generate_docker_compose "$env"
        generate_env_files "$env"
    done
    
    # Create base .env file
    cat > "$PROJECTS_DIR/$PROJECT_NAME/.env" << EOF
# ${PROJECT_NAME^} - Base Configuration
# These values are shared across all environments

APP_NAME="${PROJECT_NAME^}"
APP_KEY=base64:$(openssl rand -base64 32)

# Timezone
APP_TIMEZONE=UTC

# Logging
LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug
EOF

    # Database configuration is now handled automatically via services selection
    
    # Create deployment hooks
    create_deployment_hooks
    
    log_success "Project structure created!"
}



# Create deployment hooks
create_deployment_hooks() {
    log_info "Creating deployment hooks..."
    
    # Pre-deploy hook
    cat > "$PROJECTS_DIR/$PROJECT_NAME/pre_deploy.sh" << 'EOF'
#!/bin/bash
set -e

echo "🔧 Pre-deploy: Preparing application"

# Add your pre-deployment tasks here
# Examples:
# - Clear caches
# - Stop services gracefully
# - Backup current state

echo "✅ Pre-deploy completed"
EOF

    # Post-deploy hook
    local post_deploy="$PROJECTS_DIR/$PROJECT_NAME/post_deploy.sh"
    
    cat > "$post_deploy" << EOF
#!/bin/bash
set -e

echo "🎯 Post-deploy: Setting up application for \$REPOSITORY_NAME (\$ENVIRONMENT)"

# Wait for containers to be ready
sleep 5

EOF

    # Create app-specific post-deploy script
    local post_deploy_app="$PROJECTS_DIR/$PROJECT_NAME/post_deploy.app.sh"
    
    cat > "$post_deploy_app" << 'EOF'
#!/bin/bash
set -e

echo "🎯 Post-deploy app tasks for $APP_NAME ($APP_ENV)"
EOF

    # Add framework-specific post-deploy tasks for the app container
    case $FRAMEWORK in
        laravel)
            cat >> "$post_deploy_app" << 'EOF'

# Laravel-specific tasks
echo "Running Laravel migrations..."
php artisan migrate --force

# Create storage link if needed
php artisan storage:link

if [[ "$APP_ENV" == "staging" || "$APP_ENV" == "development" ]]; then
    echo "Non-production environment: Seeding test data..."
    php artisan db:seed --class=TestDataSeeder || true
fi
EOF
            ;;
    esac

    cat >> "$post_deploy_app" << 'EOF'

echo "✅ App post-deploy tasks completed"
EOF

    # Update main post-deploy to use the app script
    cat >> "$post_deploy" << 'EOF'
# Execute app-specific tasks inside the container
echo "Running app-specific post-deploy tasks..."
docker compose cp post_deploy.app.sh app:/tmp/post_deploy.app.sh
docker compose exec -T app chmod +x /tmp/post_deploy.app.sh
docker compose exec -T app /tmp/post_deploy.app.sh
EOF

    chmod +x "$post_deploy_app"

    cat >> "$post_deploy" << 'EOF'

echo "✅ Post-deploy completed"
EOF

    # Make hooks executable
    chmod +x "$PROJECTS_DIR/$PROJECT_NAME/pre_deploy.sh"
    chmod +x "$PROJECTS_DIR/$PROJECT_NAME/post_deploy.sh"
}

# Validate project-specific database configuration
test_project_database() {
    local env=$1
    local env_dir="$PROJECTS_DIR/$PROJECT_NAME/$env"
    
    # Check if .env.database exists with valid configuration
    if [[ ! -f "$env_dir/.env.database" ]]; then
        log_error "Database configuration file missing: $env_dir/.env.database"
        return 1
    fi
    
    # Source the database configuration
    source "$env_dir/.env.database" 2>/dev/null || {
        log_error "Failed to load database configuration from .env.database"
        return 1
    }
    
    # Verify required variables are set
    if [[ -z "$DB_DATABASE" ]] || [[ -z "$DB_USERNAME" ]] || [[ -z "$DB_PASSWORD" ]]; then
        log_error "Missing database credentials in .env.database"
        return 1
    fi
    
    log_info "✅ Database configuration validated:"
    log_info "   Database: $DB_DATABASE"
    log_info "   Username: $DB_USERNAME" 
    log_info "   Password: [securely generated]"
    
    # Show the debugging port that will be available
    local compose_file="$env_dir/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        local debug_port=$(grep -o "127.0.0.1:[0-9]*:3306" "$compose_file" | cut -d: -f2)
        if [[ -n "$debug_port" ]]; then
            log_info "   Debug Port: localhost:$debug_port (when containers are running)"
        fi
    fi
    
    log_info "🔧 The MariaDB container will automatically:"
    log_info "   - Create the '$DB_DATABASE' database on first startup"
    log_info "   - Create the '$DB_USERNAME' user with full access to the database"
    log_info "   - Set up the password and root credentials"
    
    return 0
}

# Get environment suffix for container names
get_env_suffix() {
    local env=$1
    case $env in
        production) echo "prod" ;;
        staging) echo "staging" ;;
        development) echo "dev" ;;
        *) echo "$env" ;;
    esac
}

# Setup databases
setup_databases() {
    if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
        log_info "Setting up databases..."
        
        for env in "${ENVIRONMENTS[@]}"; do
            log_info "Setting up database for $env environment..."
            
            if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
                # Shared database - needs setup via setup-database.sh
                if "$SCRIPT_DIR/setup-database.sh" setup "$PROJECTS_DIR/$PROJECT_NAME" "$env"; then
                    log_success "Shared database setup completed for $env"
                else
                    log_warning "Shared database setup failed for $env (will retry on first deployment)"
                fi
            elif [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
                # Project-specific database - test the setup
                log_info "Testing project-specific database setup for $env..."
                
                if test_project_database "$env"; then
                    log_success "Project-specific database setup verified for $env"
                else
                    log_warning "Project-specific database test failed for $env (will be created on first startup)"
                fi
            fi
        done
    fi
}

# Show completion summary
show_completion_summary() {
    echo
    log_success "🎉 Project '$PROJECT_NAME' created successfully!"
    echo
    echo -e "${CYAN}📋 Project Summary:${NC}"
    echo "  Name: $PROJECT_NAME"
    echo "  Framework: $FRAMEWORK"
    echo "  Environments: ${ENVIRONMENTS[*]}"
    if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
        echo "  Services: ${SELECTED_SERVICES[*]}"
    fi
    echo
    echo -e "${CYAN}📁 Created Structure:${NC}"
    echo "  $PROJECTS_DIR/$PROJECT_NAME/"
    for env in "${ENVIRONMENTS[@]}"; do
        echo "  ├── $env/"
        echo "  │   ├── docker-compose.yml"
        echo "  │   ├── .env"
        if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]] || [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
            echo "  │   ├── .env.database"
        fi
        echo "  │   └── logs/"
    done
    echo "  ├── .env (base config)"
    echo "  ├── pre_deploy.sh"
    echo "  └── post_deploy.sh"

    echo
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "1. Domain configuration complete:"
    for env in "${ENVIRONMENTS[@]}"; do
        local env_domain
        if [[ "$env" == "production" ]]; then
            env_domain="$PROJECT_DOMAIN"
        elif [[ "$env" == "staging" ]]; then
            env_domain="staging.$PROJECT_DOMAIN"
        elif [[ "$env" == "development" ]]; then
            env_domain="develop.$PROJECT_DOMAIN"
        else
            env_domain="$env.$PROJECT_DOMAIN"
        fi
        echo "   - $env: $env_domain"
    done
    echo
    echo "2. Create your project source directory:"
    echo "   mkdir -p ../src/$PROJECT_NAME"
    echo
    echo "3. Copy appropriate Dockerfile from docker/examples/ to your project:"
    echo "   cp docker/examples/${FRAMEWORK}.Dockerfile ../src/$PROJECT_NAME/Dockerfile"
    echo
    echo "4. Add your application code to ../src/$PROJECT_NAME/"
    echo
    echo "5. Persistent data directories created:"
    for env in "${ENVIRONMENTS[@]}"; do
        if [[ -n "${FRAMEWORK_VOLUMES:-}" ]]; then
            echo "   - volumes/projects/$PROJECT_NAME/$env/ (framework-specific data)"
        fi
    done
    echo
    echo "6. Test your setup:"
    echo "   cd projects/$PROJECT_NAME/production"
    echo "   docker compose up -d"
    echo
    
    # Add database-specific instructions
    if [[ " ${SELECTED_SERVICES[*]} " =~ " database-own " ]]; then
        echo "7. Project-specific database info:"
        for env in "${ENVIRONMENTS[@]}"; do
            local compose_file="$PROJECTS_DIR/$PROJECT_NAME/$env/docker-compose.yml"
            if [[ -f "$compose_file" ]]; then
                local debug_port=$(grep -o "127.0.0.1:[0-9]*:3306" "$compose_file" | cut -d: -f2)
                if [[ -n "$debug_port" ]]; then
                    echo "   - $env database debug access: localhost:$debug_port"
                fi
            fi
        done
        echo "   - Database and user will be created automatically on first startup"
        echo "   - Credentials are in each environment's .env.database file"
        echo
        echo "8. Setup Git repository and webhook for automatic deployment"
    elif [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
        echo "7. Shared database setup:"
        echo "   - Database users created in shared MariaDB container"
        echo "   - Credentials are in each environment's .env.database file"
        echo "   - Debug access: localhost:3306 (infrastructure database)"
        echo
        echo "8. Setup Git repository and webhook for automatic deployment"
    else
        echo "7. Setup Git repository and webhook for automatic deployment"
    fi
    echo
    log_success "Happy coding! 🎉"
}

# Main execution
main() {
    show_banner
    
    # Check if we're in the right directory
    if [[ ! -f "$INFRASTRUCTURE_DIR/docker-compose.yml" ]]; then
        log_error "Please run this script from the infrastructure directory"
        exit 1
    fi
    
    # Interactive setup
    get_project_name
    get_environments
    get_domain
    get_framework_or_services
    
    # Create project
    create_project_structure
    
    # Setup services
    setup_databases
    
    # Show summary
    show_completion_summary
}

# CLI interface for non-interactive use
if [[ "${1:-}" == "quick" ]]; then
    # Load quick setups
    if ! load_quick_setups; then
        log_error "Failed to load quick setup configurations"
        exit 1
    fi
    
    FRAMEWORK="${2:-}"
    PROJECT_NAME="${3:-}"
    PROJECT_DOMAIN="${4:-}"
    
    if [[ -z "$FRAMEWORK" ]] || [[ -z "$PROJECT_NAME" ]] || [[ -z "$PROJECT_DOMAIN" ]]; then
        echo "Usage: $0 quick <framework> <project-name> <domain>"
        echo
        echo "Available frameworks:"
        
        # Show available presets from config
        presets=($(get_available_quick_setups))
        for preset in "${presets[@]}"; do
            if [[ -n "${QUICK_SETUPS[${preset}_description]}" ]]; then
                printf "  %-12s - %s\n" "$preset" "${QUICK_SETUPS[${preset}_description]}"
            fi
        done
        
        echo
        echo "Examples:"
        echo "  $0 quick laravel my-app myapp.com"
        echo "  $0 quick react my-site mysite.com"
        echo
        echo "For custom setup, run: $0"
        exit 1
    fi
    
    # Validate framework exists in config
    if [[ -z "${QUICK_SETUPS[${FRAMEWORK}_description]}" ]]; then
        log_error "Unknown framework: $FRAMEWORK"
        echo
        echo "Available frameworks: $(get_available_quick_setups)"
        exit 1
    fi
    
    # Load preset configuration
    services_str="${QUICK_SETUPS[${FRAMEWORK}_services]}"
    if [[ -n "$services_str" ]]; then
        IFS=',' read -ra SELECTED_SERVICES <<< "$services_str"
        
        # Handle database type selection for quick setup
        if [[ " ${SELECTED_SERVICES[*]} " =~ " database " ]]; then
            # Remove generic 'database' from array
            SELECTED_SERVICES=("${SELECTED_SERVICES[@]/database}")
            
            # For quick setup, default to shared database (most common)
            # Users can modify later if they need project-specific
            SELECTED_SERVICES+=("database")
            log_info "Quick setup: Using shared database (use interactive mode for project-specific database)"
        fi
    else
        SELECTED_SERVICES=()
    fi
    
    env_str="${QUICK_SETUPS[${FRAMEWORK}_environments]}"
    if [[ -n "$env_str" ]]; then
        IFS=',' read -ra ENVIRONMENTS <<< "$env_str"
    else
        ENVIRONMENTS=("production" "staging")
    fi
    
    # Load volumes configuration
    FRAMEWORK_VOLUMES="${QUICK_SETUPS[${FRAMEWORK}_volumes]:-}"
    
    create_project_structure
    setup_databases
    show_completion_summary
else
    # Interactive mode
    main "$@"
fi