#!/bin/bash
kubectl delete namespace foodios
BASE_DIR=$(git rev-parse --show-toplevel)
$BASE_DIR/selfhost_scripts/k3s/create-all-secrets.sh
helm install foodios $BASE_DIR/foodios-chart -n foodios --create-namespace -f $BASE_DIR/foodios-chart/values-local.yaml