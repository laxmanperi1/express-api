#!/usr/bin/env bash
set -euo pipefail

# Bootstrap ArgoCD GitOps from GitHub repo:
#   https://github.com/laxmanperi1/express-api.git

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Applying ArgoCD AppProject and root Application..."
kubectl apply -k "${ROOT_DIR}/argocd/"

echo "==> Waiting for child Applications to appear..."
for app in express-api-dev kube-prometheus-stack monitoring-config; do
  for _ in $(seq 1 30); do
    if kubectl get application "${app}" -n "${ARGOCD_NAMESPACE}" &>/dev/null; then
      echo "  Found: ${app}"
      break
    fi
    sleep 2
  done
done

echo ""
echo "ArgoCD GitOps bootstrap applied."
echo ""
echo "Repo:  https://github.com/laxmanperi1/express-api.git"
echo "Branch: main"
echo ""
echo "Check status:"
echo "  kubectl get applications -n ${ARGOCD_NAMESPACE}"
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
