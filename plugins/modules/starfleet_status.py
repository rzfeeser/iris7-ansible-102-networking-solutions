# plugins/modules/starfleet_status.py
#!/usr/bin/python

from __future__ import annotations
from ansible.module_utils.basic import AnsibleModule
import os

DOCUMENTATION = r"""
---
module: starfleet_status
short_description: Create/update a Starfleet-style status file (demo module)
description:
  - Creates or updates a status file with Starfleet-themed fields.
  - Demonstrates idempotence and structured module returns.
options:
  path:
    description: Destination path for the status file.
    required: true
    type: str
  ship:
    description: Ship name.
    required: true
    type: str
  registry:
    description: Ship registry identifier.
    required: true
    type: str
  alert_level:
    description: Alert level.
    required: false
    type: str
    default: green
    choices: [green, yellow, red]
  captain:
    description: Captain name.
    required: false
    type: str
    default: Unknown
author:
  - You
"""

RETURN = r"""
changed:
  description: Whether the module made a change.
  type: bool
msg:
  description: Human-readable message.
  type: str
written_path:
  description: File path written/verified.
  type: str
content:
  description: Final rendered content.
  type: str
"""

def build_content(ship: str, registry: str, alert_level: str, captain: str) -> str:
  return (
    "STARFLEET STATUS REPORT\n"
    "======================\n"
    f"SHIP        : {ship}\n"
    f"REGISTRY    : {registry}\n"
    f"CAPTAIN     : {captain}\n"
    f"ALERT LEVEL : {alert_level.upper()}\n"
  )

def main() -> None:
  module = AnsibleModule(
    argument_spec=dict(
      path=dict(type="str", required=True),
      ship=dict(type="str", required=True),
      registry=dict(type="str", required=True),
      alert_level=dict(type="str", default="green", choices=["green", "yellow", "red"]),
      captain=dict(type="str", default="Unknown"),
    ),
    supports_check_mode=True,
  )

  path = module.params["path"]
  desired = build_content(
    module.params["ship"],
    module.params["registry"],
    module.params["alert_level"],
    module.params["captain"],
  )

  existing = ""
  if os.path.exists(path):
    try:
      with open(path, "r", encoding="utf-8") as f:
        existing = f.read()
    except Exception as e:
      module.fail_json(msg=f"Failed to read {path}: {e}")

  changed = existing != desired

  if module.check_mode:
    module.exit_json(
      changed=changed,
      msg="Check mode: would update status file." if changed else "Check mode: status already correct.",
      written_path=path,
      content=desired,
    )

  if changed:
    try:
      with open(path, "w", encoding="utf-8") as f:
        f.write(desired)
    except Exception as e:
      module.fail_json(msg=f"Failed to write {path}: {e}")

  module.exit_json(
    changed=changed,
    msg="Status file updated." if changed else "Status file already correct.",
    written_path=path,
    content=desired,
  )

if __name__ == "__main__":
  main()
