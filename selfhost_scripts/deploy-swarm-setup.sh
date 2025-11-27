#!/bin/bash

# Bluesky Docker Swarm Setup Script
# This script prepares your environment for Docker Swarm deployment

set -e  # Exit on error

echo "==================================="
echo "Bluesky Docker Swarm Setup"
echo "==================================="
echo

# Function to print colored output
print_success() {
    echo -e "✓ $1"
}

print_error() {
    echo -e "✗ $1"
}

print_warning() {
    echo -e "⚠ $1"
}

print_info() {
    echo -e "ℹ $1"
}

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. It's recommended to run Docker as a non-root user."
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker is installed"

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running. Please start Docker."
    exit 1
fi
print_success "Docker daemon is running"

# Check if Swarm is already initialized
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    print_success "Docker Swarm is already initialized"
else
    print_info "Initializing Docker Swarm..."
    SWARM_OUTPUT=$(docker swarm init 2>&1) || {
        # If swarm init fails due to multiple IPs, extract and use the first suggested IP
        if echo "$SWARM_OUTPUT" | grep -q "advertise-addr"; then
            ADVERTISE_ADDR=$(echo "$SWARM_OUTPUT" | grep -oP '(?<=--advertise-addr )[0-9.]+' | head -1)
            if [ -n "$ADVERTISE_ADDR" ]; then
                print_info "Multiple network interfaces detected. Using $ADVERTISE_ADDR"
                docker swarm init --advertise-addr "$ADVERTISE_ADDR"
            else
                print_error "Failed to initialize Docker Swarm"
                echo "$SWARM_OUTPUT"
                exit 1
            fi
        else
            print_error "Failed to initialize Docker Swarm"
            echo "$SWARM_OUTPUT"
            exit 1
        fi
    }
    print_success "Docker Swarm initialized"
fi

echo
echo "==================================="
echo "Checking Required Files"
echo "==================================="
echo

# Check for required directories and files
REQUIRED_DIRS=(
    "config"
    "certs"
)

REQUIRED_FILES=(
    ".env"
    "docker-compose.swarm.yaml"
    "certs/root.crt"
    "certs/intermediate.crt"
    "certs/ca-certificates.crt"
)



# Check directories
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_success "Directory exists: $dir"
    else
        print_warning "Directory missing: $dir (may cause issues)"
    fi
done

# Check files
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "File exists: $file"
    else
        print_error "File missing: $file"
        echo "  This file is required for deployment"
    fi
done

echo
echo "==================================="
echo "Creating Docker Secrets"
echo "==================================="
echo

# Function to create or update a secret
create_secret() {
    local secret_name=$1
    local secret_file=$2

    if [ ! -f "$secret_file" ]; then
        print_error "$secret_name (file not found: $secret_file) aborting..."
        return 1
    fi

    # Check if secret already exists
    if docker secret inspect "$secret_name" &> /dev/null; then
        print_info "Secret $secret_name already exists"

        # Ask user if they want to recreate it
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Removing old secret $secret_name..."
            # Secrets can't be updated, need to remove and recreate
            # This will fail if any service is using it
            if docker secret rm "$secret_name" 2>/dev/null; then
                print_success "Removed old secret $secret_name"
            else
                print_error "Failed to remove $secret_name (services may be using it)"
                print_info "To update, remove the stack first: docker stack rm foodios"
                return 1
            fi
        else
            return 0
        fi
    fi

    # Create the secret
    if docker secret create "$secret_name" "$secret_file"; then
        print_success "Created secret: $secret_name"
    else
        print_error "Failed to create secret: $secret_name"
        return 1
    fi
}


create_secret "db_secrets" "config/db-secrets.env"
create_secret "bgs_secrets" "config/bgs-secrets.env"
create_secret "pds_secrets" "config/pds-secrets.env"
create_secret "bsky_secrets" "config/bsky-secrets.env"
create_secret "plc_secrets" "config/plc-secrets.env"
create_secret "ozone_secrets" "config/ozone-secrets.env"
create_secret "opensearch_secrets" "config/opensearch-secrets.env"
create_secret "palomar_secrets" "config/palomar-secrets.env"
create_secret "social-link_secrets" "config/social-link-secrets.env"
create_secret "backup_secrets" "config/backup-secrets.env"
create_secret "google_backup_credentials" "config/google_backup_credentials.json"

if docker network inspect foodios-net &> /dev/null; then
    print_info "foodios-net already exists, not recreating"
else 
    print_info "Creating network foodios-net"
    if docker network create --attachable --driver=overlay foodios-net; then 
        print_success "Created network"
    else 
        print_error "Failed to create network"
    fi
fi

echo
echo "==================================="
echo "Deployment Information"
echo "==================================="
echo

print_info "Setup complete! Next steps:"
echo
echo "1. Review the docker-compose.swarm.yaml file"
echo "2. Ensure your .env file has all required variables"
echo "3. Deploy the stack:"
echo "   docker stack deploy -c docker-compose.swarm.yaml foodios"
echo
echo "4. Monitor deployment:"
echo "   docker stack ps foodios"
echo "   docker stack services foodios"
echo
echo "5. View logs for a specific service:"
echo "   docker service logs -f foodios_<service_name>"
echo
echo "6. Update the stack after changes:"
echo "   docker stack deploy -c docker-compose.swarm.yaml foodios"
echo
echo "7. Remove the stack:"
echo "   docker stack rm foodios"
echo

# Check if .env file exists and source it for validation
if [ -f ".env" ]; then
    print_info "Checking environment variables..."

    # List of critical variables
    CRITICAL_VARS=(
        "DOMAIN"
        "POSTGRES_USER"
        "BRANDED_NAMESPACE"
        "UNBRANDED_NAMESPACE"
    )

    # Source the .env file
    set -a
    source .env 2>/dev/null || true
    set +a

    missing_vars=()
    for var in "${CRITICAL_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -eq 0 ]; then
        print_success "All critical environment variables are set"
    else
        print_warning "Missing environment variables in .env:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
    fi
fi

echo
print_success "Setup script completed!"
