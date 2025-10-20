#!/bin/bash

# Database Management Script
# Automatically creates databases and users based on project configuration

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[DB-SETUP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DB-SETUP]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[DB-SETUP]${NC} $1"
}

log_error() {
    echo -e "${RED}[DB-SETUP]${NC} $1"
}

# Generate secure random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Create database and user with direct MySQL commands
create_database_init_script() {
    local db_name=$1
    local username=$2
    local password=$3
    
    log_info "Creating database and user for ${username}..."
    
    # Create database and user with direct MySQL commands
    docker exec mariadb-shared mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
    CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
    CREATE USER IF NOT EXISTS '${username}'@'10.%.%.%' IDENTIFIED BY '${password}';
    ALTER USER '${username}'@'10.%.%.%' IDENTIFIED BY '${password}';
    GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${username}'@'10.%.%.%';
        FLUSH PRIVILEGES;
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Database and user created successfully"
        return 0
    else
        log_error "Failed to create database and user"
        return 1
    fi
}

# Check if database service is running
check_db_service() {
    local service=$1
    if ! docker ps --filter "name=$service" --filter "status=running" --format "{{.Names}}" | grep -q "^$service$"; then
        log_error "Database service '$service' is not running"
        if [[ "$service" == "mariadb-shared" ]]; then
            log_info "Start infrastructure first: docker-compose up -d"
        else
            log_info "Start project first: cd to project directory and run docker-compose up -d"
        fi
        exit 1
    fi
    log_success "Database service '$service' is running"
}

# Detect database configuration from project
detect_database_config() {
    local env_dir=$1
    local app_name=$2
    local environment=$3
    
    # Check if project uses its own database container
    local compose_file="$env_dir/docker-compose.yml"
    local env_database_file="$env_dir/.env.database"
    
    if [[ ! -f "$compose_file" ]] || [[ ! -f "$env_database_file" ]]; then
        echo "shared mariadb-shared"
        return
    fi
    
    # Check if docker-compose.yml defines its own mariadb service
    if grep -q "^[[:space:]]*mariadb:" "$compose_file"; then
        # Project-specific database - determine container name
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
        # Uses shared database
        echo "shared mariadb-shared"
    fi
}

# Create isolated MariaDB user and database
create_mariadb_user() {
    local app_name=$1
    local environment=$2
    local container_name=$3
    local db_type=$4  # "shared" or "own"
    local env_dir=$5   # Added to pass environment directory
    
    local db_name="${app_name}_${environment}"
    local username="${app_name}_${environment}"
    
    # For shared database, use password from .env.database. For project-specific, use existing password
    local password
    if [[ "$db_type" == "shared" ]]; then
        # Read the password from .env.database file that was generated during project creation
        if [[ -f "$env_dir/.env.database" ]]; then
            source "$env_dir/.env.database" 2>/dev/null || true
            password="$DB_PASSWORD"
        fi
        
        # Fallback to generating new password if not found in .env.database
        if [[ -z "$password" ]]; then
            log_warning "No password found in .env.database, generating new one"
            password=$(generate_password)
            
            # Update .env.database with the generated password if the file exists
            if [[ -f "$env_dir/.env.database" ]]; then
                log_info "Updating .env.database with generated password"
                # Use sed to replace or add the DB_PASSWORD line
                if grep -q "^DB_PASSWORD=" "$env_dir/.env.database"; then
                    sed -i.bak "s/^DB_PASSWORD=.*/DB_PASSWORD=$password/" "$env_dir/.env.database"
                else
                    echo "DB_PASSWORD=$password" >> "$env_dir/.env.database"
                fi
            fi
        fi
    else
        # For project-specific database, use the password that was generated during project creation
        # This matches what's configured in docker-compose.yml environment variables
        password="$MYSQL_ROOT_PASSWORD"  # This was loaded from DB_PASSWORD in .env.database
    fi
    
    log_info "Creating MariaDB database and user for $app_name ($environment) in container: $container_name"
    
    if [[ "$db_type" == "shared" ]]; then
        # Shared database - create isolated user with limited privileges using secure init script
        create_database_init_script "$db_name" "$username" "$password"
    else
        # Project-specific database - database and user already configured via docker-compose environment
        # Just verify the database is accessible
        docker exec "$container_name" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Database setup completed for $app_name ($environment)"
        
        if [[ "$db_type" == "shared" ]]; then
            # Return credentials for shared database
            echo "DB_DATABASE=$db_name"
            echo "DB_USERNAME=$username"
            echo "DB_PASSWORD=$password"
        else
            # For project-specific database, credentials are already in docker-compose.yml environment
            log_info "Project-specific database credentials are configured via docker-compose.yml"
            return 0
        fi
    else
        log_error "Failed to setup MariaDB database"
        exit 1
    fi
}


# Check if database/user already exists
check_mariadb_exists() {
    local db_name=$1
    local username=$2
    local container_name=$3
    local db_type=$4
    
    if [[ "$db_type" == "own" ]]; then
        # For project-specific database, just check if container responds
        docker exec "$container_name" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;" > /dev/null 2>&1
        return $?
    else
        # Check if database exists
        local db_exists=$(docker exec "$container_name" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES LIKE '${db_name}';" 2>/dev/null | grep -c "${db_name}" || echo "0")
        
        # Check if user exists
        local user_exists=$(docker exec "$container_name" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "${username}" || echo "0")
        
        if [ "$db_exists" -gt 0 ] && [ "$user_exists" -gt 0 ]; then
            return 0  # Both exist
        else
            return 1  # At least one doesn't exist
        fi
    fi
}



# Update .env.database file with database credentials
update_env_database_file() {
    local env_dir=$1
    local credentials=$2
    local config_type=$3
    local env_database_file="$env_dir/.env.database"
    
    if [ ! -f "$env_database_file" ]; then
        log_warning "Environment database file $env_database_file doesn't exist, creating it"
        touch "$env_database_file"
    fi
    
    # Backup existing .env.database
    cp "$env_database_file" "${env_database_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Create new .env.database file with credentials
    if [[ "$config_type" == "shared" ]]; then
        cat > "$env_database_file" << EOF
# Database Configuration (Auto-generated on $(date))
# Shared infrastructure database credentials

DB_CONNECTION=mysql
DB_HOST=mariadb-shared
DB_PORT=3306
$credentials
EOF
    else
        cat > "$env_database_file" << EOF
# Database Configuration (Auto-generated on $(date))
# Project-specific database credentials

DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
# Database and user credentials are configured via docker-compose.yml environment variables
# DB_DATABASE, DB_USERNAME, and DB_PASSWORD are set in the container environment
EOF
    fi
    
    log_success "Updated $env_database_file with database credentials"
}

# Main function to setup database for a project
setup_project_database() {
    local project_path=$1
    local environment=${2:-"production"}
    
    if [ ! -d "$project_path" ]; then
        log_error "Project path $project_path does not exist"
        exit 1
    fi
    
    # Extract app name from path
    local app_name=$(basename "$project_path")
    local env_dir="$project_path/$environment"
    
    log_info "Setting up database for $app_name ($environment environment)"
    
    # Check if environment directory exists
    if [ ! -d "$env_dir" ]; then
        log_error "Environment directory $env_dir does not exist"
        return 1
    fi
    
    # Check if project needs database (look for .env.database file in environment)
    if [ ! -f "$env_dir/.env.database" ]; then
        log_info "No database configuration needed for $app_name ($environment)"
        return 0
    fi
    
    # Default to MySQL/MariaDB (could be made configurable later if needed)
    local db_type="mariadb"
    
    case $db_type in
        "mysql"|"mariadb")
            # Detect database configuration (shared vs own)
            local db_config=$(detect_database_config "$env_dir" "$app_name" "$environment")
            local config_type=$(echo "$db_config" | cut -d' ' -f1)  # "shared" or "own"
            local container_name=$(echo "$db_config" | cut -d' ' -f2)  # container name
            
            log_info "Detected database configuration: $config_type database using container '$container_name'"
            
            check_db_service "$container_name"
            
            # Load root password from infrastructure .env or project .env.database
            if [[ "$config_type" == "own" ]]; then
                # For project-specific database, try to get password from .env.database
                if [[ -f "$env_dir/.env.database" ]]; then
                    source "$env_dir/.env.database" 2>/dev/null || true
                    MYSQL_ROOT_PASSWORD="$DB_PASSWORD"  # Use DB_PASSWORD as root password for project DB
                fi
            else
                # For shared database, use infrastructure .env
                source "$INFRASTRUCTURE_DIR/.env" 2>/dev/null || true
            fi
            
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                log_error "MYSQL_ROOT_PASSWORD not found. For shared DB: check infrastructure .env. For project DB: check $env_dir/.env.database"
                return 1
            fi
            
            local db_name="${app_name}_${environment}"
            local username="${app_name}_${environment}"
            
            if check_mariadb_exists "$db_name" "$username" "$container_name" "$config_type"; then
                log_info "Database setup is already complete for $app_name ($environment)"
                if [[ "$config_type" == "shared" ]] && [[ ! -f "$env_dir/.env.database" ]]; then
                    log_warning "Database exists but .env.database is missing. You may need to recreate the user to get the password."
                fi
            else
                if [[ "$config_type" == "shared" ]]; then
                    local credentials=$(create_mariadb_user "$app_name" "$environment" "$container_name" "$config_type" "$env_dir")
                    update_env_database_file "$env_dir" "$credentials" "$config_type"
                else
                    # For project-specific database, just verify setup
                    create_mariadb_user "$app_name" "$environment" "$container_name" "$config_type" "$env_dir"
                fi
            fi
            ;;
            
        *)
            log_error "Unsupported database type: $db_type"
            log_info "Supported types: mysql, mariadb"
            exit 1
            ;;
    esac
}

# CLI interface
main() {
    case "${1:-}" in
        "setup")
            if [ -z "${2:-}" ]; then
                log_error "Usage: $0 setup <project-path> [environment]"
                exit 1
            fi
            setup_project_database "$2" "${3:-production}"
            ;;
        "setup-all")
            local projects_dir="${2:-./projects}"
            local environment="${3:-production}"
            
            log_info "Setting up databases for all projects in $projects_dir"
            
            for project_dir in "$projects_dir"/*; do
                if [ -d "$project_dir" ] && [ -f "$project_dir/$environment/.env.database" ]; then
                    setup_project_database "$project_dir" "$environment"
                fi
            done
            ;;
        "help"|"--help"|"-h"|"")
            echo "Database Management Script"
            echo ""
            echo "Usage:"
            echo "  $0 setup <project-path> [environment]     Setup database for specific project"
            echo "  $0 setup-all [projects-dir] [environment] Setup databases for all projects"
            echo ""
            echo "Examples:"
            echo "  $0 setup ./projects/myapp production"
            echo "  $0 setup ./projects/myapp staging"
            echo "  $0 setup-all ./projects staging"
            echo ""
            echo "Requirements:"
            echo "  - Project must have .env.database file (created by create-project.sh)"
            echo "  - For shared database: MariaDB service must be running (docker-compose up -d)"
            echo "  - For shared database: Infrastructure .env file must contain MYSQL_ROOT_PASSWORD"
            echo "  - For project-specific database: Project containers must be running"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"