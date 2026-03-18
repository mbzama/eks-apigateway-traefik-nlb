#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# reset.sh  —  Wipe local Terraform state and re-provision from scratch
#
# USE WITH CAUTION: this destroys all local state, which means Terraform
# loses track of any existing AWS resources. Only run this on a clean
# environment or after `terraform destroy` has completed successfully.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Cleaning up local Terraform state and cache..."

# Remove initialised provider plugins and modules
rm -rf "$SCRIPT_DIR/.terraform"

# Remove state files
rm -f "$SCRIPT_DIR/terraform.tfstate"
rm -f "$SCRIPT_DIR/terraform.tfstate.backup"

# Remove any crash logs
rm -f "$SCRIPT_DIR/crash.log"

echo "    .terraform/           removed"
echo "    terraform.tfstate     removed"
echo "    terraform.tfstate.backup removed"

echo ""
echo "==> Starting infrastructure provisioning..."
bash "$SCRIPT_DIR/create.sh"
