#!/bin/bash
set -e

# Script to optionally delete unhealthy StatefulSets and run Helm upgrade
# Usage: ./fix-statefulsets.sh [--remove-ss]
# Configuration is set by the workflow that generates this script

NAMESPACE="__NAMESPACE__"
RELEASE_NAME="__RELEASE_NAME__"
VALUES_FILE="__VALUES_FILE__"
REMOVE_SS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --remove-ss)
      REMOVE_SS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--remove-ss]"
      exit 1
      ;;
  esac
done

echo "📄 Namespace: $NAMESPACE"
echo "📄 Release: $RELEASE_NAME"
echo "📄 Values file: $VALUES_FILE"
echo ""

# Define unhealthy pod states
UNHEALTHY_STATES="ImagePullBackOff|ErrImagePull|CrashLoopBackOff|Error"

if [ "$REMOVE_SS" = true ]; then
  echo "🔍 Checking for unhealthy StatefulSets in namespace: $NAMESPACE"
  echo ""

  # Find StatefulSets with unhealthy pods
  UNHEALTHY_STS=$(kubectl get pods -n "$NAMESPACE" -o json | \
    jq -r --arg states "$UNHEALTHY_STATES" '
      .items[] |
      select(
        .metadata.ownerReferences[]?.kind == "StatefulSet" and
        (.status.containerStatuses[]?.state |
         to_entries[] |
         .value.reason? // "" |
         test($states))
      ) |
      .metadata.ownerReferences[] |
      select(.kind == "StatefulSet") |
      .name
    ' | sort -u)

  if [ -z "$UNHEALTHY_STS" ]; then
    echo "✅ No unhealthy StatefulSets found!"
  else
    echo "⚠️  Found unhealthy StatefulSets:"
    for sts in $UNHEALTHY_STS; do
      echo "  - $sts"

      # Show pod status for this StatefulSet
      echo "    Pods:"
      kubectl get pods -n "$NAMESPACE" -l "app=$sts" -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.containerStatuses[*].ready,\
RESTARTS:.status.containerStatuses[*].restartCount,\
REASON:.status.containerStatuses[*].state.waiting.reason 2>/dev/null | head -5
      echo ""
    done

    echo "🗑️  Deleting unhealthy StatefulSets (keeping PVCs)..."

    for sts in $UNHEALTHY_STS; do
      echo "  Deleting StatefulSet: $sts"
      kubectl delete statefulset "$sts" -n "$NAMESPACE" --cascade=orphan
    done

    echo "✅ StatefulSets deleted (PVCs preserved)"
  fi
  echo ""
fi

echo "🚀 Running Helm upgrade..."

helm upgrade "$RELEASE_NAME" ./foodios-chart \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  -f ./helm-values-override.yaml 

echo ""
echo "✅ Helm upgrade completed!"
echo ""
echo "📋 Checking pod status..."
sleep 5

kubectl get pods -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.containerStatuses[*].ready,\
RESTARTS:.status.containerStatuses[*].restartCount

echo ""
echo "✅ Done!"
