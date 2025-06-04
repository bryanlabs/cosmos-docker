#!/bin/bash
# validation script for generic cosmos docker setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo
    print_status $BLUE "=================================="
    print_status $BLUE "$1"
    print_status $BLUE "=================================="
}

print_success() {
    print_status $GREEN "✅ $1"
}

print_warning() {
    print_status $YELLOW "⚠️  $1"
}

print_error() {
    print_status $RED "❌ $1"
}

# Check dependencies
check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    else
        print_success "Docker is installed"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    else
        print_success "Docker Compose is installed"
    fi
    
    if ! command -v make &> /dev/null; then
        missing_deps+=("make")
    else
        print_success "Make is installed"
    fi
    
    # Optional dependencies
    if command -v yamllint &> /dev/null; then
        print_success "yamllint is installed"
    else
        print_warning "yamllint not found (optional for YAML validation)"
        echo "  Install with: pip install yamllint"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Validate YAML files
validate_yaml() {
    print_header "Validating YAML Files"
    
    # First, test the main configuration
    if docker-compose -f cosmos.yml config --quiet; then
        print_success "cosmos.yml syntax is valid"
    else
        print_error "cosmos.yml has syntax errors"
        return 1
    fi
    
    # Test with development override if it exists
    if [ -f "docker-compose.dev.yml" ]; then
        # Create a minimal test environment for validation
        echo "THORNODE_VERSION=mainnet-23.105.1" > .env.test
        echo "DATA_DIR=" >> .env.test
        
        if docker-compose -f cosmos.yml -f docker-compose.dev.yml --env-file .env.test config --quiet; then
            print_success "Development override configuration is valid"
        else
            print_warning "Development override configuration has validation issues (may need build context)"
        fi
        
        # Cleanup test environment
        rm -f .env.test
    fi
    
    # Run yamllint if available
    if command -v yamllint &> /dev/null; then
        if yamllint *.yml 2>/dev/null; then
            print_success "All YAML files pass yamllint checks"
        else
            print_warning "Some YAML files have yamllint warnings"
        fi
    fi
}

# Validate environment files
validate_env_files() {
    print_header "Validating Environment Files"
    
    for env_file in *.env .env.example; do
        if [ -f "$env_file" ]; then
            echo "Checking $env_file..."
            
            # Basic validation - check for proper key=value format
            if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file"; then
                print_success "$env_file has valid format"
            else
                print_error "$env_file may have invalid format"
                return 1
            fi
            
            # Check for potential issues
            if grep -q "^[[:space:]]*$" "$env_file"; then
                print_warning "$env_file contains empty lines (usually OK)"
            fi
            
            if grep -q "^#" "$env_file"; then
                print_success "$env_file contains comments (good documentation)"
            fi
        fi
    done
}

# Test Makefile targets
test_makefile() {
    print_header "Testing Makefile Targets"
    
    local targets=("help" "start" "stop" "clean" "logs" "setup-data-dir")
    
    for target in "${targets[@]}"; do
        if make --dry-run "$target" &>/dev/null; then
            print_success "Target '$target' is valid"
        else
            if [ "$target" = "help" ]; then
                print_warning "Target '$target' not found (optional)"
            else
                print_warning "Target '$target' not found or has issues"
            fi
        fi
    done
}

# Check file permissions and structure
check_file_structure() {
    print_header "Checking File Structure"
    
    local required_files=("README.md" "cosmos.yml" "Makefile")
    local recommended_files=("LICENSE" "CONTRIBUTING.md" ".gitignore" ".env.example")
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_success "Required file '$file' exists"
        else
            print_error "Required file '$file' is missing"
            return 1
        fi
    done
    
    for file in "${recommended_files[@]}"; do
        if [ -f "$file" ]; then
            print_success "Recommended file '$file' exists"
        else
            print_warning "Recommended file '$file' is missing"
        fi
    done
    
    # Check for executable scripts
    if [ -f "monitor.sh" ]; then
        if [ -x "monitor.sh" ]; then
            print_success "monitor.sh is executable"
        else
            print_warning "monitor.sh exists but is not executable"
            echo "  Run: chmod +x monitor.sh"
        fi
    fi
}

# Test Docker Compose services
test_docker_services() {
    print_header "Testing Docker Compose Services"
    
    print_status $YELLOW "⚠️  Production Safety Mode: Skipping Docker operations to avoid interfering with running services"
    print_status $BLUE "Only validating configuration syntax..."
    
    # Create test environment with required variables
    echo "DATA_DIR=" > .env.validate
    echo "THORNODE_VERSION=mainnet-23.105.1" >> .env.validate
    echo "FORCE_REBUILD=false" >> .env.validate
    echo "NETWORK=cosmoshub-4" >> .env.validate
    echo "DAEMON_NAME=gaiad" >> .env.validate
    echo "NODE_VERSION=v18.1.0" >> .env.validate
    echo "MONIKER=test-node" >> .env.validate
    echo "MONIKER=test-node" >> .env.validate
    
    # Test service definitions without any Docker operations
    if docker-compose -f cosmos.yml --env-file .env.validate config --quiet >/dev/null 2>&1; then
        print_success "Docker Compose services are properly defined"
    else
        print_error "Docker Compose service definitions have errors"
        print_status $BLUE "Running detailed config check..."
        docker-compose -f cosmos.yml --env-file .env.validate config 2>&1 | head -10
        rm -f .env.validate
        return 1
    fi
    
    # Test development override configuration
    if [ -f "docker-compose.dev.yml" ]; then
        if docker-compose -f cosmos.yml -f docker-compose.dev.yml --env-file .env.validate config --quiet >/dev/null 2>&1; then
            print_success "Development override configuration works"
        else
            print_warning "Development override has validation issues (may be normal)"
        fi
    fi
    
    print_success "Configuration validation completed safely"
    
    # Cleanup
    rm -f .env.validate
}

# Security checks
security_checks() {
    print_header "Running Security Checks"
    
    # Check for sensitive files
    local sensitive_patterns=("*.pem" "*.key" "*.p12" "*.pfx" "id_rsa*" "*.keystore")
    local found_sensitive=false
    
    for pattern in "${sensitive_patterns[@]}"; do
        if find . -name "$pattern" -type f 2>/dev/null | head -1 | grep -q .; then
            print_warning "Found potentially sensitive files matching: $pattern"
            found_sensitive=true
        fi
    done
    
    if [ "$found_sensitive" = false ]; then
        print_success "No obvious sensitive files found"
    fi
    
    # Check for hardcoded secrets in environment files
    local secret_patterns=("password.*=" "secret.*=" "key.*=")
    local found_secrets=false
    
    for env_file in *.env .env.example; do
        if [ -f "$env_file" ]; then
            for pattern in "${secret_patterns[@]}"; do
                if grep -i "$pattern" "$env_file" | grep -v -i "changeme\|placeholder\|example\|your_" >/dev/null 2>&1; then
                    print_warning "Potential hardcoded secret in $env_file"
                    found_secrets=true
                fi
            done
        fi
    done
    
    if [ "$found_secrets" = false ]; then
        print_success "No obvious hardcoded secrets found"
    fi
}

# Main execution
main() {
    print_header "Cosmos Docker Validation Script"
    echo "This script validates the project structure and configuration files."
    echo
    
    local failed_checks=0
    
    check_dependencies || ((failed_checks++))
    validate_yaml || ((failed_checks++))
    validate_env_files || ((failed_checks++))
    test_makefile || ((failed_checks++))
    check_file_structure || ((failed_checks++))
    test_docker_services || ((failed_checks++))
    security_checks || ((failed_checks++))
    
    print_header "Validation Summary"
    
    if [ $failed_checks -eq 0 ]; then
        print_success "All validation checks passed! 🎉"
        echo
        print_status $GREEN "Your Cosmos Docker setup is ready for deployment."
        exit 0
    else
        print_error "$failed_checks validation check(s) failed"
        echo
        print_status $RED "Please fix the issues above before proceeding."
        exit 1
    fi
}

# Run main function
main "$@"
