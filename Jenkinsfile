pipeline {
    agent any

    parameters {
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Skip manual approval and run terraform apply -auto-approve'
        )
        booleanParam(
            name: 'SKIP_TERRAFORM',
            defaultValue: false,
            description: 'Skip Terraform (Ansible-only re-run on existing nodes)'
        )
        booleanParam(
            name: 'SKIP_ANSIBLE',
            defaultValue: false,
            description: 'Skip Ansible (infra-only run)'
        )
        booleanParam(
            name: 'TERRAFORM_DESTROY',
            defaultValue: false,
            description: 'Destroy all infrastructure (requires AUTO_APPROVE)'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'eu-central-1'
        TF_DIR = 'terraform'
        ANSIBLE_DIR = 'ansible'
        SSH_CREDS_ID = 'k8s-ssh-key'
        PATH = "${env.HOME}/.local/bin:${env.HOME}/bin:${env.PATH}"
    }

    options {
        timestamps()
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Tools') {
            steps {
                sh '''
                    set -e
                    mkdir -p "$HOME/bin"
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

                    if ! command -v terraform >/dev/null 2>&1; then
                        curl -fsSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip
                        unzip -o /tmp/terraform.zip -d "$HOME/bin"
                        rm -f /tmp/terraform.zip
                    fi

                    if ! command -v ansible-playbook >/dev/null 2>&1; then
                        python3 -m pip install --user ansible boto3
                    fi

                    if ! command -v aws >/dev/null 2>&1; then
                        curl -fsSLo /tmp/awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
                        unzip -q /tmp/awscliv2.zip -d /tmp
                        /tmp/aws/install -i "$HOME/aws-cli" -b "$HOME/bin"
                        rm -rf /tmp/aws /tmp/awscliv2.zip
                    fi

                    if ! command -v kubectl >/dev/null 2>&1; then
                        curl -fsSLo "$HOME/bin/kubectl" https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
                        chmod +x "$HOME/bin/kubectl"
                    fi

                    chmod +x "$HOME/bin/terraform" "$HOME/bin/kubectl" 2>/dev/null || true
                    terraform version
                    ansible --version | head -n 1
                    aws --version
                    kubectl version --client --short
                '''
            }
        }

        stage('Terraform Init') {
            when {
                expression { !params.SKIP_TERRAFORM }
            }
            steps {
                sh '''
                    set -e
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                    cd "$WORKSPACE/${TF_DIR}"
                    if [ -f backend.hcl ]; then
                      terraform init -backend-config=backend.hcl
                    else
                      echo "WARNING: backend.hcl not found — using local state"
                      terraform init
                    fi
                '''
            }
        }

        stage('Terraform Plan') {
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                sh '''
                    set -e
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                    cd "$WORKSPACE/${TF_DIR}"
                    terraform plan -out=tfplan
                '''
            }
        }

        stage('Approve Terraform Apply') {
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                    expression { !params.AUTO_APPROVE }
                }
            }
            steps {
                input message: 'Apply Terraform plan?', ok: 'Apply'
            }
        }

        stage('Terraform Apply') {
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                sh '''
                    set -e
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                    cd "$WORKSPACE/${TF_DIR}"
                    if [ '${params.AUTO_APPROVE}' = 'true' ]; then
                      terraform apply -auto-approve tfplan
                    else
                      terraform apply tfplan
                    fi
                '''
            }
        }

        stage('Terraform Destroy') {
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { params.TERRAFORM_DESTROY }
                }
            }
            steps {
                input message: 'DESTROY all K8s infrastructure?', ok: 'Destroy'
                sh '''
                    set -e
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                    cd "$WORKSPACE/${TF_DIR}"
                    terraform destroy -auto-approve
                '''
            }
        }

        stage('Generate Ansible Inventory') {
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                    expression { !params.SKIP_ANSIBLE }
                }
            }
            steps {
                sh '''
                    set -e
                    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                    cd "$WORKSPACE"
                    bash scripts/generate-inventory.sh
                '''
            }
        }

        stage('Wait for SSH') {
            when {
                allOf {
                    expression { !params.SKIP_ANSIBLE }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: "${SSH_CREDS_ID}",
                    keyFileVariable: 'SSH_KEY_FILE',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -e
                        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE"
                        export SSH_KEY="$SSH_KEY_FILE"
                        bash scripts/wait-for-ssh.sh
                    '''
                }
            }
        }

        stage('Ansible Ping') {
            when {
                allOf {
                    expression { !params.SKIP_ANSIBLE }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: "${SSH_CREDS_ID}",
                    keyFileVariable: 'SSH_KEY_FILE',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -e
                        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE/${ANSIBLE_DIR}"
                        ansible all -m ping --private-key="$SSH_KEY_FILE"
                    '''
                }
            }
        }

        stage('Ansible Configure K8s') {
            when {
                allOf {
                    expression { !params.SKIP_ANSIBLE }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: "${SSH_CREDS_ID}",
                    keyFileVariable: 'SSH_KEY_FILE',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -e
                        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE/${ANSIBLE_DIR}"
                        ansible-playbook playbook.yml --private-key="$SSH_KEY_FILE"
                    '''
                }
            }
        }

        stage('Verify Cluster') {
            when {
                allOf {
                    expression { !params.SKIP_ANSIBLE }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: "${SSH_CREDS_ID}",
                    keyFileVariable: 'SSH_KEY_FILE',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -e
                        export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE"
                        MASTER_IP=$(cd terraform && terraform output -raw master_public_ip)
                        ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "kubectl get nodes -o wide"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed — check stage logs above.'
        }
        always {
            dir("${TF_DIR}") {
                sh 'rm -f tfplan || true'
            }
        }
    }
}
