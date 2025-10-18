#!/bin/bash

# Infrastructure Installation Script
# Automates the setup process for Docker infrastructure hosting
# 
# Usage: curl -fsSL https://raw.githubusercontent.com/yourusername/infrastructure/main/install.sh | bash
# Or: ./install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INFRASTRUCTURE_USER="infrastructure"
INFRASTRUCTURE_HOME="/home/${INFRASTRUCTURE_USER}"
REPO_URL="git@github.com:Interops-io/infrastructure.git"  # Update this!
INSTALL_DIR="${INFRASTRUCTURE_HOME}/infrastructure"

# Detect if we're running from within the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNING_FROM_REPO=false

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check for infrastructure repository markers
if [[ -f "$SCRIPT_DIR/docker-compose.yml" && -f "$SCRIPT_DIR/.env.example" && -d "$SCRIPT_DIR/scripts" ]]; then
    RUNNING_FROM_REPO=true
    INSTALL_DIR="$SCRIPT_DIR"  # Use current directory when running from repo
    info "📁 Detected running from existing repository: $SCRIPT_DIR"
    info "🔄 Will transfer ownership to infrastructure user for proper security"
fi

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Check OS compatibility
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS. This script supports Ubuntu 20.04+ and Debian 11+"
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        error "Unsupported OS: $ID. This script supports Ubuntu and Debian only."
    fi
    
    if [[ "$ID" == "ubuntu" && $(echo "$VERSION_ID < 20.04" | bc -l) -eq 1 ]]; then
        error "Ubuntu version $VERSION_ID is not supported. Please use Ubuntu 20.04 or later."
    fi
    
    if [[ "$ID" == "debian" && $(echo "$VERSION_ID < 11" | bc -l) -eq 1 ]]; then
        error "Debian version $VERSION_ID is not supported. Please use Debian 11 or later."
    fi
    
    log "✅ OS Check passed: $PRETTY_NAME"
}

# Check system requirements
check_requirements() {
    log "🔍 Checking system requirements..."
    
    # Check available memory (minimum 1GB)
    MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEM_GB -lt 1 ]]; then
        warning "System has ${MEM_GB}GB RAM. Minimum 1GB required for infrastructure."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log "✅ Memory check passed: ${MEM_GB}GB RAM"
        if [[ $MEM_GB -lt 2 ]]; then
            warning "Consider upgrading to 2GB+ RAM when adding applications"
        fi
    fi
    
    # Check available disk space (minimum 20GB)
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $DISK_GB -lt 20 ]]; then
        warning "Available disk space: ${DISK_GB}GB. Minimum 20GB required for infrastructure."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log "✅ Disk space check passed: ${DISK_GB}GB available"
        if [[ $DISK_GB -lt 50 ]]; then
            warning "Consider having 50GB+ total when adding applications and databases"
        fi
    fi
}

# Update system packages
update_system() {
    log "📦 Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git bc apache2-utils restic
    
    log "✅ System packages updated and backup tools installed"
}

# Create infrastructure user
create_user() {
    if id "$INFRASTRUCTURE_USER" &>/dev/null; then
        log "✅ User '$INFRASTRUCTURE_USER' already exists"
    else
        log "👤 Creating infrastructure user: $INFRASTRUCTURE_USER"
        sudo useradd -m -s /bin/bash "$INFRASTRUCTURE_USER"
        sudo usermod -aG sudo "$INFRASTRUCTURE_USER"
        log "✅ User '$INFRASTRUCTURE_USER' created"
    fi
    
    # Note: Infrastructure user should NOT have passwordless sudo for security
    # All required packages and permissions are set up during installation
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log "✅ Docker already installed: $(docker --version)"
    else
        log "🐳 Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        # Add both current user and infrastructure user to docker group
        sudo usermod -aG docker "$USER"
        sudo usermod -aG docker "$INFRASTRUCTURE_USER"
        
        log "✅ Docker installed successfully"
    fi
}

# Install Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log "✅ Docker Compose already installed: $(docker-compose --version)"
    else
        log "🔧 Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Verify installation
        if docker-compose --version &> /dev/null; then
            log "✅ Docker Compose installed successfully"
        else
            error "Failed to install Docker Compose"
        fi
    fi
}

# Setup SSH keys for Git access
setup_ssh_keys() {
    log "🔑 Setting up SSH keys for Git access..."
    
    SSH_DIR="${INFRASTRUCTURE_HOME}/.ssh"
    SSH_KEY="${SSH_DIR}/id_ed25519_git"
    
    # Create .ssh directory if it doesn't exist
    sudo mkdir -p "$SSH_DIR"
    sudo chown "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$SSH_DIR"
    sudo chmod 700 "$SSH_DIR"
    
    # Generate SSH key if it doesn't exist
    if [[ ! -f "$SSH_KEY" ]]; then
        log "Generating SSH key for Git access..."
        sudo -u "$INFRASTRUCTURE_USER" ssh-keygen -t ed25519 -C "infrastructure@$(hostname)" -f "$SSH_KEY" -N ""
    fi
    
    # Create SSH config
    SSH_CONFIG="${SSH_DIR}/config"
    sudo -u "$INFRASTRUCTURE_USER" tee "$SSH_CONFIG" > /dev/null << 'EOF'
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

Host bitbucket.org
    HostName bitbucket.org
    User git
    IdentityFile ~/.ssh/id_ed25519_git
    AddKeysToAgent yes
EOF
    
    sudo chmod 600 "$SSH_CONFIG"
    sudo chown "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$SSH_CONFIG"
    
    log "✅ SSH keys configured"
    info "📋 Public key (add this to your Git provider):"
    echo "----------------------------------------"
    sudo cat "${SSH_KEY}.pub"
    echo "----------------------------------------"
}

# Clone or copy infrastructure repository
setup_repository() {
    log "📥 Setting up infrastructure repository..."
    
    if [[ "$RUNNING_FROM_REPO" == true ]]; then
        # We're running from within the repo, transfer ownership to infrastructure user
        if [[ "$SCRIPT_DIR" == "$INSTALL_DIR" ]]; then
            log "✅ Already running from target directory: $INSTALL_DIR"
            log "🔄 Transferring ownership to infrastructure user..."
            sudo chown -R "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$INSTALL_DIR"
        else
            log "📋 Copying repository from $SCRIPT_DIR to $INSTALL_DIR..."
            sudo mkdir -p "$(dirname "$INSTALL_DIR")"
            
            if [[ -d "$INSTALL_DIR" ]]; then
                log "📁 Target directory exists, backing up..."
                sudo mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            fi
            
            # Copy the repository
            sudo cp -r "$SCRIPT_DIR" "$INSTALL_DIR"
            
            # Set correct ownership
            sudo chown -R "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$INSTALL_DIR"
        fi
    else
        # Traditional clone from remote repository
        if [[ -d "$INSTALL_DIR" ]]; then
            log "📁 Infrastructure directory exists, updating..."
            cd "$INSTALL_DIR"
            sudo -u "$INFRASTRUCTURE_USER" git pull origin main
        else
            log "📥 Cloning infrastructure repository from $REPO_URL..."
            sudo -u "$INFRASTRUCTURE_USER" git clone "$REPO_URL" "$INSTALL_DIR"
        fi
        
        # Set correct ownership
        sudo chown -R "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$INSTALL_DIR"
    fi
    
    # Make scripts executable
    sudo chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
    sudo chmod +x "$INSTALL_DIR"/test-deployment.sh 2>/dev/null || true
    sudo chmod +x "$INSTALL_DIR"/install.sh 2>/dev/null || true
    
    log "✅ Repository setup complete at $INSTALL_DIR"
}

# Get domain configuration from user
get_domain_configuration() {
    log "🌐 Domain Configuration"
    echo
    
    # Get domain from user
    while true; do
        read -p "Enter your domain name (e.g., example.com): " USER_DOMAIN
        
        # Basic domain validation
        if [[ "$USER_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            break
        else
            error "Invalid domain format. Please use format like: example.com"
        fi
    done
    
    # Confirm with user
    echo
    info "Your infrastructure will be available at:"
    echo "  - Status Dashboard: https://status.$USER_DOMAIN"
    echo "  - Traefik Dashboard: https://traefik.$USER_DOMAIN"
    echo "  - Webhook Endpoint: https://webhook.$USER_DOMAIN"
    echo
    
    read -p "Is this correct? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Domain configuration cancelled. Please run the script again."
        exit 0
    fi
    
    # Export domain for use in other functions
    export CONFIGURED_DOMAIN="$USER_DOMAIN"
}

# Setup environment configuration
setup_environment() {
    log "⚙️ Setting up environment configuration..."
    
    ENV_FILE="${INSTALL_DIR}/.env"
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log "Creating .env file from template..."
        
        # Check if .env.example exists
        if [[ ! -f "${INSTALL_DIR}/.env.example" ]]; then
            error "Missing .env.example template file. Repository may not have cloned properly."
        fi
        
        # Always use infrastructure user for proper ownership
        sudo -u "$INFRASTRUCTURE_USER" cp "${INSTALL_DIR}/.env.example" "$ENV_FILE"
        
        # Generate secure passwords
        MYSQL_ROOT_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        GRAFANA_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        TRAEFIK_ADMIN_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
        
        # Generate Traefik authentication hash
        log "Generating Traefik admin authentication..."
        TRAEFIK_AUTH_HASH=$(htpasswd -nbB admin "$TRAEFIK_ADMIN_PASS" | tr -d '\n')
        
        # Verify hash was generated successfully
        if [[ -z "$TRAEFIK_AUTH_HASH" || ! "$TRAEFIK_AUTH_HASH" =~ ^admin: ]]; then
            error "Failed to generate Traefik authentication hash. Check if apache2-utils is properly installed."
        fi
        
        # Store passwords for display later
        export GENERATED_MYSQL_ROOT_PASS="$MYSQL_ROOT_PASS"
        export GENERATED_GRAFANA_PASS="$GRAFANA_PASS"
        export GENERATED_TRAEFIK_PASS="$TRAEFIK_ADMIN_PASS"
        
        # Replace default values in .env file using infrastructure user
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your_secure_root_password_here_min_16_chars/$MYSQL_ROOT_PASS/g" "$ENV_FILE"
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your_secure_grafana_password_here_min_16_chars/$GRAFANA_PASS/g" "$ENV_FILE"
        # Escape special characters in auth hash for sed
        ESCAPED_TRAEFIK_AUTH=$(printf '%s\n' "$TRAEFIK_AUTH_HASH" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s|admin:\$\$2y\$\$10\$\$your_secure_bcrypt_hash_here|$ESCAPED_TRAEFIK_AUTH|g" "$ENV_FILE"
        
        # Replace domain placeholders if domain was configured
        if [[ -n "$CONFIGURED_DOMAIN" ]]; then
            log "Configuring domain: $CONFIGURED_DOMAIN"
            sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your-infrastructure-domain.com/$CONFIGURED_DOMAIN/g" "$ENV_FILE"
        fi
        
        log "✅ Environment file created with secure passwords and domain configuration"
    else
        log "✅ Environment file already exists"
    fi
}

# Create necessary directories and set permissions
setup_directories() {
    log "📁 Setting up directory structure..."
    
    # Create required directories using infrastructure user
    sudo -u "$INFRASTRUCTURE_USER" mkdir -p "${INSTALL_DIR}/volumes/mariadb/init"
    sudo -u "$INFRASTRUCTURE_USER" mkdir -p "${INSTALL_DIR}/traefik"
    
    # Create acme.json for Let's Encrypt
    ACME_FILE="${INSTALL_DIR}/traefik/acme.json"
    if [[ ! -f "$ACME_FILE" ]]; then
        sudo -u "$INFRASTRUCTURE_USER" touch "$ACME_FILE"
        sudo chmod 600 "$ACME_FILE"
        sudo chown "$INFRASTRUCTURE_USER:$INFRASTRUCTURE_USER" "$ACME_FILE"
    fi
    
    log "✅ Directory structure created"
}

# Update domain references in all configuration files
update_domain_references() {
    if [[ -z "$CONFIGURED_DOMAIN" ]]; then
        log "No domain configured, skipping domain updates"
        return 0
    fi
    
    log "📝 Updating domain references to: $CONFIGURED_DOMAIN"
    
    # Update files using infrastructure user
    # Update test-deployment.sh
    if [[ -f "${INSTALL_DIR}/scripts/test-deployment.sh" ]]; then
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your-infrastructure-domain\.com/$CONFIGURED_DOMAIN/g" "${INSTALL_DIR}/scripts/test-deployment.sh"
        log "✅ Updated test-deployment.sh"
    fi
    
    # Update deployment-status.sh
    if [[ -f "${INSTALL_DIR}/scripts/deployment-status.sh" ]]; then
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your-infrastructure-domain\.com/$CONFIGURED_DOMAIN/g" "${INSTALL_DIR}/scripts/deployment-status.sh"
        log "✅ Updated deployment-status.sh"
    fi
    
    # Update README.md examples
    if [[ -f "${INSTALL_DIR}/README.md" ]]; then
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your-infrastructure-domain\.com/$CONFIGURED_DOMAIN/g" "${INSTALL_DIR}/README.md"
        log "✅ Updated README.md examples"
    fi
    
    # Update Traefik middleware configuration
    if [[ -f "${INSTALL_DIR}/traefik/dynamic/middleware.yml" ]]; then
        sudo -u "$INFRASTRUCTURE_USER" sed -i "s/your-infrastructure-domain\.com/$CONFIGURED_DOMAIN/g" "${INSTALL_DIR}/traefik/dynamic/middleware.yml"
        log "✅ Updated Traefik middleware configuration"
    fi
    
    log "✅ All domain references updated"
}

# Setup automated backup scheduling
setup_backup_automation() {
    log "⏰ Setting up automated backup scheduling..."
    
    # Check if backup script exists
    if [[ ! -f "${INSTALL_DIR}/scripts/backup.sh" ]]; then
        warning "Backup script not found, skipping backup automation"
        return 0
    fi
    
    # Make backup script executable
    sudo chmod +x "${INSTALL_DIR}/scripts/backup.sh"
    
    # Get backup frequency from user
    echo
    info "📅 Configure backup frequency:"
    echo "1) Daily at 2 AM"
    echo "2) Daily at 3 AM"
    echo "3) Every 12 hours (2 AM and 2 PM)"
    echo "4) Weekly on Sunday at 3 AM"
    echo "5) Custom schedule"
    echo "6) Skip backup automation"
    
    while true; do
        read -p "Choose backup frequency (1-6): " BACKUP_CHOICE
        case $BACKUP_CHOICE in
            1)
                CRON_SCHEDULE="0 2 * * *"
                SCHEDULE_DESC="Daily at 2 AM"
                break
                ;;
            2)
                CRON_SCHEDULE="0 3 * * *"
                SCHEDULE_DESC="Daily at 3 AM"
                break
                ;;
            3)
                CRON_SCHEDULE="0 2,14 * * *"
                SCHEDULE_DESC="Every 12 hours (2 AM and 2 PM)"
                break
                ;;
            4)
                CRON_SCHEDULE="0 3 * * 0"
                SCHEDULE_DESC="Weekly on Sunday at 3 AM"
                break
                ;;
            5)
                echo "Enter cron schedule format (minute hour day month weekday):"
                echo "Example: '0 2 * * *' for daily at 2 AM"
                read -p "Cron schedule: " CRON_SCHEDULE
                SCHEDULE_DESC="Custom: $CRON_SCHEDULE"
                break
                ;;
            6)
                log "Skipping backup automation setup"
                return 0
                ;;
            *)
                error "Invalid choice. Please select 1-6."
                ;;
        esac
    done
    
    # Create backup cron job
    CRON_JOB="$CRON_SCHEDULE cd ${INSTALL_DIR} && ./scripts/backup.sh full > /var/log/infrastructure-backup.log 2>&1"
    
    # Add cron job for infrastructure user
    sudo -u "$INFRASTRUCTURE_USER" bash -c "
        (crontab -l 2>/dev/null || true; echo \"$CRON_JOB\") | crontab -
    "
    
    # Create log rotation for backup logs
    sudo tee /etc/logrotate.d/infrastructure-backup > /dev/null << EOF
/var/log/infrastructure-backup.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    # Ensure log file exists with proper permissions
    sudo touch /var/log/infrastructure-backup.log
    sudo chmod 644 /var/log/infrastructure-backup.log
    
    log "✅ Backup automation configured: $SCHEDULE_DESC"
    log "✅ Backup logs will be written to: /var/log/infrastructure-backup.log"
    
    # Initialize backup system first
    log "🔧 Initializing backup system..."
    sudo -u "$INFRASTRUCTURE_USER" bash -c "cd ${INSTALL_DIR} && ./scripts/backup.sh init" || {
        warning "⚠️  Backup initialization failed - please run './scripts/backup.sh init' manually later"
        return 0  # Don't fail the entire install for backup issues
    }
    
    # Test backup setup (dry run)
    log "🧪 Testing backup configuration..."
    sudo -u "$INFRASTRUCTURE_USER" bash -c "cd ${INSTALL_DIR} && ./scripts/backup.sh --dry-run" || {
        warning "⚠️  Backup test failed - backup is configured but may need manual verification"
        return 0  # Don't fail the entire install for backup test issues
    }
    
    log "✅ Backup system initialized and tested successfully"
    
    # Show backup status
    echo
    info "📋 Backup Configuration Summary:"
    echo "   Schedule: $SCHEDULE_DESC"
    echo "   Command: ${INSTALL_DIR}/scripts/backup.sh full"
    echo "   Logs: /var/log/infrastructure-backup.log"
    echo "   View schedule: sudo -u $INFRASTRUCTURE_USER crontab -l"
    echo "   Manual backup: cd ${INSTALL_DIR} && ./scripts/backup.sh full"
    echo
}

# Final instructions
show_final_instructions() {
    log "🎉 Installation completed successfully!"
    echo
    info "📋 Next Steps:"
    echo "1. Add the SSH public key to your Git provider (GitHub/GitLab):"
    echo "   SSH Key: ${INFRASTRUCTURE_HOME}/.ssh/id_ed25519_git.pub"
    echo
    echo "2. Domain configuration:"
    if [[ -n "$CONFIGURED_DOMAIN" ]]; then
        echo "   ✅ Domain configured: $CONFIGURED_DOMAIN"
        echo "   Edit ${INSTALL_DIR}/.env if you need to change ACME_EMAIL"
    else
        echo "   Edit: ${INSTALL_DIR}/.env"
        echo "   - Set INFRASTRUCTURE_DOMAIN to your domain"
        echo "   - Set DOMAIN to your app domain"
        echo "   - Update ACME_EMAIL for Let's Encrypt"
    fi
    echo
    echo "3. Configure DNS records (wildcard recommended):"
    if [[ -n "$CONFIGURED_DOMAIN" ]]; then
        echo "   A    $CONFIGURED_DOMAIN              → YOUR_SERVER_IP"
        echo "   A    *.$CONFIGURED_DOMAIN           → YOUR_SERVER_IP"
    else
        echo "   A    your-infrastructure-domain.com              → YOUR_SERVER_IP"
        echo "   A    *.your-infrastructure-domain.com           → YOUR_SERVER_IP"
    fi
    echo
    echo "4. Configure firewall (example):"
    echo "   sudo ufw allow ssh"
    echo "   sudo ufw allow 80/tcp"
    echo "   sudo ufw allow 443/tcp"
    echo "   sudo ufw --force enable"
    echo
    info "🔐 Working with Infrastructure User:"
    echo "   Directory: $INSTALL_DIR (owned by $INFRASTRUCTURE_USER)"
    echo "   Switch to infrastructure user: sudo su - $INFRASTRUCTURE_USER"
    echo "   Edit files: sudo -u $INFRASTRUCTURE_USER nano $INSTALL_DIR/.env"
    echo "   Run Docker commands: docker-compose up -d (no sudo needed)"
    echo "   Security: Infrastructure user has NO passwordless sudo access"
    echo
    echo "5. Test the installation:"
    echo "   sudo su - $INFRASTRUCTURE_USER"
    echo "   cd $INSTALL_DIR"
    echo "   ./test-deployment.sh"
    echo
    echo "6. Start the infrastructure:"
    echo "   docker-compose up -d"
    echo
    echo "7. Initialize backup system (if configured):"
    echo "   ./scripts/backup.sh init"
    echo "   # Note: Backup automation is already configured via cron"
    echo
    
    # Display generated passwords if they were created
    if [[ -n "$GENERATED_MYSQL_ROOT_PASS" || -n "$GENERATED_GRAFANA_PASS" || -n "$GENERATED_TRAEFIK_PASS" ]]; then
        info "🔑 Generated Secure Passwords:"
        echo "   📋 Save these passwords in a secure location!"
        echo
        if [[ -n "$GENERATED_MYSQL_ROOT_PASS" ]]; then
            echo "   MariaDB Root Password: $GENERATED_MYSQL_ROOT_PASS"
        fi
        if [[ -n "$GENERATED_GRAFANA_PASS" ]]; then
            echo "   Grafana Admin Password: $GENERATED_GRAFANA_PASS"
        fi
        if [[ -n "$GENERATED_TRAEFIK_PASS" ]]; then
            echo "   Traefik Admin Password: $GENERATED_TRAEFIK_PASS (username: admin)"
        fi
        echo
        warning "⚠️  These passwords are also stored in ${INSTALL_DIR}/.env"
        echo
    fi
    
    info "🔐 Infrastructure endpoints (VPN-restricted):"
    if [[ -n "$CONFIGURED_DOMAIN" ]]; then
        echo "   - https://traefik.$CONFIGURED_DOMAIN"
        echo "   - https://status.$CONFIGURED_DOMAIN"
        echo "   - https://prometheus.$CONFIGURED_DOMAIN"
        echo
        info "🌐 Public endpoints:"
        echo "   - https://webhook.$CONFIGURED_DOMAIN"
    else
        echo "   - https://traefik.your-infrastructure-domain.com"
        echo "   - https://status.your-infrastructure-domain.com"
        echo "   - https://prometheus.your-infrastructure-domain.com"
        echo
        info "🌐 Public endpoints:"
        echo "   - https://webhook.your-infrastructure-domain.com"
    fi
    
    # Show backup information if configured
    if sudo -u "$INFRASTRUCTURE_USER" crontab -l 2>/dev/null | grep -q "backup.sh"; then
        echo
        info "⏰ Backup Automation:"
        echo "   Status: Enabled and configured"
        echo "   Logs: /var/log/infrastructure-backup.log"
        echo "   Manual backup: cd $INSTALL_DIR && ./scripts/backup.sh full"
        echo "   View schedule: sudo -u $INFRASTRUCTURE_USER crontab -l"
    fi
    
    echo
    warning "⚠️  Reboot recommended to ensure all group memberships are active"
}

# Main installation function
main() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "🚀 Docker Infrastructure Installer"
    echo "=========================================="
    echo -e "${NC}"
    
    check_root
    check_os
    check_requirements
    
    log "🚀 Starting infrastructure installation..."
    
    update_system
    create_user
    install_docker
    install_docker_compose
    setup_ssh_keys
    get_domain_configuration
    setup_repository
    setup_environment
    setup_directories
    update_domain_references
    setup_backup_automation
    
    show_final_instructions
}

# Run main function
main "$@"