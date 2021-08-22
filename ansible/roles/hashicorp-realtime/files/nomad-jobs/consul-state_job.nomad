job "consul-state_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/1 * * * *"  // every 1 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

  # No restart attempts
  reschedule {
    attempts = 0
    unlimited = false
  }

  group "consul-state_group" {
    count = 1

    task "consul-state_task" {
      driver = "raw_exec"

      user = "ubuntu"

      template {
        data = <<EOH
#!/usr/bin/env bash

if [[ -f /etc/realtime/consul-state.json ]]; then
  echo "Importing consul state"
  # Base64 encode string "value" attributes and pipe to consul
  jq '[ .[] | .value = (.value | @base64) ]' < /etc/realtime/consul-state.json | consul kv import -
else
  echo "/etc/realtime/consul-state.json does not exist, skipping consul state import"
fi
        EOH
        destination = "local/run.sh"
        perms = "755"
        change_mode = "restart"
      }

      config {
        command = "/local/run.sh"
      }
    }
  }
}
