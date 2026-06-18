# Kubernetes on AWS Frankfurt — Terraform + Ansible

Provisions **3 EC2 instances** in `eu-central-1` (Frankfurt) and configures a **1 master + 2 worker** Kubernetes cluster with kubeadm.

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
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.14
- AWS CLI configured (`aws configure`) with credentials that can create EC2, VPC, and security groups
- SSH key pair (default: `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)

## Step 1 — Provision EC2 with Terraform

```bash
cd terraform

# Copy and edit variables (add your SSH public key)
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform plan
terraform apply
```

After apply, save the Ansible inventory:

```bash
terraform output -raw ansible_inventory > ../ansible/inventory/hosts.yml
```

Or note the IPs manually:

```bash
terraform output master_public_ip
terraform output worker_public_ips
```

## Step 2 — Configure Kubernetes with Ansible

Wait ~60 seconds after EC2 launch for cloud-init to finish, then:

```bash
cd ../ansible

# Test connectivity
ansible all -m ping

# Run full cluster setup
ansible-playbook playbook.yml
```

## Step 3 — Verify cluster

SSH into the master:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<master-public-ip>
kubectl get nodes
```

Expected output — 3 nodes (master may show as control-plane, workers as Ready):

```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   ...   v1.29.x
k8s-worker-1   Ready    <none>          ...   v1.29.x
k8s-worker-2   Ready    <none>          ...   v1.29.x
```

## What gets installed

| Component | Version |
|-----------|---------|
| OS | Ubuntu 22.04 LTS |
| Kubernetes | 1.29 (kubeadm) |
| Container runtime | containerd |
| CNI | Calico |

## Security notes

- `allowed_ssh_cidr` defaults to `0.0.0.0/0` — restrict to your IP in production
- API server port 6443 is open to the internet — use a bastion or VPN for production
- Instance type `t3.medium` (2 vCPU, 4 GB RAM) is the minimum recommended for kubeadm

## Cleanup

```bash
cd terraform
terraform destroy
```

## Project structure

```
k8s-aws-frankfurt/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg
    ├── playbook.yml
    ├── inventory/hosts.yml
    └── roles/
        ├── common/   # containerd, kubeadm packages, sysctl
        ├── master/   # kubeadm init, Calico CNI
        └── worker/   # kubeadm join
```
