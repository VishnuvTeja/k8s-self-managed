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
        TF_DIR             = 'terraform'
        ANSIBLE_DIR        = 'ansible'
        // Jenkins credential IDs — update to match your Jenkins setup
        AWS_CREDS_ID       = 'aws-creds'
        SSH_CREDS_ID       = 'k8s-ssh-key'
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

        stage('Terraform Init') {
            when {
                expression { !params.SKIP_TERRAFORM }
            }
            steps {
                    dir("${TF_DIR}") {
                        sh '''
                            if [ -f backend.hcl ]; then
                              terraform init -backend-config=backend.hcl
                            else
                              echo "WARNING: backend.hcl not found — using local state"
                              terraform init
                            fi
                        '''
                    }
                }
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    dir("${TF_DIR}") {
                        sh 'terraform plan -out=tfplan'
                    }
                }
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    dir("${TF_DIR}") {
                        sh """
                            if [ "${params.AUTO_APPROVE}" = "true" ]; then
                              terraform apply -auto-approve tfplan
                            else
                              terraform apply tfplan
                            fi
                        """
                    }
                }
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    dir("${TF_DIR}") {
                        sh 'terraform destroy -auto-approve'
                    }
                }
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh 'bash scripts/generate-inventory.sh'
                }
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
                        export SSH_KEY="${SSH_KEY_FILE}"
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
                    dir("${ANSIBLE_DIR}") {
                        sh 'ansible all -m ping --private-key="${SSH_KEY_FILE}"'
                    }
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
                    dir("${ANSIBLE_DIR}") {
                        sh 'ansible-playbook playbook.yml --private-key="${SSH_KEY_FILE}"'
                    }
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
                        MASTER_IP=$(cd terraform && terraform output -raw master_public_ip)
                        ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} \
                          "kubectl get nodes -o wide"
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
