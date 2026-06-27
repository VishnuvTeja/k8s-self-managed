pipeline {
    agent {
        docker {
            image 'vishnuvteja/k8s-jenkins-tools:latest'
            args '-u root'
        }
    }

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
        TF_DIR             = 'terraform'
        ANSIBLE_DIR        = 'ansible'
        SSH_CREDS_ID       = 'k8s-ssh-key'
        PATH               = "/root/.local/bin:/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }

    options {
        timestamps()
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {

        // ─────────────────────────────────────────
        stage('Checkout') {
        // ─────────────────────────────────────────
            steps {
                checkout scm
            }
        }

        // ─────────────────────────────────────────
        stage('Verify Tooling') {
        // ─────────────────────────────────────────
            steps {
                sh '''
                    set -e
                    echo "=== Terraform ===" && terraform version
                    echo "=== Ansible ===" && ansible --version | head -n 1
                    echo "=== AWS CLI ===" && aws --version
                    echo "=== kubectl ===" && kubectl version --client
                '''
            }
        }

        // ─────────────────────────────────────────
        stage('Terraform Init') {
        // ─────────────────────────────────────────
            when {
                expression { !params.SKIP_TERRAFORM }
            }
            steps {
                sh '''
                    set -e
                    cd "$WORKSPACE/${TF_DIR}"
                    if [ -f backend.hcl ]; then
                        echo "Using backend.hcl for remote state"
                        terraform init -backend-config=backend.hcl
                    else
                        echo "WARNING: backend.hcl not found — using local state"
                        terraform init
                    fi
                '''
            }
        }

        // ─────────────────────────────────────────
        stage('Terraform Plan') {
        // ─────────────────────────────────────────
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                sh '''
                    set -e
                    cd "$WORKSPACE/${TF_DIR}"
                    terraform plan -out=tfplan
                '''
            }
        }

        // ─────────────────────────────────────────
        stage('Approve Terraform Apply') {
        // ─────────────────────────────────────────
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                    expression { !params.AUTO_APPROVE }
                }
            }
            steps {
                input message: 'Review the plan above. Apply Terraform?', ok: 'Apply'
            }
        }

        // ─────────────────────────────────────────
        stage('Terraform Apply') {
        // ─────────────────────────────────────────
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { !params.TERRAFORM_DESTROY }
                }
            }
            steps {
                // FIX: use a Groovy variable — single-quoted shell can't interpolate params
                script {
                    def autoApprove = params.AUTO_APPROVE
                    sh """
                        set -e
                        cd "\$WORKSPACE/\${TF_DIR}"
                        if [ "${autoApprove}" = "true" ]; then
                            echo "Auto-approve enabled — applying without prompt"
                            terraform apply -auto-approve tfplan
                        else
                            terraform apply tfplan
                        fi
                    """
                }
            }
        }

        // ─────────────────────────────────────────
        stage('Terraform Destroy') {
        // ─────────────────────────────────────────
            when {
                allOf {
                    expression { !params.SKIP_TERRAFORM }
                    expression { params.TERRAFORM_DESTROY }
                }
            }
            steps {
                // input must be BEFORE sh in the same steps block
                script {
                    input message: '⚠️  DESTROY all K8s infrastructure? This is irreversible.', ok: 'Yes, Destroy'
                    sh '''
                        set -e
                        cd "$WORKSPACE/${TF_DIR}"
                        terraform destroy -auto-approve
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        stage('Generate Ansible Inventory') {
        // ─────────────────────────────────────────
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
                    cd "$WORKSPACE"
                    bash scripts/generate-inventory.sh
                '''
            }
        }

        // ─────────────────────────────────────────
        stage('Wait for SSH') {
        // ─────────────────────────────────────────
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
                        chmod 600 "$SSH_KEY_FILE"
                        export SSH_KEY="$SSH_KEY_FILE"
                        cd "$WORKSPACE"
                        bash scripts/wait-for-ssh.sh
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        stage('Ansible Ping') {
        // ─────────────────────────────────────────
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
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE/${ANSIBLE_DIR}"
                        ansible all -m ping --private-key="$SSH_KEY_FILE"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        stage('Ansible Configure K8s') {
        // ─────────────────────────────────────────
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
                        chmod 600 "$SSH_KEY_FILE"
                        cd "$WORKSPACE/${ANSIBLE_DIR}"
                        ansible-playbook playbook.yml --private-key="$SSH_KEY_FILE" -v
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        stage('Verify Cluster') {
        // ─────────────────────────────────────────
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
                        chmod 600 "$SSH_KEY_FILE"
                        MASTER_IP=$(cd "$WORKSPACE/${TF_DIR}" && terraform output -raw master_public_ip)
                        echo "Master IP: ${MASTER_IP}"
                        ssh -i "$SSH_KEY_FILE" \
                            -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            ubuntu@${MASTER_IP} \
                            "kubectl get nodes -o wide"
                    '''
                }
            }
        }
    }

    // ─────────────────────────────────────────
    post {
    // ─────────────────────────────────────────
        success {
            echo '✅ Pipeline completed successfully.'
        }
        failure {
            echo '❌ Pipeline failed — check stage logs above.'
        }
        always {
            // FIX: use WORKSPACE-anchored path so this works reliably in post block
            sh 'rm -f "$WORKSPACE/${TF_DIR}/tfplan" || true'
        }
    }
}
