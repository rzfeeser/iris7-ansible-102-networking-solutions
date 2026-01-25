#!/usr/bin/env bash
set -euo pipefail

# IRIS7 local Ansible lab: 3 Docker containers with SSH + static IPs
# - luke      (Ubuntu)
# - hansolo   (Ubuntu)
# - chewie    (CentOS Stream 9 - RHEL-like community distro)
#
# What this script does (high level):
# 1) Ensures Docker is installed and running (optional auto-install).
# 2) Creates a dedicated Docker network with a predictable subnet.
# 3) Creates an SSH keypair if missing and injects the public key into all containers.
# 4) Builds small images with OpenSSH server enabled.
# 5) Runs containers with static IPs and prints SSH + Ansible details.

# -----------------------------
# Settings (adjust if you want)
# -----------------------------
NET_NAME="ansiblelab"
SUBNET="172.28.0.0/24"
GATEWAY="172.28.0.1"

LUKE_IP="172.28.0.11"
HAN_IP="172.28.0.12"
CHEWIE_IP="172.28.0.13"

SSH_USER="ansible"
SSH_PORT="22"

KEY_DIR="${HOME}/.ssh"
KEY_PATH="${KEY_DIR}/ansible_docker_lab"
PUB_KEY_PATH="${KEY_PATH}.pub"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

need_cmd() { command -v "$1" >/dev/null 2>&1; }

log() { printf "\n[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }

# -----------------------------
# Preflight: Docker available?
# -----------------------------
if ! need_cmd docker; then
  log "Docker not found. Installing docker.io via apt (requires sudo). This will add Docker to your system packages."
  sudo apt update
  sudo apt install -y docker.io
fi

log "Ensuring Docker service is running. This is required to build images and launch containers."
sudo systemctl enable --now docker >/dev/null 2>&1 || true

if ! docker info >/dev/null 2>&1; then
  log "Docker daemon is not accessible to the current user. Adding you to the docker group so you can run docker without sudo."
  sudo usermod -aG docker "${USER}" || true
  echo
  echo "NOTE: You may need to log out and back in for group membership to apply."
  echo "For now, the script will continue using sudo for docker commands."
  DOCKER="sudo docker"
else
  DOCKER="docker"
fi

# -----------------------------
# SSH key setup
# -----------------------------
log "Ensuring SSH keypair exists at ${KEY_PATH}. This key will be used by Ansible/SSH to access all containers."
mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [[ ! -f "${KEY_PATH}" || ! -f "${PUB_KEY_PATH}" ]]; then
  ssh-keygen -t ed25519 -N "" -f "${KEY_PATH}" -C "ansible-docker-lab" >/dev/null
fi

PUBKEY="$(cat "${PUB_KEY_PATH}")"

# -----------------------------
# Docker network (static IPs)
# -----------------------------
log "Ensuring Docker network '${NET_NAME}' exists with subnet ${SUBNET}. This provides predictable container IPs for Ansible."
if ! ${DOCKER} network inspect "${NET_NAME}" >/dev/null 2>&1; then
  ${DOCKER} network create \
    --driver bridge \
    --subnet "${SUBNET}" \
    --gateway "${GATEWAY}" \
    "${NET_NAME}" >/dev/null
fi

# -----------------------------
# Build SSH-enabled images
# -----------------------------
log "Creating build context. Each image includes OpenSSH server, the '${SSH_USER}' user, and your public key for passwordless login."
mkdir -p "${WORKDIR}/ubuntu" "${WORKDIR}/centos"

# Ubuntu image Dockerfile
cat > "${WORKDIR}/ubuntu/Dockerfile" <<EOF
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install SSH server and common tools. This prepares the container to be managed like a tiny VM by Ansible.
RUN apt-get update && apt-get install -y --no-install-recommends \\
    iproute2 openssh-server sudo python3 ca-certificates \\
  && rm -rf /var/lib/apt/lists/*

# Create SSH runtime directory and a non-root user. Ansible commonly uses a normal user with sudo for privilege escalation.
RUN mkdir -p /var/run/sshd \\
  && useradd -m -s /bin/bash ${SSH_USER} \\
  && echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${SSH_USER} \\
  && chmod 0440 /etc/sudoers.d/${SSH_USER}

# Add the injected public key for passwordless SSH. This lets Ansible connect without prompting for a password.
RUN mkdir -p /home/${SSH_USER}/.ssh \\
  && chmod 700 /home/${SSH_USER}/.ssh \\
  && echo '${PUBKEY}' > /home/${SSH_USER}/.ssh/authorized_keys \\
  && chmod 600 /home/${SSH_USER}/.ssh/authorized_keys \\
  && chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.ssh

# Configure sshd to allow key-based auth and keep it simple for labs. We disable password auth to avoid password management overhead.
RUN sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \\
  && sed -i 's/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \\
  && sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd","-D","-e"]
EOF

# CentOS Stream 9 (RHEL-like) image Dockerfile
cat > "${WORKDIR}/centos/Dockerfile" <<EOF
FROM quay.io/centos/centos:stream9

# Install SSH server and Python. Python is needed for most Ansible modules to work smoothly on the target.
RUN dnf -y update && dnf -y install \\
    iproute openssh-server sudo python3 \\
  && dnf clean all

# Initialize SSH host keys. Containers don't come with host keys by default, so we generate them once at build time.
RUN ssh-keygen -A

# Create a non-root user for Ansible. This mirrors typical server setups and lets you use become/sudo.
RUN useradd -m -s /bin/bash ${SSH_USER} \\
  && echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${SSH_USER} \\
  && chmod 0440 /etc/sudoers.d/${SSH_USER}

# Add your public key for passwordless login. This is the same key used for both Ubuntu containers.
RUN mkdir -p /home/${SSH_USER}/.ssh \\
  && chmod 700 /home/${SSH_USER}/.ssh \\
  && echo '${PUBKEY}' > /home/${SSH_USER}/.ssh/authorized_keys \\
  && chmod 600 /home/${SSH_USER}/.ssh/authorized_keys \\
  && chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.ssh

# Configure sshd to use key-based auth only. This keeps the lab simple and matches common Ansible practices.
RUN sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \\
  && sed -i 's/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \\
  && sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd","-D","-e"]
EOF

log "Building images. This compiles the SSH-ready container templates used for luke/hansolo (Ubuntu) and chewie (CentOS Stream)."
${DOCKER} build -t ansiblelab-ubuntu-ssh:22.04 "${WORKDIR}/ubuntu" >/dev/null
${DOCKER} build -t ansiblelab-centos-ssh:stream9 "${WORKDIR}/centos" >/dev/null

# -----------------------------
# Run containers (static IPs)
# -----------------------------
remove_if_exists() {
  local name="$1"
  if ${DOCKER} ps -a --format '{{.Names}}' | grep -qx "$name"; then
    log "Removing existing container '$name'. This prevents name/IP conflicts and makes the script rerunnable."
    ${DOCKER} rm -f "$name" >/dev/null
  fi
}

remove_if_exists "luke"
remove_if_exists "hansolo"
remove_if_exists "chewie"

log "Launching containers with static IPs on network '${NET_NAME}'. This makes inventory stable and repeatable for Ansible."
${DOCKER} run -d --name luke    --hostname luke    --network "${NET_NAME}" --ip "${LUKE_IP}"   ansiblelab-ubuntu-ssh:22.04 >/dev/null
${DOCKER} run -d --name hansolo --hostname hansolo --network "${NET_NAME}" --ip "${HAN_IP}"    ansiblelab-ubuntu-ssh:22.04 >/dev/null
${DOCKER} run -d --name chewie  --hostname chewie  --network "${NET_NAME}" --ip "${CHEWIE_IP}" ansiblelab-centos-ssh:stream9 >/dev/null

log "Waiting briefly for sshd to be ready. This prevents immediate connection attempts from failing while services start."
sleep 2

# -----------------------------
# Output: what to use next
# -----------------------------
cat <<EOF

========================================
Ansible Docker Lab Deployed (Ubuntu 22.04)
========================================

SSH key used (private): ${KEY_PATH}
SSH key used (public):  ${PUB_KEY_PATH}
SSH user on all containers: ${SSH_USER}

Network:
- Docker network name: ${NET_NAME}
- Subnet/Gateway: ${SUBNET} / ${GATEWAY}

Containers (name -> IP -> OS):
- luke     -> ${LUKE_IP}  -> Ubuntu 22.04
- hansolo  -> ${HAN_IP}   -> Ubuntu 22.04
- chewie   -> ${CHEWIE_IP} -> CentOS Stream 9 (RHEL-like)

Quick SSH tests (copy/paste):
- ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${LUKE_IP}
- ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${HAN_IP}
- ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${CHEWIE_IP}

Suggested Ansible inventory (INI). This uses the same key for all hosts and disables host key prompts for lab convenience:
[starwars]
luke ansible_host=${LUKE_IP}
hansolo ansible_host=${HAN_IP}
chewie ansible_host=${CHEWIE_IP}

[starwars:vars]
ansible_user=${SSH_USER}
ansible_ssh_private_key_file=${KEY_PATH}
ansible_become=true
ansible_become_method=sudo
ansible_become_flags=-H -S
ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new

Example Ansible commands:
- ansible -i inventory.ini starwars -m ping
- ansible -i inventory.ini starwars -a "uname -a"
- ansible -i inventory.ini starwars -b -m command -a "id"

Notes:
- These containers are reachable by IP from the Docker host. If you are inside another container or VM, ensure it can reach ${SUBNET}.
- If 'docker' still requires sudo for you, either re-login after group changes or prefix docker commands with sudo.

EOF

