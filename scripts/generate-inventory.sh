#!/usr/bin/env bash
# Write Terraform host IPs into Ansible inventory.
# Cluster variables are loaded from ansible/group_vars/all.yml.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
INV_FILE="${ROOT_DIR}/ansible/inventory/hosts.yml"

cd "${TF_DIR}"
terraform output -raw ansible_inventory > "${INV_FILE}"

echo "Inventory written to ${INV_FILE}"
echo "Cluster vars loaded from ansible/group_vars/all.yml"
