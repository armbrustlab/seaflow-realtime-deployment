job "seaflow-transfer_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "*/15 * * * *"  // every 15 minutes
    prohibit_overlap = true
    time_zone = "UTC"
  }

  # No restart attempts
  reschedule {
    attempts = 0
    unlimited = false
  }

  group "seaflow-transfer_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    volume "seaflow_data" {
      type = "host"
      source = "seaflow_data"
    }

    task "seaflow-transfer_copy_task" {
      driver = "exec"

      user = "ubuntu"

      volume_mount {
        volume = "seaflow_data"
        destination = "/seaflow_data"
      }

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash
# Script for atomic copy of SeaFlow instrument log file

OUTDIR="/jobs_data/seaflow-transfer/{{ key "cruise/name" }}"

[[ -d "${OUTDIR}" ]] || mkdir -p "${OUTDIR}"
cp "/seaflow_data/logs/SFlog.txt" "${OUTDIR}/.SFlog.txt" || exit 1
mv "${OUTDIR}/.SFlog.txt" "${OUTDIR}/SFlog.txt" || exit 1
        EOH
        destination = "local/cp.sh"
        change_mode = "restart"
      }

      config {
        command = "bash"
        args = [
          "/local/cp.sh"
        ]
      }

      lifecycle {
        hook = "prestart"
        sidecar = false
      }
    }

    task "seaflow-transfer_task" {
      driver = "exec"

      user = "ubuntu"

      volume_mount {
        volume = "seaflow_data"
        destination = "/seaflow_data"
      }

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

OUTDIR="/jobs_data/seaflow-transfer/{{ key "cruise/name" }}/evt"
START="{{ key "cruise/start" }}"

seaflow-transfer -version

seaflow-transfer \
  -srcRoot /seaflow_data/datafiles/evt \
  -dstRoot "${OUTDIR}" \
  -start "${START}"
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
