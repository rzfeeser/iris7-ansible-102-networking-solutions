#!/bin/bash
# system_check.sh
# Simple demo script for ansible.builtin.script

echo "=== SYSTEM CHECK ==="
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Uptime:"
uptime

if [ $# -gt 0 ]; then
  echo "Arguments passed to script:"
  for arg in "$@"; do
    echo " - $arg"
  done
fi
