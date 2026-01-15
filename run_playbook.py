# run_playbook.py
import ansible_runner

print("Running Ansible playbook via ansible-runner...\n")

r = ansible_runner.run(
    private_data_dir=".",
    playbook="hello-runner.yml",
)

print("Run complete")
print(f"Status: {r.status}")
print(f"RC: {r.rc}")

print("\nTask Events:")
for event in r.events:
    if event.get("event") == "runner_on_ok":
        task = event["event_data"].get("task", "unknown")
        host = event["event_data"].get("host", "unknown")
        result = event["event_data"].get("res", {})
        print(f" - Task '{task}' succeeded on {host}: {result}")
