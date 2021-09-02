data_dir = "/var/local/nomad/data"

bind_addr = "127.0.0.1"

server {
  enabled = true
  bootstrap_expect = 1 
  default_scheduler_config {
    memory_oversubscription_enabled = true
  }
}

advertise {
  http = "127.0.0.1"
  rpc = "127.0.0.1"
  serf = "127.0.0.1"
}

client {
  enabled = true
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

plugin "docker" {
  config {
    volumes {
      enabled      = true  # to enable bind mounts
    }
    gc {
      image = false  # don't erase images once a job is complete
    }
  }
}

