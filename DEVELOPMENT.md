# Development Guide

This guide is for developers who want to contribute to the THORChain Docker project or customize it for their own needs.

## Development Setup

### Prerequisites

- Docker Desktop or Docker Engine with Docker Compose
- Make (usually pre-installed on Linux/macOS)
- Git
- Text editor or IDE

### Optional Tools

- `yamllint` for YAML validation: `pip install yamllint`
- `jq` for JSON processing: `sudo apt-get install jq` (Ubuntu/Debian)
- `curl` for API testing

### Getting Started

1. **Clone and enter the repository:**
   ```bash
   git clone https://github.com/thorchain/thorchain-docker.git
   cd thorchain-docker
   ```

2. **Validate your setup:**
   ```bash
   ./validate.sh
   ```

3. **Start development environment:**
   ```bash
   # Use development override configuration
   docker compose -f thorchain.yml -f docker-compose.dev.yml up -d
   ```

## Development Configuration

### Development Override File

The `docker-compose.dev.yml` file provides development-specific configuration:

- **Volume Mounts**: Maps local directories for easier development
- **Debug Ports**: Exposes additional ports for debugging
- **Development Image Tags**: Uses development or latest tags instead of specific versions
- **Resource Limits**: Reduced resource constraints for development machines

### Environment Files

- **`.env.example`**: Template for minimal configuration
- **`thorchain-1.env`**: Production-ready configuration for mainnet
- **`.env.dev`**: Development-specific environment variables (create as needed)

## Project Structure

```
thorchain-docker/
├── .github/
│   └── workflows/          # GitHub Actions CI/CD workflows
│       ├── lint.yml        # YAML linting
│       ├── docker-test.yml # Docker configuration testing
│       └── security.yml    # Security scanning
├── thorchain.yml           # Main Docker Compose configuration
├── docker-compose.dev.yml  # Development overrides
├── Makefile                # Build and deployment automation
├── monitor.sh              # Node monitoring script
├── validate.sh             # Setup validation script
├── .env.example            # Minimal environment template
├── thorchain-1.env         # Complete mainnet configuration
├── README.md               # Main documentation
├── CONTRIBUTING.md         # Contribution guidelines
├── DEVELOPMENT.md          # This file
├── LICENSE                 # MIT License
└── .gitignore              # Git ignore patterns
```

## Making Changes

### 1. Docker Compose Configuration

When modifying `thorchain.yml`:

- **Test syntax**: `docker compose -f thorchain.yml config --quiet`
- **Validate with development override**: `docker compose -f thorchain.yml -f docker-compose.dev.yml config --quiet`
- **Use YAML anchors** for repeated configuration (see existing examples)
- **Include health checks** for new services
- **Use environment variable substitution** for configurable values

### 2. Environment Configuration

When modifying environment files:

- **Maintain compatibility** between `.env.example` (minimal) and `thorchain-1.env` (complete)
- **Add comments** explaining new variables
- **Use sections** with clear headers
- **Provide sensible defaults** in `.env.example`
- **Include validation** in `validate.sh` for new variables

### 3. Makefile Targets

When adding new Makefile targets:

- **Use `.PHONY`** for targets that don't create files
- **Add help text** using `## Comment` format
- **Include error handling** with `set -e` in shell commands
- **Test with dry-run**: `make --dry-run target-name`

### 4. Scripts

When modifying shell scripts:

- **Use `set -e`** for error handling
- **Include dependency checks** at the beginning
- **Provide colored output** for better user experience
- **Add progress indicators** for long-running operations
- **Make scripts executable**: `chmod +x script.sh`

## Testing

### Local Testing

1. **Run validation script:**
   ```bash
   ./validate.sh
   ```

2. **Test specific configurations:**
   ```bash
   # Test main configuration
   docker compose -f thorchain.yml config --quiet
   
   # Test with development overrides
   docker compose -f thorchain.yml -f docker-compose.dev.yml config --quiet
   
   # Test Makefile targets
   make --dry-run help up down clean
   ```

3. **Test environment files:**
   ```bash
   # Check environment file syntax
   set -a && source .env.example && set +a
   set -a && source thorchain-1.env && set +a
   ```

### CI/CD Testing

The project includes GitHub Actions workflows that run automatically:

- **YAML Lint** (`lint.yml`): Validates YAML syntax and style
- **Docker Test** (`docker-test.yml`): Tests Docker configurations and Makefile
- **Security Scan** (`security.yml`): Scans for vulnerabilities and secrets

## Code Style

### YAML Files

- **Indentation**: 2 spaces
- **Line length**: Maximum 120 characters
- **Comments**: Use comments to explain complex configurations
- **Anchors**: Use YAML anchors to reduce duplication

### Shell Scripts

- **Shebang**: Use `#!/bin/bash`
- **Error handling**: Include `set -e` at the top
- **Quoting**: Quote variables: `"$variable"`
- **Functions**: Use functions for repeated code
- **Comments**: Comment complex logic

### Environment Files

- **Format**: `KEY=value` (no spaces around =)
- **Comments**: Use `#` for comments
- **Sections**: Group related variables with comment headers
- **Naming**: Use UPPERCASE for environment variables

## Common Development Tasks

### Adding a New Service

1. **Define service in `thorchain.yml`:**
   ```yaml
   new-service:
     image: service:latest
     restart: unless-stopped
     environment:
       - SETTING=${SETTING:-default}
     volumes:
       - service-data:/data
     healthcheck:
       test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
       interval: 30s
       timeout: 10s
       retries: 3
   ```

2. **Add environment variables to `.env.example`:**
   ```bash
   # New Service Configuration
   SETTING=default_value
   ```

3. **Add complete configuration to `thorchain-1.env`:**
   ```bash
   # ================================
   # New Service Configuration
   # ================================
   SETTING=production_value
   # Additional production settings...
   ```

4. **Test the configuration:**
   ```bash
   ./validate.sh
   ```

### Modifying Existing Configuration

1. **Make changes incrementally**
2. **Test after each change**
3. **Update documentation** if needed
4. **Run validation script**
5. **Test with both minimal and complete environments**

### Adding New Makefile Targets

```makefile
.PHONY: new-target
new-target: ## Description of what this target does
	@echo "Running new target..."
	# Commands here
```

### Debugging Issues

1. **Check logs:**
   ```bash
   make logs
   # or
   docker compose -f thorchain.yml logs -f
   ```

2. **Inspect configuration:**
   ```bash
   docker compose -f thorchain.yml config
   ```

3. **Test individual services:**
   ```bash
   docker compose -f thorchain.yml up service-name
   ```

4. **Validate environment:**
   ```bash
   ./validate.sh
   ```

## Release Process

1. **Update version tags** in Docker Compose files
2. **Test with validation script**: `./validate.sh`
3. **Update documentation** as needed
4. **Create pull request** with detailed description
5. **Ensure CI/CD passes**
6. **Tag release** after merge to main

## Best Practices

### Security

- **Never commit secrets** or private keys
- **Use `.env` files** for sensitive configuration
- **Scan for vulnerabilities** regularly
- **Keep dependencies updated**

### Performance

- **Use specific image tags** instead of `latest` in production
- **Configure resource limits** appropriately
- **Use health checks** for all services
- **Monitor resource usage**

### Maintainability

- **Document configuration changes**
- **Use consistent naming conventions**
- **Keep configurations DRY** (Don't Repeat Yourself)
- **Test on different environments**

## Getting Help

- **GitHub Issues**: Report bugs and request features
- **GitHub Discussions**: Ask questions and share ideas
- **THORChain Community**: Join the official Discord/Telegram
- **Documentation**: Check the main README.md

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.
