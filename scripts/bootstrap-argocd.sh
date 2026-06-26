#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
LOCAL_DEV="${LOCAL_DEV:-0}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.2}"
GIT_BRANCH="${GIT_BRANCH:-main}"

usage() {
  cat <<EOF
Usage: GIT_REPO_URL=<git-url> $0

Bootstrap ArgoCD GitOps for express-api.

Required:
  GIT_REPO_URL   Git repository URL (HTTPS or SSH) that ArgoCD will sync from.
                 Example: https://github.com/your-user/express-api.git

Optional env vars:
  LOCAL_DEV=1            Use minikube mount + file:// repo (no GitHub needed)
  GIT_BRANCH             Git branch to sync (default: main)
  IMAGE_TAG              Docker image tag (default: 1.0.0)
  ARGOCD_NAMESPACE       ArgoCD namespace (default: argocd)
  ARGOCD_VERSION           ArgoCD version tag (default: v2.13.2)
  SKIP_IMAGE_BUILD       Set to 1 to skip docker build/load
  SKIP_CERT_MANAGER      Set to 1 to skip cert-manager install

Example:
  GIT_REPO_URL=https://github.com/your-user/express-api.git $0
EOF
}

if [[ -z "${GIT_REPO_URL}" && "${LOCAL_DEV}" != "1" ]]; then
  usage
  exit 1
fi

if [[ "${LOCAL_DEV}" == "1" ]]; then
  GIT_REPO_URL="file:///mnt/express-api"
  GIT_BRANCH="$(git -C "${ROOT_DIR}" branch --show-current)"
  echo "==> Local dev mode: using ${GIT_REPO_URL} (branch: ${GIT_BRANCH})"
fi

render() {
  sed -e "s|__GIT_REPO_URL__|${GIT_REPO_URL}|g" -e "s|main|${GIT_BRANCH}|g" "$1"
}

setup_local_repo_mount() {
  echo "==> Mounting local repo into minikube..."
  pkill -f "minikube mount ${ROOT_DIR}:/mnt/express-api" 2>/dev/null || true
  minikube mount "${ROOT_DIR}:/mnt/express-api" &
  MOUNT_PID=$!
  sleep 5

  echo "==> Patching ArgoCD repo-server to access mounted repo..."
  kubectl patch deployment argocd-repo-server -n "${ARGOCD_NAMESPACE}" --type=json -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"local-repo","hostPath":{"path":"/mnt/express-api","type":"Directory"}}},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"local-repo","mountPath":"/mnt/express-api","readOnly":true}}
  ]' 2>/dev/null || true

  kubectl rollout status deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout=120s
  echo "${MOUNT_PID}" > /tmp/minikube-mount-express-api.pid
}

echo "==> Installing cert-manager..."
if [[ "${SKIP_CERT_MANAGER:-0}" != "1" ]]; then
  if ! kubectl get crd certificates.cert-manager.io &>/dev/null; then
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml"
    kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=180s
    kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=180s
  fi
fi

echo "==> Labeling ingress-nginx namespace (for NetworkPolicy)..."
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite 2>/dev/null || true

if [[ "${SKIP_IMAGE_BUILD:-0}" != "1" ]]; then
  echo "==> Building and loading Docker image..."
  docker build -t "express-api:${IMAGE_TAG}" "${ROOT_DIR}"
  minikube image load "express-api:${IMAGE_TAG}"
fi

echo "==> Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for=condition=Available deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s

if [[ "${LOCAL_DEV}" == "1" ]]; then
  setup_local_repo_mount
fi

echo "==> Applying ArgoCD project..."
render "${ROOT_DIR}/argocd/project.yaml" | kubectl apply -f -

echo "==> Registering Git repository with ArgoCD..."
if [[ "${GIT_REPO_URL}" == file://* ]]; then
  echo "Using local file repository (no remote secret needed)."
elif [[ "${GIT_REPO_URL}" == git@* ]]; then
  echo "SSH repo URL detected. Ensure your SSH key is added to ArgoCD:"
  echo "  argocd repo add ${GIT_REPO_URL} --ssh-private-key-path ~/.ssh/id_rsa"
else
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
fi

echo "==> Bootstrapping root Application (app-of-apps)..."
render "${ROOT_DIR}/argocd/root-app.yaml" | kubectl apply -f -

echo "==> Waiting for express-api Application to be created..."
for _ in $(seq 1 30); do
  if kubectl get application express-api -n "${ARGOCD_NAMESPACE}" &>/dev/null; then
    break
  fi
  sleep 2
done

echo "==> Syncing applications..."
if command -v argocd &>/dev/null; then
  argocd login --core
  argocd app sync express-api-root --force
  argocd app wait express-api-root --health --timeout 300
  argocd app sync express-api --force || true
  argocd app sync kube-prometheus-stack --force || true
  argocd app sync monitoring-config --force || true
else
  echo "argocd CLI not found. Trigger sync from the UI or install the CLI:"
  echo "  brew install argocd"
fi

echo ""
echo "GitOps bootstrap complete."
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "  URL: https://localhost:8080"
echo ""
echo "ArgoCD admin password:"
echo "  kubectl get secret argocd-initial-admin-secret -n ${ARGOCD_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Applications:"
echo "  kubectl get applications -n ${ARGOCD_NAMESPACE}"
echo ""
echo "IMPORTANT: Push this repo to ${GIT_REPO_URL} before expecting a successful sync."
fi
