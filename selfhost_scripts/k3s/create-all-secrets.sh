#!/bin/bash
set -e

NAMESPACE="foodios"

BASE_DIR=$(git rev-parse --show-toplevel)
CONFIG_DIR=$BASE_DIR/config
CERT_DIR=$BASE_DIR/foodios-chart/certs

echo "Creating Kubernetes secrets for Foodios stack from existing config files..."
echo ""

# Create namespace if it doesn't exist
echo "Creating namespace if it doesn't exist..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo ""

# Function to create secret from env file with variable substitution
create_secret_from_file() {
  local secret_name=$1
  local env_file=$2

  if [ -f "$env_file" ]; then
    echo "Creating $secret_name from $env_file..."

    # Create a temporary file for substituted values
    local temp_file=$(mktemp)

    # Use envsubst to perform variable substitution while preserving formatting
    # First, export all variables from the env file
    set -a
    source "$env_file"
    set +a

    # Use envsubst to substitute variables in the file
    envsubst < "$env_file" > "$temp_file"

    # Create secret from temp file
    kubectl create secret generic $secret_name \
      --from-env-file="$temp_file" \
      --namespace=$NAMESPACE \
      --dry-run=client -o yaml | kubectl apply -f -

    # Clean up temp file
    rm "$temp_file"

    echo "✓ $secret_name created"
  else
    echo "⚠ Warning: $env_file not found, skipping $secret_name"
  fi
  echo ""
}

# Create secrets from config files
create_secret_from_file "db-secrets" "$CONFIG_DIR/db-secrets.env"
create_secret_from_file "pds-secrets" "$CONFIG_DIR/pds-secrets.env"
create_secret_from_file "bsky-secrets" "$CONFIG_DIR/bsky-secrets.env"
create_secret_from_file "plc-secrets" "$CONFIG_DIR/plc-secrets.env"
create_secret_from_file "bgs-secrets" "$CONFIG_DIR/bgs-secrets.env"
create_secret_from_file "palomar-secrets" "$CONFIG_DIR/palomar-secrets.env"
create_secret_from_file "opensearch-secrets" "$CONFIG_DIR/opensearch-secrets.env"
create_secret_from_file "social-link-secrets" "$CONFIG_DIR/social-link-secrets.env"
create_secret_from_file "ozone-secrets" "$CONFIG_DIR/ozone-secrets.env"
create_secret_from_file "backup-secrets" "$CONFIG_DIR/backup-secrets.env"
create_secret_from_file "relay-secrets" "$CONFIG_DIR/relay-secrets.env"

echo "Creating tls secret"
kubectl create secret tls local-tls \
    --cert=$CERT_DIR/tls.crt \
    --key=$CERT_DIR/tls.key \
    -n foodios

echo ""
echo "======================================"
echo "✓ All secrets created successfully!"
echo "======================================"
echo ""
echo "To list all secrets:"
echo "  kubectl get secrets -n $NAMESPACE"
echo ""
echo "To view a specific secret:"
echo "  kubectl get secret <secret-name> -n $NAMESPACE -o yaml"
echo ""
echo "To decode a secret value:"
echo "  kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data.KEY}' | base64 -w0 -d"
echo ""
echo "To delete all secrets (if you need to recreate them):"
echo "  kubectl delete secrets -n $NAMESPACE db-secrets pds-secrets bsky-secrets plc-secrets bgs-secrets palomar-secrets opensearch-secrets social-link-secrets ozone-secrets backup-secrets"
echo ""
