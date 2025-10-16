# Frontend build stage
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install npm dependencies
RUN npm ci --only=production

# Copy frontend source files
COPY resources/ resources/
COPY public/ public/
COPY vite.config.js ./
COPY tailwind.config.js ./
COPY postcss.config.js ./

# Build frontend assets
RUN npm run build

# PHP dependencies stage
FROM serversideup/php:8.4-cli AS php-deps

WORKDIR /var/www/html

# Copy composer files for better layer caching
COPY composer.json composer.lock ./

# Install PHP dependencies (production optimized)
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# Laravel Production stage using ServersideUp/php with NGINX Unit
FROM serversideup/php:8.4-unit

# Copy Laravel application to the container
COPY . /var/www/html

# Copy PHP dependencies from previous stage
COPY --from=php-deps /var/www/html/vendor/ /var/www/html/vendor/

# Copy built frontend assets from frontend stage
COPY --from=frontend-builder /app/public/build/ /var/www/html/public/build/

RUN composer dump-autoload --optimize --no-dev && \
    php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache && \
    php artisan event:cache