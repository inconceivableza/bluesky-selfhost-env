#!/bin/bash
# Setup OpenSearch Index State Management (ISM) Policies
# This script configures log retention policies for different types of logs

set -e

# Configuration
OPENSEARCH_HOST="${OPENSEARCH_HOST:-localhost:9200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "OpenSearch Log Retention Setup"
echo "========================================="
echo ""

# Function to check if OpenSearch is ready
check_opensearch() {
    echo -n "Checking OpenSearch availability... "
    for i in {1..30}; do
        if curl -s "http://${OPENSEARCH_HOST}/_cluster/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    echo -e "${RED}✗${NC}"
    echo "Error: OpenSearch is not available at http://${OPENSEARCH_HOST}"
    exit 1
}

# Function to apply ISM policy
apply_policy() {
    local policy_name=$1
    local policy_file=$2
    local description=$3

    echo -n "Applying policy '${policy_name}'... "

    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "http://${OPENSEARCH_HOST}/_plugins/_ism/policies/${policy_name}" \
        -H 'Content-Type: application/json' \
        -d @"${policy_file}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        echo -e "${GREEN}✓${NC}"
        echo "  Description: ${description}"
    else
        echo -e "${RED}✗${NC}"
        echo "  Error: HTTP $http_code"
        echo "  Response: $body"
        return 1
    fi
}

# Function to list current policies
list_policies() {
    echo ""
    echo "Current ISM Policies:"
    echo "===================="
    curl -s "http://${OPENSEARCH_HOST}/_plugins/_ism/policies" | jq -r '.policies[]._id' 2>/dev/null | while read -r policy; do
        echo "  - $policy"
    done
}

# Function to show policy details
show_policy() {
    local policy_name=$1
    echo ""
    echo "Policy Details: ${policy_name}"
    echo "========================================"
    curl -s "http://${OPENSEARCH_HOST}/_plugins/_ism/policies/${policy_name}" | jq '.'
}

# Main execution
main() {
    check_opensearch

    echo ""
    echo "Applying ISM Policies..."
    echo "========================"

    # Apply 30-day retention policy (default)
    apply_policy "logs-30day-policy" \
        "${SCRIPT_DIR}/opensearch-ism-policy.json" \
        "Standard 30-day retention: Hot (7d) → Warm (7d) → Delete (30d)"

    # Apply 90-day retention policy (for important logs)
    apply_policy "logs-90day-policy" \
        "${SCRIPT_DIR}/opensearch-ism-policy-long.json" \
        "Long 90-day retention: Hot (30d) → Warm (30d) → Cold (30d) → Delete (90d)"

    # Apply 7-day retention policy (for verbose/debug logs)
    apply_policy "logs-7day-policy" \
        "${SCRIPT_DIR}/opensearch-ism-policy-short.json" \
        "Short 7-day retention: Hot (3d) → Delete (7d)"

    echo ""
    echo -e "${GREEN}✓${NC} All policies applied successfully!"

    list_policies

    echo ""
    echo "========================================="
    echo "Policy Application"
    echo "========================================="
    echo ""
    echo "The 30-day policy is automatically applied to all 'logs-*' indices."
    echo ""
    echo "To manually apply a different policy to specific indices:"
    echo "  curl -X POST http://${OPENSEARCH_HOST}/_plugins/_ism/add/logs-pds-* \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"policy_id\": \"logs-90day-policy\"}'"
    echo ""
    echo "To check policy status:"
    echo "  curl http://${OPENSEARCH_HOST}/_plugins/_ism/explain/logs-*"
    echo ""
}

# Run main function
main
