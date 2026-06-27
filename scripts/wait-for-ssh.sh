#!/usr/bin/env bash
# Wait until all K8s nodes accept SSH (run after terraform apply + inventory generation).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

cd "${ANSIBLE_DIR}"

echo "Waiting for SSH on all inventory hosts..."
ansible all \
  -m wait_for_connection \
  -a "timeout=300 delay=10 sleep=5" \
  --private-key="${SSH_KEY}"

echo "All nodes reachable via SSH."
