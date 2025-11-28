#!/bin/bash
# Manage OpenSearch Log Retention using ISM

set -e

OPENSEARCH_HOST="${OPENSEARCH_HOST:-localhost:9200}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << HELP
OpenSearch Log Retention Management (ISM)

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    status              Show current retention status
    policies            List all ISM policies
    explain INDEX       Show ISM status for index pattern
    add POLICY INDEX    Add policy to indices
    indices             List all indices
    stats               Show statistics

Examples:
    $0 status
    $0 add logs-90day-policy logs-pds-*
    $0 explain logs-*

HELP
}

check_opensearch() {
    if ! curl -s "http://${OPENSEARCH_HOST}/_cluster/health" > /dev/null 2>&1; then
        echo -e "${RED}Error: OpenSearch not available${NC}"
        exit 1
    fi
}

show_status() {
    echo "OpenSearch Status"
    echo "================="
    curl -s "http://${OPENSEARCH_HOST}/_cluster/health" | jq -r '"Status: \(.status) | Nodes: \(.number_of_nodes)"'
    echo ""
    echo "Indices:"
    curl -s "http://${OPENSEARCH_HOST}/_cat/indices/logs-*?v&h=index,docs.count,store.size" | head -10
}

list_policies() {
    echo "ISM Policies:"
    curl -s "http://${OPENSEARCH_HOST}/_plugins/_ism/policies" | jq -r '.policies[]._id' 2>/dev/null
}

explain_ism() {
    curl -s "http://${OPENSEARCH_HOST}/_plugins/_ism/explain/$1" | jq '.'
}

add_policy() {
    curl -X POST "http://${OPENSEARCH_HOST}/_plugins/_ism/add/$2" \
        -H 'Content-Type: application/json' \
        -d "{\"policy_id\": \"$1\"}"
}

list_indices() {
    curl -s "http://${OPENSEARCH_HOST}/_cat/indices/logs-*?v"
}

show_stats() {
    curl -s "http://${OPENSEARCH_HOST}/_cat/indices/logs-*?h=docs.count,store.size" | \
        awk '{docs+=$1} END {print "Total documents:", docs}'
}

check_opensearch

case "${1:-status}" in
    status) show_status ;;
    policies) list_policies ;;
    explain) explain_ism "$2" ;;
    add) add_policy "$2" "$3" ;;
    indices) list_indices ;;
    stats) show_stats ;;
    *) show_help ;;
esac
