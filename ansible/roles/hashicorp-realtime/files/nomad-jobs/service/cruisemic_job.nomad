variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "cruisemic_job" {
  datacenters = ["dc1"]

  type = "service"

  group "cruisemic_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    service {
      name = "cruisemic"
    }

    task "cruisemic_task" {
      driver = "exec"

      user = var.realtime_user

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

CRUISE="{{ key "cruise/name" }}"
PARSER="{{ key "appconfig/cruisemic/parser" }}"
PORT="{{ key "appconfig/cruisemic/port" }}"
INTERVAL="{{ key "appconfig/cruisemic/interval" }}"

cruisemic --version

cruisemic \
  -parser "${PARSER}" \
  -name "${CRUISE}" \
  -udp -port "${PORT}" \
  -interval "${INTERVAL}" \
  -dir "/jobs_data/cruisemic/${CRUISE}" \
  -quiet -flush
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
