#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="kube-prometheus-stack"
NAMESPACE="monitoring"
CHART="prometheus-community/kube-prometheus-stack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Adding Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

echo "==> Creating monitoring namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying Grafana admin secret..."
if [[ -f "${SCRIPT_DIR}/grafana-admin-secret.yaml" ]]; then
  kubectl apply -f "${SCRIPT_DIR}/grafana-admin-secret.yaml"
else
  echo "WARNING: grafana-admin-secret.yaml not found, using example template."
  echo "Copy monitoring/grafana-admin-secret.example.yaml and set a strong password."
  kubectl apply -f "${SCRIPT_DIR}/grafana-admin-secret.example.yaml"
fi

echo "==> Installing Prometheus + Grafana..."
helm upgrade --install "${RELEASE_NAME}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${SCRIPT_DIR}/values-minikube.yaml" \
  --wait \
  --timeout 10m

echo "==> Applying Express API ServiceMonitor..."
kubectl apply -f "${SCRIPT_DIR}/servicemonitor-express-api.yaml"

echo "==> Applying Grafana dashboard..."
kubectl apply -f "${SCRIPT_DIR}/grafana-dashboard.yaml"

echo "==> Applying Prometheus alert rules..."
kubectl apply -f "${SCRIPT_DIR}/prometheus-rules.yaml"

echo ""
echo "Prometheus + Grafana installed."
echo ""
echo "Grafana credentials are stored in secret: grafana-admin-credentials"
echo "  kubectl get secret grafana-admin-credentials -n ${NAMESPACE} -o jsonpath='{.data.admin-password}' | base64 -d"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-grafana 3000:80"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-prometheus 9090:9090"
echo ""
echo "Access Alertmanager:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-alertmanager 9093:9093"
