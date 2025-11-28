# macVendor.io API Specification

## OpenAPI 3.0 Specification

This document provides the complete API specification for MacVendor.io in OpenAPI 3.0 format.

### Base URL
```
Production: https://api.macvendor.io/v1
Staging: https://staging-api.macvendor.io/v1
Development: http://localhost:3000/v1
```

### Authentication & Rate Limiting

- All requests should include `x-api-key: <key>`. Anonymous access is allowed with stricter limits.
- Rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.
- API keys align with tiers (anonymous, registered, enterprise - future).
- Error responses for throttling use `429` plus the standard error schema below.
- API keys are stored as salted hashes in the database; raw keys are never persisted or returned.
- Rate limiting is enforced per API key and per source IP to throttle abuse.

### OpenAPI Source of Truth

- Full spec: `openapi/openapi.yaml` (OpenAPI 3.1). This document summarizes the same contract.

### Core Endpoints

#### 1. Single MAC Lookup
```yaml
GET /lookup/{mac_address}
```

**Parameters:**
- `mac_address` (string, required): MAC address in format `XX:XX:XX:XX:XX:XX`, `XX-XX-XX-XX-XX-XX`, or `XXXXXXXXXXXX`

**Validation rules:**
- Must be 12 hexadecimal characters; separators `:` or `-` are optional.
- Case-insensitive; normalized to upper-case colon-delimited for responses.
- Returns `400` with code `INVALID_MAC_ADDRESS` if validation fails.

**Example:**
```bash
curl "https://api.macvendor.io/v1/lookup/00:1B:44:11:3A:B7" \
  -H "x-api-key: <YOUR_API_KEY>"
```

**Response (200):**
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

**Error Responses:**
- `400`: Invalid MAC address format
- `401`: Missing/invalid API key
- `403`: Forbidden (suspended/revoked key)
- `404`: MAC address not found
- `429`: Rate limit exceeded
- `500`: Internal server error

#### 2. Bulk MAC Lookup
```yaml
POST /lookup/bulk
```

**Request Body:**
```json
{
  "macs": ["00:1B:44:11:3A:B7", "00:50:56:12:34:56"]
}
```

**Validation rules:**
- `macs` is required, array length 1-100.
- Each entry must satisfy the single lookup validation; invalid entries trigger `400 BULK_LIMIT_EXCEEDED` or `INVALID_MAC_ADDRESS`.
- Returns `413` if the payload size exceeds configured limits.

**Response (200):**
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
  "not_found": ["00:50:56:12:34:56"],
  "timestamp": "2024-11-28T10:58:57Z"
}
```

**Error Responses:**
- `400`: Invalid request body or macs > 100
- `401`: Missing/invalid API key
- `403`: Forbidden (suspended/revoked key)
- `429`: Rate limit exceeded
- `500`: Internal server error

#### 3. Vendor Search
```yaml
GET /vendors/search?query=cisco&limit=10
```

**Parameters:**
- `query` (string, required): Search term for vendor name
- `limit` (integer, optional): Maximum results (default: 10, max: 100)

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "vendor_name": "Cisco Systems, Inc",
      "country_code": "US",
      "total_macs": 1250
    }
  ],
  "total": 1,
  "timestamp": "2024-11-28T10:58:57Z"
}
```

**Error Responses:**
- `400`: Missing/invalid query
- `401`: Missing/invalid API key
- `403`: Forbidden (suspended/revoked key)
- `429`: Rate limit exceeded
- `500`: Internal server error

#### 4. Health Check
```yaml
GET /health
```

**Response (200):**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2024-11-28T10:58:57Z",
  "uptime": 3600
}
```

### Rate Limits

| Tier | Requests/Hour | Requests/Day |
|------|---------------|--------------|
| Anonymous | 1,000 | 10,000 |
| Registered | 10,000 | 100,000 |
| Enterprise | Custom | Custom |

Responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers.
`/vendors/search` and all lookup endpoints expose the same rate-limit headers.

### Error Codes

| Code | Description | Retry After |
|------|-------------|-------------|
| `INVALID_MAC_ADDRESS` | MAC address format is invalid | No |
| `MAC_NOT_FOUND` | MAC address not in database | No |
| `UNAUTHORIZED` | Missing or invalid API key | No |
| `FORBIDDEN` | API key revoked/suspended | No |
| `RATE_LIMIT_EXCEEDED` | Request rate limit exceeded | Yes |
| `BULK_LIMIT_EXCEEDED` | Too many MAC addresses in bulk request | No |
| `INTERNAL_ERROR` | Unexpected server error | Yes |

**Standard error schema**

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
  },
  "timestamp": "2024-11-28T10:58:57Z"
}
```

### Request/Response Examples

#### Successful Request
```bash
curl -X GET "https://api.macvendor.io/v1/lookup/00:1B:44:11:3A:B7" \
  -H "Accept: application/json" \
  -H "User-Agent: MyApp/1.0" \
  -H "x-api-key: <YOUR_API_KEY>"
```

#### Rate Limit Error
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

#### Bulk Request Example
```bash
curl -X POST "https://api.macvendor.io/v1/lookup/bulk" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{
    "macs": [
      "00:1B:44:11:3A:B7",
      "00:50:56:12:34:56",
      "AA:BB:CC:DD:EE:FF"
    ]
  }'
```

### Performance Targets

- **Response Time**: < 100ms (95th percentile)
- **Availability**: 99.9% uptime
- **Throughput**: 10,000 requests/second per instance
- **Cache Hit Rate**: > 80% for popular MAC addresses

### Security Headers

All responses include the following headers:
```http
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'
```

### CORS Policy

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Accept, User-Agent
Access-Control-Max-Age: 86400
```

### Logging & Privacy
- Lookup logs (IP + timestamp + MAC) are retained for a maximum of 30 days for rate limiting and abuse prevention, then deleted.
- Request bodies are not logged by default.
- Error responses avoid leaking internal details.
- Responses include `X-Request-Id` for log correlation.
