# Quick Setup Configuration Guide

This document explains how to configure framework presets for the project creation wizard.

## Configuration File Location

The configuration is stored in: `config/quick-setups.conf`

## Configuration Format

The file uses INI-style format with sections for each framework preset:

```ini
[framework_name]
description=Human readable description shown in menus
environments=comma-separated list of default environments
services=comma-separated list of services to include
dockerfile_template=dockerfile template to use for this framework
```

## Available Services

- `database` - MariaDB database with isolated user
- `redis` - Project-specific Redis instance
- `queue` - Background job processing container
- `scheduler` - Cron-like task scheduling container  
- `websockets` - WebSocket server container

## Available Dockerfile Templates

- `laravel` - PHP 8.4 with ServersideUp/php for Laravel projects
- `static` - Nginx Alpine for static sites (React, Vue, Angular build output)

## Environment Options

- `production` - Production environment
- `staging` - Staging environment  
- `development` - Development environment

## Example Configurations

### Full-Stack Framework (Laravel)
```ini
[laravel]
description=Laravel application with full stack (database, redis, queue, scheduler)
environments=production,staging
services=database,redis,queue,scheduler
dockerfile_template=laravel
```

### Static Site (React/Vue)
```ini
[react]
description=React SPA with static file serving
environments=production,staging
services=
dockerfile_template=static
```



## Adding New Framework Presets

1. **Edit the config file**: Add a new section to `config/quick-setups.conf`

2. **Choose appropriate services**: Select services needed for your framework

3. **Select dockerfile template**: Use existing template or add new one to the script

4. **Test your preset**: 
   ```bash
   ./scripts/create-project.sh quick your-framework test-project example.com
   ```

## Custom Dockerfile Templates

To add a new dockerfile template:

1. Edit `scripts/create-project.sh`
2. Find the `create_dockerfile()` function  
3. Add a new case for your template:

```bash
your-template)
    cat > "$dockerfile" << 'EOF'
FROM your-base-image

# Your dockerfile content here

EXPOSE 8080
CMD ["your-command"]
EOF
    ;;
```

## Validation

The script automatically:
- Validates framework names exist in config
- Shows available frameworks when invalid name provided
- Falls back to sensible defaults for missing values

## Examples of Use Cases

### WordPress Site
```ini
[wordpress]
description=WordPress with database and redis caching
environments=production,staging  
services=database,redis
dockerfile_template=php
```



### JAMStack Site  
```ini
[gatsby]
description=Gatsby static site with build process
environments=production,staging
services=
dockerfile_template=static
```

This configuration system makes the project creation wizard easily extensible for any framework or technology stack.