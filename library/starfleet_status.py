# library/starfleet_status.py
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
  - Demonstrates module argument parsing, validation, idempotence, and structured returns.
options:
  path:
    description:
      - Destination file path for the status file.
    required: true
    type: str
  ship:
    description:
      - Starship name to record in the status file.
    required: true
    type: str
  registry:
    description:
      - Starship registry identifier (example: NCC-1701).
    required: true
    type: str
  alert_level:
    description:
      - Alert level to record in the status file.
    required: false
    type: str
    default: green
    choices: [green, yellow, red]
  captain:
    description:
      - Captain name to record in the status file.
    required: false
    type: str
    default: "Unknown"
author:
  - You
"""

EXAMPLES = r"""
- name: Write a status file
  starfleet_status:
    path: /tmp/starfleet-status.txt
    ship: USS Enterprise
    registry: NCC-1701
    alert_level: yellow
    captain: James T. Kirk
"""

RETURN = r"""
changed:
  description: Whether the module made a change.
  type: bool
msg:
  description: Human-readable result.
  type: str
written_path:
  description: Path to the file written/verified.
  type: str
content:
  description: Final content of the status file.
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


def run_module() -> None:
  module_args = dict(
    path=dict(type="str", required=True),
    ship=dict(type="str", required=True),
    registry=dict(type="str", required=True),
    alert_level=dict(type="str", required=False, default="green", choices=["green", "yellow", "red"]),
    captain=dict(type="str", required=False, default="Unknown"),
  )

  module = AnsibleModule(argument_spec=module_args, supports_check_mode=True)

  path = module.params["path"]
  ship = module.params["ship"]
  registry = module.params["registry"]
  alert_level = module.params["alert_level"]
  captain = module.params["captain"]

  desired = build_content(ship, registry, alert_level, captain)

  # Read existing content if present
  existing = ""
  if os.path.exists(path):
    try:
      with open(path, "r", encoding="utf-8") as f:
        existing = f.read()
    except Exception as e:
      module.fail_json(msg=f"Failed to read existing file {path}: {e}")

  changed = (existing != desired)

  if module.check_mode:
    module.exit_json(
      changed=changed,
      msg="Check mode: would update status file." if changed else "Check mode: status file already correct.",
      written_path=path,
      content=desired,
    )

  # Write only if needed (idempotence)
  if changed:
    try:
      with open(path, "w", encoding="utf-8") as f:
        f.write(desired)
    except Exception as e:
      module.fail_json(msg=f"Failed to write file {path}: {e}")

  module.exit_json(
    changed=changed,
    msg="Status file updated." if changed else "Status file already correct.",
    written_path=path,
    content=desired,
  )


def main() -> None:
  run_module()


if __name__ == "__main__":
  main()
