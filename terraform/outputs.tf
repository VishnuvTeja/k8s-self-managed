output "master_public_ip" {
  description = "Public IP of the Kubernetes control plane"
  value       = aws_instance.master.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.workers[*].public_ip
}

output "master_private_ip" {
  description = "Private IP of the Kubernetes control plane"
  value       = aws_instance.master.private_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.workers[*].private_ip
}

output "ssh_user" {
  description = "Default SSH user for Ubuntu AMI"
  value       = "ubuntu"
}

output "ansible_inventory" {
  description = "Ansible inventory (host IPs only — vars in ansible/group_vars/all.yml)"
  value       = <<-EOT
    all:
      children:
        k8s_cluster:
          children:
            masters:
              hosts:
                k8s-master:
                  ansible_host: ${aws_instance.master.public_ip}
                  node_ip: ${aws_instance.master.private_ip}
            workers:
              hosts:
                k8s-worker-1:
                  ansible_host: ${aws_instance.workers[0].public_ip}
                  node_ip: ${aws_instance.workers[0].private_ip}
                k8s-worker-2:
                  ansible_host: ${aws_instance.workers[1].public_ip}
                  node_ip: ${aws_instance.workers[1].private_ip}
  EOT
}
