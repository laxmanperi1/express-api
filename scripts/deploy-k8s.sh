#!/usr/bin/env bash
set -euo pipefail
echo "deploy-k8s.sh is deprecated. Use GitOps bootstrap instead:"
echo "  GIT_REPO_URL=https://github.com/your-user/express-api.git ./scripts/bootstrap-argocd.sh"
exit 1
