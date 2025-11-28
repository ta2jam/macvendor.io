# MacVendor.io Deployment Guide

## 🚀 Production Deployment

This guide provides step-by-step instructions for deploying the MacVendor.io API service using Docker Compose.

## 📋 Prerequisites

### Infrastructure Requirements
- **Server**: Ubuntu 20.04+ or similar Linux distribution
- **Memory**: 2GB RAM minimum, 4GB recommended
- **Storage**: 20GB SSD minimum
- **Network**: Public IP with domain name (optional)

### Software Requirements
- Docker 20.10+
- Docker Compose 2.0+
- Node.js 18+ (for local development)

## 🏗️ Infrastructure Setup

### 1. Server Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Reboot or logout/login to apply group changes
```

### 2. Project Setup

```bash
# Clone repository
git clone https://github.com/your-org/macvendor.io.git
cd macvendor.io

# Create environment file
cp .env.example .env
# Edit .env with your configuration
```

## 🐳 Docker Deployment

### 1. Docker Compose Configuration

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://macvendor:password@db:5432/macvendor
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=macvendor
      - POSTGRES_USER=macvendor
      - POSTGRES_PASSWORD=your_secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U macvendor"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  postgres_data:
  redis_data:
```

### 2. Environment Configuration

```bash
# .env file
NODE_ENV=production
DATABASE_URL=postgresql://macvendor:your_secure_password@db:5432/macvendor
REDIS_URL=redis://redis:6379
API_RATE_LIMIT=1000
JWT_SECRET=your_jwt_secret_here
```

### 3. Deployment Commands

```bash
# Build and start services
docker compose up -d --build

# Check service status
docker compose ps

# View logs
docker compose logs -f api

# Stop services
docker compose down

# Update deployment
docker compose pull
docker compose up -d
```

## 📊 Monitoring Setup

### 1. Basic Monitoring

```bash
# Check service health
curl http://localhost:3000/health

# Monitor resource usage
docker stats

# View application logs
docker compose logs -f --tail=100 api
```

### 2. Prometheus + Grafana (Optional)

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'macvendor-api'
    static_configs:
      - targets: ['host.docker.internal:3000']
    metrics_path: '/metrics'
```

## 🔒 Security Configuration

### 1. Firewall Setup

```bash
# Allow SSH and HTTP
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable
```

### 2. SSL with Let's Encrypt (Optional)

```bash
# Install certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d yourdomain.com

# Update nginx configuration for SSL
```

### 3. Database Security

```sql
-- Create limited user for application
CREATE USER macvendor_app WITH PASSWORD 'secure_app_password';
GRANT CONNECT ON DATABASE macvendor TO macvendor_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO macvendor_app;
```

## 🔄 Data Management

### 1. Initial Data Import

```bash
# Run data import
docker compose exec api npm run import-data

# Verify data
docker compose exec db psql -U macvendor -d macvendor -c "SELECT COUNT(*) FROM mac_vendors;"
```

### 2. Backup Strategy

```bash
# Database backup script
#!/bin/bash
BACKUP_DIR="/backups/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup database
docker compose exec db pg_dump -U macvendor macvendor > $BACKUP_DIR/database.sql

# Compress
gzip $BACKUP_DIR/database.sql

# Upload to cloud storage (optional)
# aws s3 cp $BACKUP_DIR/database.sql.gz s3://your-backup-bucket/
```

## 🚀 Scaling

### 1. Horizontal Scaling

```yaml
# docker-compose.scale.yml
version: '3.8'

services:
  api:
    deploy:
      replicas: 3
    # ... rest of config
```

```bash
# Scale API instances
docker compose up -d --scale api=3
```

### 2. Load Balancing

```yaml
# nginx.conf
upstream macvendor_api {
    server api1:3000;
    server api2:3000;
    server api3:3000;
}

server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://macvendor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## 📋 Maintenance Procedures

### 1. Updates

```bash
# Pull latest changes
git pull origin main

# Rebuild and restart
docker compose down
docker compose up -d --build
```

### 2. Troubleshooting

```bash
# Check service health
docker compose ps

# Inspect logs
docker compose logs api

# Restart specific service
docker compose restart api

# Access database
docker compose exec db psql -U macvendor -d macvendor
```

## 📊 Performance Tuning

### 1. Database Optimization

```sql
-- Create indexes
CREATE INDEX CONCURRENTLY idx_mac_vendors_prefix ON mac_vendors(mac_prefix);
CREATE INDEX CONCURRENTLY idx_api_usage_created ON api_usage(created_at);

-- Analyze tables
ANALYZE mac_vendors;
ANALYZE api_usage;
```

### 2. Redis Configuration

```yaml
# redis.conf
maxmemory 256mb
maxmemory-policy allkeys-lru
tcp-keepalive 300
```

## 🚨 Incident Response

### Common Issues

#### Service Unavailable
```bash
# Check service status
docker compose ps

# Restart services
docker compose restart

# Check logs
docker compose logs --tail=50
```

#### Database Connection Issues
```bash
# Check database connectivity
docker compose exec api pg_isready -h db -p 5432

# Restart database
docker compose restart db
```

#### High Memory Usage
```bash
# Check memory usage
docker stats

# Restart problematic service
docker compose restart api
```

This deployment guide provides a simple, production-ready setup for the MacVendor.io service using Docker Compose.
