FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    git \
    openssh-client \
    bash \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

ARG TERRAFORM_VERSION=1.8.5
RUN curl -fsSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip -o /tmp/terraform.zip -d /usr/local/bin \
    && rm -f /tmp/terraform.zip

RUN pip3 install --no-cache-dir ansible boto3

RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

RUN curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl

WORKDIR /workspace
