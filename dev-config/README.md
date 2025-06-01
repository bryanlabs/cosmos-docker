# Development Environment

This directory contains development-specific configurations and tools for working with the Cosmos Docker setup.

## Usage

### Basic Development Setup

```bash
# Start with development overrides
docker compose -f cosmos.yml -f docker-compose.dev.yml up -d

# View enhanced logs
docker compose logs -f cosmos
```

### Development Tools

Enable the development tools container:

```bash
# Start with dev tools
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools up -d

# Access the tools container
docker compose exec dev-tools bash

# Inside the container, you have access to:
# - curl, jq for API testing
# - htop, procps for monitoring
# - Direct access to node data (read-only)
```

### Monitoring Stack

Enable full monitoring with Prometheus and Grafana:

```bash
# Start with monitoring stack
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile monitoring up -d

# Access Grafana at http://localhost:3000
# Default credentials: admin/admin

# Access Prometheus at http://localhost:9090
```

### Log Aggregation

Enable Loki for log aggregation:

```bash
# Start with logging stack
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile logging up -d

# Loki available at http://localhost:3100
```

### All Development Features

Start everything:

```bash
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools --profile monitoring --profile logging up -d
```

## Development Features

### Enhanced Logging
- Debug level logging enabled
- JSON format for structured logs
- Local logs directory mounted for easy access

### Performance Tuning for Development
- Faster consensus timeouts for quicker testing
- Reduced mempool rechecking
- More lenient networking settings

### Monitoring
- Prometheus scraping Tendermint metrics
- Grafana dashboards for visualization
- Loki for log aggregation

### Utilities
- Development tools container with common utilities
- Read-only access to node data
- Health check optimized for development

## Configuration Files

- `prometheus.yml` - Prometheus scraping configuration
- `grafana/` - Grafana provisioning configurations
  - `datasources/` - Auto-configured data sources
  - `dashboards/` - Dashboard provisioning

## Tips

1. **Faster Restarts**: Development mode uses `restart: on-failure` instead of `unless-stopped`
2. **Log Access**: Logs are mounted to `./logs/` for easy access
3. **Custom Configs**: Mount additional configs to `/dev-config` in the container
4. **API Testing**: Use the dev-tools container for testing APIs without installing tools locally

## Cleaning Up

```bash
# Stop all development services
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools --profile monitoring --profile logging down

# Remove development volumes
docker volume prune
```
