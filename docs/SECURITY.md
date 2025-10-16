# 🔒 Database Security & Network Isolation Guide

## 🚨 Current Security Issues

### Problem: Shared Network Access
- **Issue**: ALL project containers are on the same `shared` Docker network
- **Risk**: If one project container is compromised, attacker can:
  - Directly communicate with ALL other project containers
  - Access shared infrastructure services (database)
  - Perform network reconnaissance and lateral movement
- **Attack Vector**: `docker exec compromised-container nmap 172.18.0.0/16`

### Network Topology (Current - INSECURE)
```
┌─────────────────────────────────────────┐
│            Shared Network               │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │Project A │ │Project B │ │Database │ │
│  │Container │◄┤Container │◄┤ MariaDB │ │
│  └──────────┘ └──────────┘ └─────────┘ │
│       ▲             ▲           ▲      │
│       └─────────────┼───────────┘      │
│          Direct Network Access         │  
└─────────────────────────────────────────┘
```

## 🛡️ Security Solutions

### 1️⃣ **Database User Isolation** (Implemented)

Each project gets its own database and user:

```sql
-- Project: myapp, Environment: production
CREATE DATABASE IF NOT EXISTS `myapp_production`;
CREATE USER IF NOT EXISTS 'myapp_prod_user'@'%' IDENTIFIED BY 'unique_secure_password';
GRANT ALL PRIVILEGES ON `myapp_production`.* TO 'myapp_prod_user'@'%';
```

### 2️⃣ **Network Segmentation** (Recommended)

Create project-specific networks to prevent lateral movement:

```yaml
# Secure Network Topology:
networks:
  traefik:                    # Public web traffic only
  infrastructure_internal:    # Database, Redis, monitoring (backend-only)  
  myapp_network:             # Isolated network for myapp project
  
services:
  # Project containers ONLY get access to what they need
  myapp:
    networks:
      - traefik              # Web access
      - myapp_network        # Project isolation  
      - infrastructure_db    # Database access (limited)
  
  # Infrastructure services on separate network
  mariadb-shared:
    networks:
      - infrastructure_db    # Database access only
```

### 3️⃣ **Database Per Project** (Advanced)

For high-security environments, run separate database containers:

```yaml
services:
  myapp-db:
    image: mariadb:10.11
    networks:
      - myapp_network  # Isolated network
    environment:
      MYSQL_ROOT_PASSWORD: ${MYAPP_DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYAPP_DB_NAME}
```

## 🔧 Implementation Levels

### Level 1: User Isolation (Current)
```bash
# Create isolated database users
./scripts/setup-database.sh setup myapp production
```
- ✅ **Easy to implement**
- ✅ **Prevents accidental data access**
- ⚠️ **Still shared database server**
- ⚠️ **Root access compromises all**

### Level 2: Network Isolation (Recommended)
```yaml
# Project docker-compose.yml
networks:
  traefik:
    external: true
  myapp_isolated:    # Project-specific network
    external: false
  db_access:         # Limited database access
    external: true
    name: database_network
```
- ✅ **Network-level isolation**
- ✅ **Limits lateral movement**
- ✅ **Shared infrastructure still possible**
- ⚠️ **More complex setup**

### Level 3: Complete Isolation (High Security)
```yaml
# Each project has its own database container
services:
  app:
    networks: [traefik, myapp_private]
  
  myapp-database:
    image: mariadb:10.11
    networks: [myapp_private]  # No shared access
```
- ✅ **Complete isolation**
- ✅ **No shared attack surface**
- ⚠️ **Higher resource usage**
- ⚠️ **More complex backup/monitoring**

## 🚀 Quick Security Improvements

### 1. Enable Database User Isolation

Update your project `.env` files:

```bash
# projects/myapp/production/.env
DB_CONNECTION=mysql
DB_HOST=mariadb-shared
DB_DATABASE=myapp_production        # Project-specific database
DB_USERNAME=myapp_prod_user         # Project-specific user
DB_PASSWORD=unique_secure_password  # Unique password
```

### 2. Generate Unique Database Credentials

```bash
# Auto-generate secure credentials per project
./scripts/setup-database.sh setup myapp production
./scripts/setup-database.sh setup myapp staging
```

### 3. Network Segmentation (Advanced)

Create project-specific networks in docker-compose.yml:

```yaml
services:
  app:
    networks:
      - traefik          # Web access
      - myapp_network    # Project isolation
      - database_access  # Limited DB access

networks:
  traefik:
    external: true
  myapp_network:
    external: false
  database_access:
    external: true
    name: infrastructure_db
```

## 📊 Security Trade-offs

| Level | Security | Complexity | Resources | Shared Services |
|-------|----------|------------|-----------|-----------------|
| **Level 1** | Basic | Low | Low | Full sharing |
| **Level 2** | Good | Medium | Medium | Limited sharing |
| **Level 3** | Excellent | High | High | No sharing |

## 🎯 Recommended Approach

For most use cases, **Level 2 (Network Isolation)** provides the best balance:

1. **Keep shared infrastructure** (MariaDB, monitoring)
2. **Isolate project networks** to prevent lateral movement
3. **Use unique database users** per project/environment
4. **Monitor database access** via Grafana dashboards

## 🛠️ Implementation Steps

1. **Immediate**: Run database user isolation
   ```bash
   ./scripts/setup-database.sh setup yourproject production
   ```

2. **Medium term**: Implement network segmentation
   - Update project docker-compose files
   - Create project-specific networks
   - Test connectivity

3. **Long term**: Consider per-project databases for sensitive applications

## 🔍 Security Monitoring

Monitor for suspicious database activity:
- Multiple failed login attempts
- Cross-database queries
- Unusual query patterns
- Network connections between projects

Add to Grafana dashboard:
- Database connections per user
- Failed authentication attempts
- Cross-project network traffic