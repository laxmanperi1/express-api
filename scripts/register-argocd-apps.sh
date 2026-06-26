#!/usr/bin/env bash
set -euo pipefail

# Apply GitOps manifests directly when ArgoCD cannot reach a remote Git repo yet.
# ArgoCD Applications are registered; sync succeeds once the repo is pushed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/laxmanperi1/express-api.git}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

render() {
  sed -e "s|__GIT_REPO_URL__|${GIT_REPO_URL}|g" "$1"
}

echo "==> Applying ArgoCD project..."
render "${ROOT_DIR}/argocd/project.yaml" | kubectl apply -f -

echo "==> Registering Git repository..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: express-api-repo
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${GIT_REPO_URL}
EOF

echo "==> Applying ArgoCD Applications..."
for app in express-api-dev.yaml express-api-prod.yaml monitoring-stack.yaml monitoring-config.yaml; do
  render "${ROOT_DIR}/argocd/apps/${app}" | kubectl apply -f -
done

render "${ROOT_DIR}/argocd/root-app.yaml" | kubectl apply -f -

echo "==> Applying manifests directly (until Git repo is reachable)..."
kubectl apply -k "${ROOT_DIR}/deploy/overlays/dev"
kubectl apply -k "${ROOT_DIR}/monitoring/manifests"

echo ""
echo "GitOps Applications registered in ArgoCD."
echo "Repo URL: ${GIT_REPO_URL}"
echo ""
echo "Next: push to GitHub, then sync in ArgoCD UI or run:"
echo "  argocd app sync express-api --force"
echo ""
kubectl get applications -n "${ARGOCD_NAMESPACE}" 2>/dev/null || true
