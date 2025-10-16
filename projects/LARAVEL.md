# Laravel Deployment Guide

This guide covers Laravel-specific configuration for deployment with the infrastructure.

## HTTPS Detection Behind Traefik Proxy

**Problem:** Laravel sees HTTP traffic from Traefik, not HTTPS, which can cause issues with:
- `url()` helper generating HTTP URLs
- `asset()` helper pointing to HTTP
- `redirect()` not preserving HTTPS
- CSRF token issues

## Solution: Middleware Approach (Recommended)

The cleanest solution is to create a middleware that configures trusted proxies and forces HTTPS detection.

### Laravel 11+ (Current Version)

**1. Create the middleware:**
```bash
php artisan make:middleware TrustProxies
```

**2. Update `app/Http/Middleware/TrustProxies.php`:**
```php
<?php

namespace App\Http\Middleware;

use Illuminate\Http\Middleware\TrustProxies as Middleware;
use Illuminate\Http\Request;

class TrustProxies extends Middleware
{
    /**
     * The trusted proxies for this application.
     *
     * @var array<int, string>|string|null
     */
    protected $proxies = '*';

    /**
     * The headers that should be used to detect proxies.
     *
     * @var int
     */
    protected $headers =
        Request::HEADER_X_FORWARDED_FOR |
        Request::HEADER_X_FORWARDED_HOST |
        Request::HEADER_X_FORWARDED_PORT |
        Request::HEADER_X_FORWARDED_PROTO |
        Request::HEADER_X_FORWARDED_AWS_ELB;
}
```

**3. Register in `bootstrap/app.php` (Laravel 11+):**
```php
<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        $middleware->prependToGroup('web', [
            \App\Http\Middleware\TrustProxies::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions) {
        //
    })->create();
```

**4. Environment variables in `.env`:**
```bash
APP_URL=https://your-app-domain.com
ASSET_URL=https://your-app-domain.com
```

### Laravel 8-10 (Previous Versions)

**1. Update existing `app/Http/Middleware/TrustProxies.php`:**
```php
<?php

namespace App\Http\Middleware;

use Illuminate\Http\Middleware\TrustProxies as Middleware;
use Illuminate\Http\Request;

class TrustProxies extends Middleware
{
    /**
     * The trusted proxies for this application.
     *
     * @var array<int, string>|string|null
     */
    protected $proxies = '*';

    /**
     * The headers that should be used to detect proxies.
     *
     * @var int
     */
    protected $headers = Request::HEADER_X_FORWARDED_ALL;
}
```

**2. Register in `app/Http/Kernel.php`:**
```php
<?php

namespace App\Http;

use Illuminate\Foundation\Http\Kernel as HttpKernel;

class Kernel extends HttpKernel
{
    /**
     * The application's global HTTP middleware stack.
     *
     * These middleware are run during every request to your application.
     *
     * @var array<int, class-string|string>
     */
    protected $middleware = [
        // ... other middleware
        \App\Http\Middleware\TrustProxies::class,
        // ... other middleware
    ];
    
    // ... rest of kernel
}
```

**3. Environment variables in `.env`:**
```bash
APP_URL=https://your-app-domain.com
ASSET_URL=https://your-app-domain.com
```

### Force HTTPS (Optional)

If you want to force HTTPS redirects at the application level, create an additional middleware:

```bash
php artisan make:middleware ForceHttps
```

**`app/Http/Middleware/ForceHttps.php`:**
```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ForceHttps
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (!$request->isSecure() && app()->environment('production')) {
            return redirect()->secure($request->getRequestUri(), 301);
        }

        return $next($request);
    }
}
```

Register this middleware in your middleware stack (after TrustProxies).

## Database Configuration

### Automatic Database Setup

When you create a Laravel project with the project creation wizard (`./scripts/create-project.sh quick laravel`), the system will automatically:
1. Create a project-specific database
2. Create isolated database user
3. Generate `.env.database` file with credentials

### Manual Database Setup

```bash
# From infrastructure directory
./scripts/setup-database.sh setup ./projects/mylaravel production
./scripts/setup-database.sh setup ./projects/mylaravel staging
```

## Common Laravel Commands in Hooks

### Pre-deploy Hook (`pre_deploy.sh`)
```bash
#!/bin/bash
set -e

echo "🔧 Pre-deploy: Preparing Laravel application"

# Clear caches before deployment
docker compose exec -T app php artisan config:clear || true
docker compose exec -T app php artisan route:clear || true
docker compose exec -T app php artisan view:clear || true
```

### Post-deploy Hook (`post_deploy.sh`)
```bash
#!/bin/bash
set -e

echo "🎯 Post-deploy: Running Laravel application setup"

# Wait for database to be ready
sleep 5

# Run migrations
docker compose exec -T app php artisan migrate --force

# Cache configuration and routes
docker compose exec -T app php artisan config:cache
docker compose exec -T app php artisan route:cache
docker compose exec -T app php artisan view:cache

# Create storage link if needed
docker compose exec -T app php artisan storage:link

echo "✅ Laravel application setup completed"
```

## Example Docker Compose Configuration

See the `example-laravel-app/` directory for complete examples including:
- Multi-environment setup (production, staging)
- Queue workers
- Scheduled tasks
- Proper network configuration
- SSL certificates

## Troubleshooting

### Mixed Content Warnings
If you're getting mixed content warnings, ensure:
1. `APP_URL` and `ASSET_URL` use `https://`
2. `URL::forceScheme('https')` is set in AppServiceProvider
3. Trusted proxies are configured correctly

### CSRF Token Issues
If CSRF tokens aren't working:
1. Check that `APP_URL` matches your actual domain
2. Verify trusted proxies configuration
3. Ensure session domain is set correctly

### Database Connection Issues
1. Verify database credentials in `.env`
2. Check that database user exists
3. Ensure your container is on the `database` network