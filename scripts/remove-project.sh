#!/bin/bash

# Remove Project Script
# Safely removes a project: stops containers, backs up, deletes DB user (if shared), deletes volumes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[REMOVE-PROJECT]${NC} $1"
}
log_success() {
    echo -e "${GREEN}[REMOVE-PROJECT]${NC} $1"
}
log_warning() {
    echo -e "${YELLOW}[REMOVE-PROJECT]${NC} $1"
}
log_error() {
    echo -e "${RED}[REMOVE-PROJECT]${NC} $1"
}

usage() {
    echo "Usage: $0 <project-path> [environment]"
    echo "Example: $0 ./projects/myapp production"
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

PROJECT_PATH="$1"
ENVIRONMENT="${2:-production}"
APP_NAME="$(basename "$PROJECT_PATH")"
ENV_DIR="$PROJECT_PATH/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
    log_error "Environment directory $ENV_DIR does not exist"
    exit 1
fi

log_info "Stopping containers for $APP_NAME ($ENVIRONMENT)"
if [ -f "$ENV_DIR/docker-compose.yml" ]; then
    (cd "$ENV_DIR" && docker compose down)
else
    log_warning "No docker-compose.yml found in $ENV_DIR, skipping container stop"
fi

log_info "Running backup for $APP_NAME ($ENVIRONMENT)"
"$SCRIPT_DIR/backup.sh" "$PROJECT_PATH" "$ENVIRONMENT"

# Detect database config (shared or own)
detect_database_config() {
    local env_dir=$1
    local app_name=$2
    local environment=$3
    local compose_file="$env_dir/docker-compose.yml"
    local env_database_file="$env_dir/.env.database"
    if [[ ! -f "$compose_file" ]] || [[ ! -f "$env_database_file" ]]; then
        echo "shared mariadb-shared"
        return
    fi
    if grep -q "^[[:space:]]*mariadb:" "$compose_file"; then
        local suffix=""
        case $environment in
            production) suffix="prod" ;;
            staging) suffix="staging" ;;
            development) suffix="dev" ;;
            *) suffix="$environment" ;;
        esac
        local container_name="${app_name}-mariadb-${suffix}"
        echo "own $container_name"
    else
        echo "shared mariadb-shared"
    fi
}

DB_CONFIG=$(detect_database_config "$ENV_DIR" "$APP_NAME" "$ENVIRONMENT")
CONFIG_TYPE=$(echo "$DB_CONFIG" | cut -d' ' -f1)
CONTAINER_NAME=$(echo "$DB_CONFIG" | cut -d' ' -f2)

# Delete DB user if shared
delete_db_user() {
    local app_name=$1
    local environment=$2
    local container_name=$3
    local username="${app_name}_${environment}"
    source "$INFRASTRUCTURE_DIR/.env" 2>/dev/null || true
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        log_error "MYSQL_ROOT_PASSWORD not found in infrastructure .env"
        return 1
    fi
    log_info "Deleting DB user $username from shared database ($container_name)"
    docker exec "$container_name" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '${username}'@'172.%.%.%'; DROP USER IF EXISTS '${username}'@'192.168.%.%'; DROP USER IF EXISTS '${username}'@'10.%.%.%'; FLUSH PRIVILEGES;" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_success "DB user $username deleted from shared database"
    else
        log_warning "Failed to delete DB user $username (may not exist)"
    fi
}

if [ "$CONFIG_TYPE" = "shared" ]; then
    delete_db_user "$APP_NAME" "$ENVIRONMENT" "$CONTAINER_NAME"
else
    log_info "Project uses its own database container ($CONTAINER_NAME), skipping DB user deletion"
fi

log_info "Deleting volumes for $APP_NAME ($ENVIRONMENT)"
if [ -f "$ENV_DIR/docker-compose.yml" ]; then
    (cd "$ENV_DIR" && docker compose down -v)
else
    log_warning "No docker-compose.yml found in $ENV_DIR, skipping volume deletion"
fi

log_success "Project $APP_NAME ($ENVIRONMENT) removal complete."
