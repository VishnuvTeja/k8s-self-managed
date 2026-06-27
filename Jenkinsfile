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
        IMAGE_NAME = 'k8s-jenkins-toolbox'
        SSH_CREDS_ID = 'k8s-ssh-key'
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

        stage('Build Tool Image') {
            steps {
                sh '''
                    docker build -t "${IMAGE_NAME}" .
                '''
            }
        }

        stage('Terraform Init') {
            when {
                expression { !params.SKIP_TERRAFORM }
            }
            steps {
                sh '''
                    docker run --rm \
                      -v "$PWD:/workspace" \
                      -w /workspace/${TF_DIR} \
                      -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                      "${IMAGE_NAME}" \
                      sh -c "if [ -f backend.hcl ]; then terraform init -backend-config=backend.hcl; else echo 'WARNING: backend.hcl not found — using local state'; terraform init; fi"
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
                    docker run --rm \
                      -v "$PWD:/workspace" \
                      -w /workspace/${TF_DIR} \
                      -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                      "${IMAGE_NAME}" \
                      sh -c "terraform plan -out=tfplan"
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
                sh """
                    docker run --rm \
                      -v "$PWD:/workspace" \
                      -w /workspace/${TF_DIR} \
                      -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                      "${IMAGE_NAME}" \
                      sh -c "if [ '${params.AUTO_APPROVE}' = 'true' ]; then terraform apply -auto-approve tfplan; else terraform apply tfplan; fi"
                """
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
                    docker run --rm \
                      -v "$PWD:/workspace" \
                      -w /workspace/${TF_DIR} \
                      -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                      "${IMAGE_NAME}" \
                      sh -c "terraform destroy -auto-approve"
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
                    docker run --rm \
                      -v "$PWD:/workspace" \
                      -w /workspace \
                      -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                      "${IMAGE_NAME}" \
                      sh -c "bash scripts/generate-inventory.sh"
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
                        chmod 600 "${SSH_KEY_FILE}"
                        docker run --rm \
                          -v "$PWD:/workspace" \
                          -w /workspace \
                          -v "${SSH_KEY_FILE}:${SSH_KEY_FILE}:ro" \
                          -e SSH_KEY_FILE="${SSH_KEY_FILE}" \
                          -e SSH_USER="${SSH_USER}" \
                          "${IMAGE_NAME}" \
                          sh -c "bash scripts/wait-for-ssh.sh"
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
                        chmod 600 "${SSH_KEY_FILE}"
                        docker run --rm \
                          -v "$PWD:/workspace" \
                          -w /workspace/${ANSIBLE_DIR} \
                          -v "${SSH_KEY_FILE}:${SSH_KEY_FILE}:ro" \
                          -e SSH_KEY_FILE="${SSH_KEY_FILE}" \
                          -e SSH_USER="${SSH_USER}" \
                          "${IMAGE_NAME}" \
                          sh -c "ansible all -m ping --private-key='${SSH_KEY_FILE}'"
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
                        chmod 600 "${SSH_KEY_FILE}"
                        docker run --rm \
                          -v "$PWD:/workspace" \
                          -w /workspace/${ANSIBLE_DIR} \
                          -v "${SSH_KEY_FILE}:${SSH_KEY_FILE}:ro" \
                          -e SSH_KEY_FILE="${SSH_KEY_FILE}" \
                          -e SSH_USER="${SSH_USER}" \
                          "${IMAGE_NAME}" \
                          sh -c "ansible-playbook playbook.yml --private-key='${SSH_KEY_FILE}'"
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
                        chmod 600 "${SSH_KEY_FILE}"
                        docker run --rm \
                          -v "$PWD:/workspace" \
                          -w /workspace \
                          -v "${SSH_KEY_FILE}:${SSH_KEY_FILE}:ro" \
                          -e SSH_KEY_FILE="${SSH_KEY_FILE}" \
                          -e SSH_USER="${SSH_USER}" \
                          "${IMAGE_NAME}" \
                          sh -c "MASTER_IP=$(cd terraform && terraform output -raw master_public_ip); ssh -i '${SSH_KEY_FILE}' -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} 'kubectl get nodes -o wide'"
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
