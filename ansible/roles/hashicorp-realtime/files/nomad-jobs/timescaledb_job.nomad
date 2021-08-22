job "timescaledb_job" {
  datacenters = ["dc1"]

  type = "service"

  group "timescaledb_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    network {
      port "postgres" {
        static = 5432
      }
    }

    service {
      name = "timescaledb"
      check {
        task = "timescaledb_task"
        type = "script"
        timeout = "3s"
        interval = "30s"
        command = "/usr/local/bin/pg_isready"
      }
    }

    task "timescaledb_task" {
      driver = "docker"

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
# Timescaledb secrets env vars
POSTGRES_PASSWORD="{{key "timescaledb/POSTGRES_PASSWORD"}}"
TIMESCALEDB_TELEMETRY=off
        EOH
        destination = "secrets/file.env"
        env = true
      }

      config {
        image = "timescale/timescaledb:2.4.1-pg12"
        ports = [ "postgres" ]
      }

      resources {
        memory = 2000
        cpu = 2000
      }
    }
  }
}
