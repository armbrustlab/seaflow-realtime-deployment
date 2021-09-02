job "grafana_job" {
  datacenters = ["dc1"]

  type = "service"

  group "grafana_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    network {
      port "grafana-http" {
        static = 3000
      }
    }

    service {
      name = "grafana"
      check {
        type = "http"
        method = "GET"
        path = "/api/health"
        port = "grafana-http"
        timeout = "3s"
        interval = "30s"
        
      }
    }

    task "grafana_task" {
      driver = "docker"

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
# grafana secrets env vars
GF_SECURITY_ADMIN_PASSWORD="{{key "grafana/GF_SECURITY_ADMIN_PASSWORD"}}"
GF_ANALYTICS_REPORTING_ENABLED=false
GF_ANALYTICS_CHECK_FOR_UPDATES=false
        EOH
        destination = "secrets/file.env"
        env = true
      }

      config {
        image = "grafana/grafana:8.1.2-ubuntu"
        ports = [ "grafana-http" ]
      }

      resources {
        memory = 2000
        cpu = 2000
      }
    }
  }
}
