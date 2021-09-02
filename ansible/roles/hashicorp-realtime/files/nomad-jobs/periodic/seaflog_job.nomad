variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "seaflog_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/15 * * * *"  // every 15 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

  parameterized {
    meta_required = ["instrument"]
  }

  # No restart attempts
  reschedule {
    attempts = 0
    unlimited = false
  }

  group "seaflog_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    task "parse" {
      driver = "exec"

      user = var.realtime_user

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

set -e

cruise="{{ key "cruise/name" }}"
start="{{ key "cruise/start" }}"
end="{{ key "cruise/end" }}"
instrument="${NOMAD_META_instrument}"

seaflog --version

seaflog \
  --filetype SeaFlowInstrumentLog \
  --project "${cruise}" \
  --description "SeaFlow Instrument Log data for ${cruise} bewteen ${start} and ${end}" \
  --earliest "${start}" \
  --latest "${END}" \
  --logfile "/jobs_data/seaflow-transfer/${cruise}/${instrument}/SFlog.txt" \
  --outfile "/jobs_data/seaflog/${cruise}/${instrument}/${cruise}.tsdata" \
  --quiet
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
