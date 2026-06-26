#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"

echo "==> Checking cert-manager..."
if ! kubectl get crd certificates.cert-manager.io &>/dev/null; then
  echo "Installing cert-manager..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
  kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
  kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s
fi

echo "==> Labeling ingress-nginx namespace (for NetworkPolicy)..."
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite 2>/dev/null || true

echo "==> Building Docker image..."
docker build -t "express-api:${IMAGE_TAG}" "${ROOT_DIR}"

echo "==> Loading image into minikube..."
minikube image load "express-api:${IMAGE_TAG}"

echo "==> Deploying application..."
kubectl apply -k "${ROOT_DIR}/k8s/"

echo "==> Waiting for rollout..."
kubectl rollout status deployment/express-api -n express-api --timeout=120s

echo ""
echo "Deployment complete."
echo ""
echo "Port-forward:  kubectl port-forward -n express-api svc/express-api 8080:80"
echo "Health check:  curl http://localhost:8080/health"
echo "Metrics (internal only): kubectl port-forward -n express-api svc/express-api 8080:80 && curl http://localhost:8080/metrics"
