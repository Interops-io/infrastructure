# Dockerfile Examples

This directory contains example Dockerfile templates for different frameworks. Copy the appropriate Dockerfile to your project source code directory.

## Available Templates

- `laravel.Dockerfile` - PHP 8.4 with ServersideUp/php for Laravel projects
- `static.Dockerfile` - Nginx Alpine for static sites (React, Vue, Angular build output)

## Usage

1. **Copy the appropriate Dockerfile to your project root**:
   ```bash
   # For Laravel projects
   cp infrastructure/docker/examples/laravel.Dockerfile /path/to/your-project/Dockerfile
   
   # For static sites
   cp infrastructure/docker/examples/static.Dockerfile /path/to/your-project/Dockerfile
   ```

2. **Customize as needed** for your specific project requirements

3. **The infrastructure will automatically use your Dockerfile** when building containers

## Project Structure Expected

Your project source should be organized as:
```
src/
└── your-project-name/
    ├── Dockerfile              # ← Copy from examples and customize
    ├── composer.json           # For Laravel/PHP
    └── ... (your source code)
```

## Docker-Compose Build Context

The infrastructure docker-compose.yml files point to:
```yaml
build:
  context: ../../../src/your-project-name  # Your source directory
  dockerfile: Dockerfile
```

This keeps your Dockerfile and build configuration with your source code, not with the infrastructure.