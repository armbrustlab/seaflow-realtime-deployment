variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "minio_job" {
  datacenters = ["dc1"]

  type = "service"

  group "minio_group" {
    count = 1

    volume "minio_data" {
      type = "host"
      source = "minio_data"
    }

    network {
      port "minio-api" {
        static = 9000
      }
      port "minio-console" {
        static = 9001
      }
    }

    service {
      name = "minio"
    }

    task "minio_task" {
      driver = "exec"

      user = var.realtime_user

      volume_mount {
        volume = "minio_data"
        destination = "/minio"
      }

      template {
        data = <<EOH
# Minio env vars
MINIO_ROOT_USER="{{key "minio/MINIO_ROOT_USER"}}"
MINIO_ROOT_PASSWORD="{{key "minio/MINIO_ROOT_PASSWORD"}}"
MINIO_KMS_SECRET_KEY="{{key "minio/MINIO_KMS_SECRET_KEY"}}"
MINIO_NOTIFY_WEBHOOK_ENABLE=on
MINIO_NOTIFY_WEBHOOK_ENDPOINT_PRIMARY="http://localhost:{{key "minio/webhook_endpoint_port"}}/hooks/minio"
MINIO_NOTIFY_WEBHOOK_QUEUE_DIR=/minio/events
        EOH
        destination = "secrets/file.env"
        env = true
      }

      config {
        command = "minio"
        args = [
          "server",
          "/minio/data",
          "--console-address", ":9001"
        ]
      }

      resources {
        memory = 1000
        cpu = 500
      }
    }
  }
}
