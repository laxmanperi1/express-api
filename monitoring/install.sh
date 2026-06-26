#!/usr/bin/env bash
set -euo pipefail
echo "monitoring/install.sh is deprecated. Monitoring is now managed by ArgoCD."
echo "Use: GIT_REPO_URL=https://github.com/your-user/express-api.git ./scripts/bootstrap-argocd.sh"
exit 1
