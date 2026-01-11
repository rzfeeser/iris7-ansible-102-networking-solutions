#!/usr/bin/env bash
set -euo pipefail

# Teardown script for IRIS7 Ansible Docker Lab
# This removes:
# - Containers: luke, hansolo, chewie
# - Docker network: ansiblelab
# It does NOT remove:
# - SSH keys
# - Docker images (unless you choose to uncomment that section)

NET_NAME="ansiblelab"
CONTAINERS=("luke" "hansolo" "chewie")

log() {
  printf "\n[%s] %s\n" "$(date +'%H:%M:%S')" "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Determine whether docker needs sudo
if need_cmd docker && docker info >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi

log "Starting teardown of Ansible Docker lab resources."

# -----------------------------
# Remove containers
# -----------------------------
for c in "${CONTAINERS[@]}"; do
  if ${DOCKER} ps -a --format '{{.Names}}' | grep -qx "$c"; then
    log "Stopping and removing container '$c'. This frees the container name and IP."
    ${DOCKER} rm -f "$c" >/dev/null
  else
    log "Container '$c' not found. Skipping."
  fi
done

# -----------------------------
# Remove Docker network
# -----------------------------
if ${DOCKER} network inspect "${NET_NAME}" >/dev/null 2>&1; then
  log "Removing Docker network '${NET_NAME}'. This releases the static subnet."
  ${DOCKER} network rm "${NET_NAME}" >/dev/null
else
  log "Docker network '${NET_NAME}' not found. Skipping."
fi

# -----------------------------
# Optional image cleanup
# -----------------------------
# Uncomment this section if you also want to remove the custom images.
# Leaving them in place speeds up re-deployments.

# IMAGES=(
#   "ansiblelab-ubuntu-ssh:22.04"
#   "ansiblelab-centos-ssh:stream9"
# )
#
# for img in "${IMAGES[@]}"; do
#   if ${DOCKER} images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$img"; then
#     log "Removing image '$img'."
#     ${DOCKER} rmi "$img" >/dev/null
#   fi
# done

# -----------------------------
# Summary
# -----------------------------
cat <<EOF

========================================
Teardown Complete
========================================

Removed:
- Containers: luke, hansolo, chewie
- Docker network: ${NET_NAME}

Preserved:
- SSH keys in ~/.ssh
- Docker images (unless you opted to remove them)

You can safely re-run the deployment script at any time.
If docker was installed by the deployment script, it was NOT removed.

EOF

