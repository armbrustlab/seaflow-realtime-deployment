variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "seaflow-transfer_job" {
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

  reschedule {
    attempts = 1
    unlimited = false
  }

  group "seaflow-transfer_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    task "transfer" {
      driver = "exec"

      user = var.realtime_user

      config {
        command = "/local/run.sh"
      }

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      resources {
        memory = 500
        cpu = 300
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

set -e

seaflow-transfer -version

start="{{ key "cruise/start" }}"
cruise="{{ key "cruise/name" }}"
instrument=${NOMAD_META_instrument}
outdir="/jobs_data/seaflow-transfer/${cruise}/${instrument}"
echo "cruise=${cruise} start=${start}"
echo "transferring data for $instrument to $outdir"

mkdir -p "$outdir"

netbiosname=$(consul kv get "seaflowconfig/${instrument}/netbiosname")
datapath=$(consul kv get "seaflowconfig/${instrument}/datapath")
echo "netbiosname=${netbiosname} datapath=${datapath}"

nmblookup_resp=$(nmblookup "$netbiosname")
seaflowip=$(echo "$nmblookup_resp" | awk '{print $1}')
echo "seaflowip=$seaflowip"

sshuser=$(consul kv get "seaflowconfig/${instrument}/sshuser")
echo "sshuser=$sshuser"

SSHPASS=$(consul kv get "seaflowconfig/${instrument}/sshpassword")
SSHPASSWORD=${SSHPASS}
export SSHPASS SSHPASSWORD
echo "Got SSH password from conusl"

sshpass -e scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "${sshuser}@${seaflowip}:${datapath}/logs/SFlog.txt" \
  "${outdir}/.SFlog.txt"

mv "${outdir}/.SFlog.txt" "${outdir}/SFlog.txt"

seaflow-transfer \
  -srcAddress "${seaflowip}" \
  -sshUser "${sshuser}" \
  -srcRoot "${datapath}/datafiles/evt" \
  -dstRoot "${outdir}/evt" \
  -start "${start}"
        EOH
        destination = "/local/run.sh"
        perms = "755"
        change_mode = "restart"
      }
    }
  }
}
