# Kubernetes on AWS Frankfurt — Terraform + Ansible + Jenkins

Provisions **3 EC2 instances** in `eu-central-1` (Frankfurt) and configures a **1 master + 2 worker** Kubernetes cluster with kubeadm. Includes **Jenkins pipeline**, **S3 remote state**, and **group_vars** for stable Ansible configuration.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  VPC 10.0.0.0/16 (eu-central-1)               │
│                                                 │
│  ┌──────────────┐  ┌──────────┐  ┌──────────┐  │
│  │ k8s-master   │  │ worker-1 │  │ worker-2 │  │
│  │ control plane│  │          │  │          │  │
│  └──────────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────┘

Jenkins EC2  ──►  Terraform (S3 state)  ──►  EC2 nodes
              ──►  Ansible (group_vars)  ──►  kubeadm cluster
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.14
- AWS CLI configured (`aws configure`) with credentials that can create EC2, VPC, S3, and DynamoDB
- SSH key pair (default: `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)

## One-time: Bootstrap remote state (S3 + DynamoDB)

Run once before using the S3 backend or Jenkins:

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit state_bucket_name — must be globally unique

terraform init
terraform apply

# Copy output into backend config
terraform output -raw backend_config_snippet > ../backend.hcl
```

Then init the main Terraform with remote state:

```bash
cd ../
terraform init -backend-config=backend.hcl
```

## Step 1 — Provision EC2 with Terraform

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
# Edit: add your SSH public key

terraform init -backend-config=backend.hcl   # or plain init for local state
terraform plan
terraform apply
```

Generate Ansible inventory (host IPs only):

```bash
bash ../scripts/generate-inventory.sh
```

Cluster variables (`pod_network_cidr`, `kubernetes_version`, etc.) load automatically from `ansible/group_vars/all.yml` — they are **not** overwritten by inventory generation.

## Step 2 — Configure Kubernetes with Ansible

```bash
bash ../scripts/wait-for-ssh.sh

cd ../ansible
ansible all -m ping
ansible-playbook playbook.yml
```

## Step 3 — Verify cluster

```bash
ssh -i ~/.ssh/id_rsa ubuntu@$(cd ../terraform && terraform output -raw master_public_ip)
kubectl get nodes
```

Expected output — 3 nodes:

```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   ...   v1.29.x
k8s-worker-1   Ready    <none>          ...   v1.29.x
k8s-worker-2   Ready    <none>          ...   v1.29.x
```

---

## Jenkins pipeline setup

### 1. Install on Jenkins EC2

```bash
sudo apt update
sudo apt install -y git terraform ansible awscli
```

Or use a Jenkins agent in the same AWS VPC as the K8s nodes.

### 2. Create Jenkins credentials

| Credential ID | Type | Value |
|---------------|------|-------|
| `aws-creds` | AWS Credentials | Access key + secret (or use IAM instance profile on Jenkins EC2) |
| `k8s-ssh-key` | SSH Username with private key | User: `ubuntu`, Key: your private key matching Terraform `ssh_public_key` |

Update credential IDs in `Jenkinsfile` if you use different names.

### 3. Create pipeline job

1. Jenkins → **New Item** → **Pipeline**
2. **Pipeline script from SCM** → point to your GitHub repo
3. Script path: `Jenkinsfile`
4. Ensure `terraform/backend.hcl` exists on the Jenkins agent (from bootstrap step)
5. Ensure `terraform/terraform.tfvars` exists (use Jenkins **Secret file** credential or pre-place on agent)

### 4. Pipeline parameters

| Parameter | Purpose |
|-----------|---------|
| `AUTO_APPROVE` | Skip manual approval gate before `terraform apply` |
| `SKIP_TERRAFORM` | Re-run Ansible only on existing nodes |
| `SKIP_ANSIBLE` | Provision infra only, skip K8s config |
| `TERRAFORM_DESTROY` | Tear down all infrastructure |

### 5. Pipeline stages

```
Checkout → Terraform Init → Plan → [Approve] → Apply
         → Generate Inventory → Wait for SSH → Ansible Ping
         → Ansible Configure K8s → Verify (kubectl get nodes)
```

### 6. Recommended: IAM instance profile on Jenkins EC2

Instead of storing AWS keys in Jenkins, attach an IAM role to the Jenkins EC2 with permissions for EC2, VPC, S3, and DynamoDB. Remove the `withCredentials` AWS block or use the instance profile automatically.

---

## What gets installed

| Component | Version |
|-----------|---------|
| OS | Ubuntu 22.04 LTS |
| Kubernetes | 1.29 (kubeadm) |
| Container runtime | containerd |
| CNI | Calico |
| Pod network CIDR | 10.244.0.0/16 (`group_vars/all.yml`) |

## Security notes

- `allowed_ssh_cidr` defaults to `0.0.0.0/0` — restrict to your IP in production
- API server port 6443 is open to the internet — use a bastion or VPN for production
- Instance type `t3.medium` (2 vCPU, 4 GB RAM) is the minimum recommended for kubeadm
- Do not commit `terraform.tfvars`, `backend.hcl`, or SSH private keys

## Cleanup

```bash
cd terraform
terraform destroy
```

## Project structure

```
k8s-aws-frankfurt/
├── Jenkinsfile
├── scripts/
│   ├── generate-inventory.sh
│   └── wait-for-ssh.sh
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── backend.tf
│   ├── backend.hcl.example
│   ├── terraform.tfvars.example
│   └── bootstrap/          # one-time S3 + DynamoDB setup
└── ansible/
    ├── ansible.cfg
    ├── playbook.yml
    ├── group_vars/
    │   └── all.yml         # pod_network_cidr, k8s version, etc.
    ├── inventory/hosts.yml # host IPs (regenerated from Terraform)
    └── roles/
        ├── common/
        ├── master/
        └── worker/
```
