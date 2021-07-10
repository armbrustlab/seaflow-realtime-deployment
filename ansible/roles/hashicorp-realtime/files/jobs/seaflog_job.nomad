job "seaflog_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/15 * * * * *"  // every 15 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

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

    task "seaflog_task" {
      driver = "exec"

      user = "vagrant"

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

CRUISE="{{ key "cruise/name" }}"
START="{{ key "cruise/start" }}"
END="{{ key "cruise/end" }}"

seaflog --version

seaflog \
  --filetype SeaFlowInstrumentLog \
  --project "${CRUISE}" \
  --description "SeaFlow Instrument Log data for ${CRUISE} bewteen ${START} and ${END}" \
  --earliest "${START}" \
  --latest "${END}" \
  --logfile "/jobs_data/seaflow-transfer/${CRUISE}/SFlog.txt" \
  --outfile "/jobs_data/seaflog/${CRUISE}/${CRUISE}.tsdata" \
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
