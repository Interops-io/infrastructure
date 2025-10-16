#!/bin/bash

# Restic-based Backup System for Docker Infrastructure
# Supports infrastructure, project-specific, and selective backups
#
# Usage:
#   ./backup.sh                    # Backup everything
#   ./backup.sh infrastructure     # Backup only infrastructure
#   ./backup.sh project app1       # Backup only app1 project
#   ./backup.sh init               # Initialize restic repository
#   ./backup.sh list               # List available snapshots
#   ./backup.sh restore <snapshot> # Restore from snapshot

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_CONFIG="${INFRASTRUCTURE_DIR}/.backup-config"
TEMP_BACKUP_DIR="/tmp/infrastructure-backup-$$"

# Dry run mode
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Load backup configuration
load_config() {
    if [[ -f "$BACKUP_CONFIG" ]]; then
        source "$BACKUP_CONFIG"
    else
        log_error "Backup configuration not found. Run: $0 init"
        exit 1
    fi
    
    # Load infrastructure environment variables for database access
    if [[ -f "$INFRASTRUCTURE_DIR/.env" ]]; then
        source "$INFRASTRUCTURE_DIR/.env"
    else
        log_warning "Infrastructure .env file not found - some backups may fail"
    fi
    
    # Validate required variables
    if [[ -z "$RESTIC_REPOSITORY" || -z "$RESTIC_PASSWORD" ]]; then
        log_error "Invalid backup configuration. Run: $0 init"
        exit 1
    fi
    
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD
}

# Initialize restic repository
init_backup() {
    log_info "Initializing backup system..."
    
    # Check if restic is installed
    if ! command -v restic &> /dev/null; then
        log_info "Installing restic..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y restic
        elif command -v yum &> /dev/null; then
            sudo yum install -y restic
        else
            log_error "Please install restic manually: https://restic.net/"
            exit 1
        fi
    fi
    
    # Get backup repository location
    echo "Choose backup repository type:"
    echo "1) Local directory"
    echo "2) SFTP (remote server)"
    echo "3) S3 compatible"
    read -p "Enter choice (1-3): " repo_type
    
    case $repo_type in
        1)
            read -p "Enter local backup directory path: " local_path
            mkdir -p "$local_path"
            RESTIC_REPOSITORY="$local_path"
            ;;
        2)
            read -p "Enter SFTP details (user@host:/path): " sftp_path
            RESTIC_REPOSITORY="sftp:$sftp_path"
            ;;
        3)
            read -p "Enter S3 endpoint: " s3_endpoint
            read -p "Enter S3 bucket: " s3_bucket
            read -p "Enter AWS Access Key ID: " aws_access_key
            read -s -p "Enter AWS Secret Access Key: " aws_secret_key
            echo
            RESTIC_REPOSITORY="s3:$s3_endpoint/$s3_bucket"
            export AWS_ACCESS_KEY_ID="$aws_access_key"
            export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Generate secure password
    RESTIC_PASSWORD=$(openssl rand -base64 32)
    
    # Save configuration
    cat > "$BACKUP_CONFIG" << EOF
# Restic Backup Configuration
RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
RESTIC_PASSWORD="$RESTIC_PASSWORD"
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=12
EOF

    if [[ $repo_type -eq 3 ]]; then
        cat >> "$BACKUP_CONFIG" << EOF
AWS_ACCESS_KEY_ID="$aws_access_key"
AWS_SECRET_ACCESS_KEY="$aws_secret_key"
EOF
    fi

    chmod 600 "$BACKUP_CONFIG"
    
    # Initialize repository
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD
    
    log_info "Initializing restic repository..."
    if ! restic snapshots &> /dev/null; then
        restic init
        log_success "Restic repository initialized"
    else
        log_info "Repository already initialized"
    fi
    
    log_success "Backup system configured successfully!"
    log_warning "IMPORTANT: Save this password securely: $RESTIC_PASSWORD"
}

# Get database dumps
backup_databases() {
    local backup_dir="$1"
    local project="$2"
    
    log_info "Creating database dumps..."
    
    # Shared MariaDB backup
    if docker ps --format "table {{.Names}}" | grep -q "mariadb-shared"; then
        log_info "Backing up shared MariaDB..."
        docker exec mariadb-shared mysqldump -u root -p${MYSQL_ROOT_PASSWORD} --all-databases \
            > "$backup_dir/mariadb-shared-dump.sql" 2>/dev/null || \
            log_warning "Failed to backup shared MariaDB (check if running)"
    fi
    
    # Project-specific database backups
    if [[ -n "$project" ]]; then
        local project_dir="$INFRASTRUCTURE_DIR/projects/$project"
        if [[ -d "$project_dir" ]]; then
            # Find all .env.database files for this project
            for env_database_file in "$project_dir"/*/.env.database; do
                if [[ -f "$env_database_file" ]]; then
                    local env_dir=$(dirname "$env_database_file")
                    local env=$(basename "$env_dir")
                    
                    # Get database configuration from environment file
                    local db_host=$(grep "^DB_HOST=" "$env_database_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
                    local db_name=$(grep "^DB_DATABASE=" "$env_database_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "${project}_${env}")
                    local db_user=$(grep "^DB_USERNAME=" "$env_database_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "root")
                    local db_pass=$(grep "^DB_PASSWORD=" "$env_database_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
                    
                    if [[ -n "$db_name" && "$db_name" != "DB_DATABASE" && -n "$db_host" ]]; then
                        # Check if the database host container is running
                        if docker ps --format "table {{.Names}}" | grep -q "$db_host"; then
                            log_info "Backing up database: $db_host/$db_name"
                            docker exec "$db_host" mysqldump -u "$db_user" -p"$db_pass" "$db_name" \
                                > "$backup_dir/${project}-${env}-database.sql" 2>/dev/null || \
                                log_warning "Failed to backup database: $db_host/$db_name"
                        else
                            log_warning "Database container not found or not running: $db_host"
                        fi
                    fi
                fi
            done
        fi
    fi
}

# Backup project volumes and files
backup_project() {
    local project="$1"
    local backup_dir="$2"
    
    log_info "Backing up project: $project"
    
    local project_dir="$INFRASTRUCTURE_DIR/projects/$project"
    if [[ ! -d "$project_dir" ]]; then
        log_error "Project directory not found: $project_dir"
        return 1
    fi
    
    # Backup project configuration
    log_info "Backing up project configuration..."
    cp -r "$project_dir" "$backup_dir/projects/"
    
    # Backup project volumes
    for env_dir in "$project_dir"/{production,staging,development}; do
        if [[ -d "$env_dir" ]] && [[ -f "$env_dir/docker-compose.yml" ]]; then
            local env=$(basename "$env_dir")
            log_info "Backing up $project/$env volumes..."
            
            cd "$env_dir"
            
            # Get all volumes used by this project environment
            local volumes=$(docker-compose config --volumes 2>/dev/null || true)
            
            for volume in $volumes; do
                if docker volume ls | grep -q "$volume"; then
                    log_info "Backing up volume: $volume"
                    docker run --rm \
                        -v "$volume:/volume:ro" \
                        -v "$backup_dir:/backup" \
                        alpine tar czf "/backup/volume-${project}-${env}-${volume}.tar.gz" -C /volume . \
                        2>/dev/null || log_warning "Failed to backup volume: $volume"
                fi
            done
            
            # Backup host-mounted storage directories (Laravel storage, logs, etc.)
            local storage_dir="$INFRASTRUCTURE_DIR/volumes/projects/$project/$env"
            if [[ -d "$storage_dir" ]]; then
                log_info "Backing up host storage: $storage_dir"
                tar czf "$backup_dir/host-storage-${project}-${env}.tar.gz" -C "$storage_dir" . \
                    2>/dev/null || log_warning "Failed to backup host storage: $storage_dir"
            fi
        fi
    done
    
    # Backup databases for this project
    backup_databases "$backup_dir" "$project"
}

# Backup infrastructure components
backup_infrastructure() {
    local backup_dir="$1"
    
    log_info "Backing up infrastructure components..."
    
    # Configuration files
    log_info "Backing up configuration files..."
    cd "$INFRASTRUCTURE_DIR"
    cp -r traefik/ scripts/ monitoring/ config/ "$backup_dir/" 2>/dev/null || true
    cp hooks.json "$backup_dir/" 2>/dev/null || true
    cp docker-compose.yml .env* "$backup_dir/" 2>/dev/null || true
    
    # Backup volumes directory (contains project storage, database init files, etc.)
    if [[ -d "$INFRASTRUCTURE_DIR/volumes" ]]; then
        log_info "Backing up volumes directory..."
        tar czf "$backup_dir/volumes-backup.tar.gz" -C "$INFRASTRUCTURE_DIR" volumes/ \
            2>/dev/null || log_warning "Failed to backup volumes directory"
    fi
    
    # Infrastructure volumes
    log_info "Backing up infrastructure volumes..."
    
    # Get all volumes used by the main docker-compose
    cd "$INFRASTRUCTURE_DIR"
    local compose_volumes=$(docker-compose config --volumes 2>/dev/null || true)
    
    for volume in $compose_volumes; do
        if docker volume ls | grep -q "$volume"; then
            log_info "Backing up infrastructure volume: $volume"
            docker run --rm \
                -v "$volume:/volume:ro" \
                -v "$backup_dir:/backup" \
                alpine tar czf "/backup/volume-infrastructure-${volume}.tar.gz" -C /volume . \
                2>/dev/null || log_warning "Failed to backup volume: $volume"
        fi
    done
    
    # Infrastructure databases
    backup_databases "$backup_dir"
}

# Perform backup
perform_backup() {
    local backup_type="$1"
    local project_name="$2"
    
    load_config
    
    # Clean and create temp directory
    rm -rf "$TEMP_BACKUP_DIR"
    mkdir -p "$TEMP_BACKUP_DIR/projects"
    
    local tag_suffix=""
    
    case $backup_type in
        "infrastructure")
            backup_infrastructure "$TEMP_BACKUP_DIR"
            tag_suffix="-infrastructure"
            ;;
        "project")
            if [[ -z "$project_name" ]]; then
                log_error "Project name required for project backup"
                exit 1
            fi
            backup_project "$project_name" "$TEMP_BACKUP_DIR"
            tag_suffix="-project-$project_name"
            ;;
        "full"|"")
            backup_infrastructure "$TEMP_BACKUP_DIR"
            # Backup all projects
            for project_dir in "$INFRASTRUCTURE_DIR/projects"/*; do
                if [[ -d "$project_dir" ]]; then
                    local project=$(basename "$project_dir")
                    backup_project "$project" "$TEMP_BACKUP_DIR"
                fi
            done
            tag_suffix="-full"
            ;;
        *)
            log_error "Invalid backup type: $backup_type"
            exit 1
            ;;
    esac
    
    # Create snapshot with restic
    log_info "Creating restic snapshot..."
    local hostname=$(hostname)
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    restic backup "$TEMP_BACKUP_DIR" \
        --tag "infrastructure$tag_suffix" \
        --tag "host:$hostname" \
        --tag "date:$timestamp"
    
    # Cleanup temp directory
    rm -rf "$TEMP_BACKUP_DIR"
    
    # Prune old snapshots
    log_info "Pruning old snapshots..."
    restic forget \
        --keep-daily "$BACKUP_RETENTION_DAILY" \
        --keep-weekly "$BACKUP_RETENTION_WEEKLY" \
        --keep-monthly "$BACKUP_RETENTION_MONTHLY" \
        --prune
    
    log_success "Backup completed successfully!"
}

# List snapshots
list_snapshots() {
    load_config
    restic snapshots
}

# Restore from snapshot
restore_snapshot() {
    local snapshot_id="$1"
    local restore_path="${2:-/tmp/restore-$(date +%s)}"
    
    if [[ -z "$snapshot_id" ]]; then
        log_error "Snapshot ID required"
        echo "Available snapshots:"
        list_snapshots
        exit 1
    fi
    
    load_config
    
    log_info "Restoring snapshot $snapshot_id to $restore_path..."
    mkdir -p "$restore_path"
    
    restic restore "$snapshot_id" --target "$restore_path"
    
    log_success "Restored to: $restore_path"
    log_info "Review the files and manually restore as needed"
}

# Show usage
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init                     Initialize backup system"
    echo "  full                     Backup everything (default)"
    echo "  infrastructure           Backup only infrastructure"
    echo "  project <name>          Backup specific project"
    echo "  list                     List available snapshots"
    echo "  restore <snapshot> [path] Restore snapshot to path"
    echo "  --dry-run               Test configuration without backup"
    echo ""
    echo "Examples:"
    echo "  $0 init                  # Initialize backup"
    echo "  $0                       # Full backup"
    echo "  $0 project my-app        # Backup only my-app"
    echo "  $0 list                  # Show snapshots"
    echo "  $0 restore abc123        # Restore snapshot abc123"
}

# Main execution
case "${1:-full}" in
    "init")
        init_backup
        ;;
    "full"|"")
        perform_backup "full"
        ;;
    "infrastructure")
        perform_backup "infrastructure"
        ;;
    "project")
        perform_backup "project" "$2"
        ;;
    "list")
        list_snapshots
        ;;
    "restore")
        restore_snapshot "$2" "$3"
        ;;
    "--dry-run"|"dry-run")
        DRY_RUN=true
        log_info "🧪 Dry run mode - testing configuration..."
        
        # Test configuration loading
        load_config
        if [[ -z "$RESTIC_REPOSITORY" ]]; then
            log_error "❌ Backup not configured. Run: $0 init"
            exit 1
        fi
        
        log_success "✅ Configuration loaded"
        log_info "Repository: $RESTIC_REPOSITORY"
        
        # Test restic connection
        if ! command -v restic >/dev/null 2>&1; then
            log_error "❌ Restic not installed"
            exit 1
        fi
        
        # Test repository access (but don't create backup)
        if restic --repo "$RESTIC_REPOSITORY" snapshots --latest 1 >/dev/null 2>&1; then
            log_success "✅ Repository access successful"
        else
            log_warning "⚠️  Repository access failed - may need initialization"
        fi
        
        # Test Docker access
        if ! docker version >/dev/null 2>&1; then
            log_error "❌ Docker access failed"
            exit 1
        fi
        
        log_success "✅ Docker access successful"
        
        # Check backup directories
        if [[ -d "$INFRASTRUCTURE_DIR" ]]; then
            log_success "✅ Infrastructure directory found: $INFRASTRUCTURE_DIR"
        else
            log_error "❌ Infrastructure directory not found: $INFRASTRUCTURE_DIR"
            exit 1
        fi
        
        log_success "✅ Dry run completed successfully - backup system is ready"
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac