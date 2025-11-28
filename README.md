[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](https://github.com/ta2jam/macvendor.io)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![API Version](https://img.shields.io/badge/API-v1.0-orange.svg)](#api-documentation)
[![Open Source](https://img.shields.io/badge/Open%20Source-Yes-success.svg)](#contributing)

A fast, reliable, and open-source MAC address vendor lookup API service. macVendor.io provides developers with accurate manufacturer information for MAC addresses through a simple REST API.

## Quick Start

### Local Sandbox (Node.js + Postgres + Redis)

This repo includes a minimal runnable skeleton for local development:

```bash
# 1) Install dependencies
npm install

# 2) Start local infra (Postgres + Redis)
docker compose -f docker-compose.dev.yml up -d

# 3) Seed a small OUI fixture (offline-friendly)
npm run seed:fixtures

# 4) Start the API (hot reload)
npm run dev
```

> The local skeleton exposes the same endpoints as production but returns stubbed data until you replace the seed fixtures with real IEEE imports.
> Set `REQUIRE_API_KEY=true` to mimic production auth locally.

### API Usage (Production)

```bash
# Lookup a single MAC address
curl "https://api.macvendor.io/v1/lookup/00:1B:44:11:3A:B7" \
  -H "x-api-key: <YOUR_API_KEY>"

# Bulk lookup (up to 100 MAC addresses)
curl -X POST "https://api.macvendor.io/v1/lookup/bulk" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{"macs": ["00:1B:44:11:3A:B7", "00:50:56:12:34:56"]}'
```

### Response Format

```json
{
  "mac_address": "00:1B:44:11:3A:B7",
  "vendor_name": "Cisco Systems, Inc",
  "vendor_address": "170 West Tasman Drive, San Jose, CA 95134",
  "country_code": "US",
  "oui_assigned": "2005-01-01",
  "block_type": "MA-L",
  "last_updated": "2024-11-28T10:58:57Z"
}
```

## Table of Contents

- [Features](#features)
- [API Documentation](#api-documentation)
- [OpenAPI](#openapi)
- [Installation](#installation)
- [Architecture](#architecture)
- [Data Pipeline](#data-pipeline)
- [Performance](#performance)
- [Testing](#testing)
- [Security](#security)
- [Privacy](#privacy)
- [Privacy Policy](#privacy-policy)
- [Contributing](#contributing)
- [Deployment](#deployment)
- [License](#license)

## Features

- **Fast Lookup**: Sub-100ms response times with optimized database queries
- **High Accuracy**: Curated database with 40,000+ vendor entries
- **Bulk Processing**: Process up to 100 MAC addresses per request
- **Open Source**: Fully open with community contributions welcome
- **RESTful API**: Clean, documented REST interface
- **API Key Security**: `x-api-key` header with tiered rate limits
- **Rate Limited**: Fair usage with configurable limits per tier
- **Data Fresh**: Regular updates from IEEE registration database
- **JSON Responses**: Clean, structured JSON output

## API Documentation

### Base URL
```
https://api.macvendor.io/v1
```

### Authentication & Rate Limits

- Send `x-api-key: <key>` on all requests (anonymous tier allowed but heavily rate-limited).
- Rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.
- Error codes are documented in `API_SPECIFICATION.md` and the OpenAPI file at `openapi/openapi.yaml`.

### Endpoints

#### 1. Single MAC Lookup
```http
GET /lookup/{mac_address}
```

**Parameters:**
- `mac_address` (string, required): MAC address in format `XX:XX:XX:XX:XX:XX`, `XX-XX-XX-XX-XX-XX`, or `XXXXXXXXXXXX`

**Example:**
```bash
curl "https://api.macvendor.io/v1/lookup/00:1B:44:11:3A:B7"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "mac_address": "00:1B:44:11:3A:B7",
    "vendor_name": "Cisco Systems, Inc",
    "vendor_address": "170 West Tasman Drive, San Jose, CA 95134",
    "country_code": "US",
    "oui_assigned": "2005-01-01",
    "block_type": "MA-L",
    "last_updated": "2024-11-28T10:58:57Z"
  },
  "timestamp": "2024-11-28T10:58:57Z"
}
```

#### 2. Bulk MAC Lookup
```http
POST /lookup/bulk
```

**Request Body:**
```json
{
  "macs": ["00:1B:44:11:3A:B7", "00:50:56:12:34:56", "AA:BB:CC:DD:EE:FF"]
}
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "mac_address": "00:1B:44:11:3A:B7",
      "vendor_name": "Cisco Systems, Inc",
      "vendor_address": "170 West Tasman Drive, San Jose, CA 95134",
      "country_code": "US",
      "oui_assigned": "2005-01-01",
      "block_type": "MA-L",
      "last_updated": "2024-11-28T10:58:57Z"
    }
  ],
  "not_found": ["AA:BB:CC:DD:EE:FF"],
  "timestamp": "2024-11-28T10:58:57Z"
}
```

#### 3. Search Vendors
```http
GET /vendors/search?query=cisco&limit=10
```

**Parameters:**
- `query` (string, required): Search term for vendor name
- `limit` (integer, optional): Maximum results (default: 10, max: 100)

### Rate Limits

| Plan | Requests/Hour | Requests/Day |
|------|---------------|--------------|
| Anonymous | 1,000 | 10,000 |
| Registered | 10,000 | 100,000 |
| Enterprise | Custom | Custom |

### Error Responses

```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded. Try again later.",
    "details": {
      "limit": 1000,
      "window": "1 hour",
      "reset_at": "2024-11-28T11:58:57Z"
    }
  }
}
```

## OpenAPI

- The full contract lives at `openapi/openapi.yaml` (OpenAPI 3.1). It defines request/response schemas, error objects, rate limit headers, and validation rules for MAC formats (colon, hyphen, and 12-hex compact).
- Swagger UI: `npm run docs:serve` renders the spec locally.

## Architecture

### System Overview

```mermaid
graph TB
    A[API Gateway<br/>Express.js] --> B[Authentication Middleware]
    A --> C[Rate Limiting Middleware]
    A --> D[Load Balancer]

    D --> E[MAC Lookup Handler]
    D --> F[Bulk Lookup Handler]
    D --> G[Vendor Search Handler]

    E --> H[(PostgreSQL Database)]
    E --> I[(Redis Cache)]
    F --> H
    F --> I
    G --> H
    G --> I

    J[Data Update Service] --> H
    J --> K[IEEE OUI Database]

    L[Monitoring<br/>Prometheus/Grafana] --> A
    L --> H
    L --> I
```

### Technology Stack

- **Backend**: Node.js with Express.js
- **Database**: PostgreSQL with optimized indexing
- **Cache**: Redis for frequently accessed MAC addresses
- **API Documentation**: OpenAPI 3.0 with Swagger UI
- **Testing**: Jest with 95%+ coverage
- **CI/CD**: GitHub Actions with automated deployments
- **Monitoring**: Prometheus + Grafana
- **Infrastructure**: Docker containers on cloud platform

### Database Schema

```sql
-- MAC Address to Vendor Mapping
CREATE TABLE mac_vendors (
    id SERIAL PRIMARY KEY,
    mac_prefix VARCHAR(8) UNIQUE NOT NULL,  -- First 3 octets (OUI)
    vendor_name VARCHAR(255) NOT NULL,
    vendor_address TEXT,
    country_code CHAR(2),
    oui_assigned DATE,
    block_type VARCHAR(10),  -- MA-L, MA-M, MA-S
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),

    INDEX idx_mac_prefix (mac_prefix),
    INDEX idx_vendor_name (vendor_name),
    INDEX idx_country (country_code)
);

-- API Keys and Authentication
CREATE TABLE api_keys (
    id SERIAL PRIMARY KEY,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255),
    tier VARCHAR(20) NOT NULL,  -- anonymous, registered, enterprise
    rate_limit_per_hour INTEGER NOT NULL,
    rate_limit_per_day INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),

    INDEX idx_key_hash (key_hash),
    INDEX idx_tier (tier)
);

-- Usage Tracking (for rate limiting and basic analytics)
CREATE TABLE api_usage (
    id SERIAL PRIMARY KEY,
    api_key_id INTEGER REFERENCES api_keys(id),
    endpoint VARCHAR(100) NOT NULL,
    ip_address INET,
    created_at TIMESTAMP DEFAULT NOW(),

    INDEX idx_api_key_id (api_key_id),
    INDEX idx_created_at (created_at)
);
```

## Data Pipeline

- **Sources**: IEEE OUI CSV (primary)
- **Scheduler**: Weekly updates from IEEE with validation
- **Validation**: Regex validation for MAC prefixes, ISO country codes
- **Fixtures**: `data/fixtures/oui_sample.csv` for development and testing
- **Cache Invalidation**: Cache cleared after data updates

## Performance

### Benchmarks (Target)

- **Response Time**: < 100ms (95th percentile)
- **Throughput**: 10,000 requests/second per instance
- **Database Queries**: Optimized with indexing
- **Cache Hit Rate**: > 80% for popular MAC addresses
- **Uptime**: 99.9% availability

### Optimization Strategies

1. **Database Indexing**: Primary key on MAC prefix for O(1) lookups
2. **Caching**: Redis cache for top 10,000 most requested MAC addresses
3. **Connection Pooling**: Efficient database connection management
4. **Response Compression**: Gzip compression for API responses
5. **CDN Integration**: Static assets served via CDN
6. **Load Balancing**: Horizontal scaling with load balancers

## Testing

- **Unit/Integration**: Use Jest with `npm test`
- **Lint/Format**: ESLint + Prettier with `npm run lint` / `npm run format`
- **Load Testing**: k6 with `npm run test:k6` for smoke tests
- **OpenAPI Validation**: `npm run lint:openapi` validates the spec

## Security

### API Security

- **API Keys**: Store only salted + hashed API keys (no raw secrets in DB); never return keys in responses.
- **Rate Limiting**: IP-based and API-key-based rate limiting with configurable thresholds; include rate-limit headers on responses.
- **Input Validation**: Strict MAC address format validation
- **SQL Injection Prevention**: Parameterized queries
- **CORS Configuration**: Secure cross-origin resource sharing
- **Request Logging**: Minimal structured logs for security monitoring; avoid verbose body logging by default.

### Data Security

- **Database Encryption**: At-rest encryption for sensitive data
- **HTTPS Only**: TLS for all API communications
- **Input Sanitization**: All inputs sanitized before processing
- **Error Handling**: Generic error messages to prevent information leakage
- **Data Minimization**: Keep essential OUI→vendor mappings

## Privacy

- High-level policy lives in `PRIVACY_POLICY.md`.
- Default log retention: keep IP + timestamp + MAC lookup events for 30 days max, then delete.
- Do not log request bodies by default.
- MAC addresses may be personal data; handle lookup logs carefully.

## Privacy Policy

See `PRIVACY_POLICY.md` for collection, use, and retention details.

## 🛠️ Installation

### Prerequisites

- Node.js 18+
- PostgreSQL 14+
- Redis 6+
- Docker (optional)

### Local Development

1. **Clone Repository**
   ```bash
   git clone https://github.com/ta2jam/macvendor.io.git
   cd macvendor.io
   ```

2. **Install Dependencies**
   ```bash
   npm install
   ```

3. **Database Setup**
   ```bash
   # Create database
   createdb macvendor
   
   # Run migrations
   npm run migrate
   # or
   python manage.py migrate
   ```

4. **Import MAC Vendor Data**
   ```bash
   npm run import-data
   ```

5. **Start Development Server**
   ```bash
   npm run dev
   ```

### Docker Deployment

```bash
# Build and run with Docker Compose
docker compose up -d
```

### Development Setup

```bash
# Install development dependencies
npm install --dev

# Run tests
npm test

# Run linting
npm run lint

# Format code
npm run format
```

### Adding New Vendors

1. **Data Sources**: Vendor data comes primarily from IEEE OUI database
2. **Update Process**: Monthly data synchronization from IEEE
3. **Community Contributions**: Submit vendor updates via pull requests
4. **Data Validation**: All new entries validated for format and completeness

### Code of Conduct

We expect all contributors to maintain a welcoming and inclusive environment.

## Deployment

### Production Deployment

#### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/macvendor
REDIS_URL=redis://localhost:6379

# API Configuration
PORT=3000
NODE_ENV=production
API_RATE_LIMIT=1000

# Monitoring
PROMETHEUS_PORT=9090
LOG_LEVEL=info
```

#### Deployment Options

1. **Cloud Platforms**: DigitalOcean, Railway, or similar
2. **Container Platforms**: Docker Compose for simple deployments
3. **VPS**: Ubuntu with systemd services

### Monitoring & Alerts

- **Health Checks**: `/health` endpoint for load balancer checks
- **Metrics**: Response time, throughput, error rates
- **Logging**: Structured JSON logs with request tracing
- **Alerts**: Email/Slack notifications for critical issues

## License

This project is licensed under the GPL-3.0 License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

- **IEEE OUI Database**: Public domain data
- **Vendor Data**: Aggregated from multiple public sources
- **Open Source Dependencies**: See package.json for full license list

## Support

- **Documentation**: [https://docs.macvendor.io](https://docs.macvendor.io)
- **Issues**: [GitHub Issues](https://github.com/ta2jam/macvendor.io/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ta2jam/macvendor.io/discussions)
