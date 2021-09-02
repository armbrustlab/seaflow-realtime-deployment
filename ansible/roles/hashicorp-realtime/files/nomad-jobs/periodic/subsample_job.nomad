variable "realtime_user" {
  type = string
  default = "ubuntu"
}

job "subsample_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "0 */2 * * *"  // every 2 hours at 10 past the hour
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

  group "subsample_group" {
    count = 1

    volume "jobs_data" {
      type = "host"
      source = "jobs_data"
    }

    task "setup" {
      driver = "exec"

      user = var.realtime_user

      config {
        command = "/local/run.sh"
      }

      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      resources {
        memory = 300
        cpu = 300
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

# Get cruise info
echo "cruise=$(consul kv get cruise/name)" >> ${NOMAD_ALLOC_DIR}/data/vars
echo "start=$(consul kv get cruise/start)" >> ${NOMAD_ALLOC_DIR}/data/vars

# Get instrument name
echo "instrument=${NOMAD_META_instrument}" >> ${NOMAD_ALLOC_DIR}/data/vars

# Get subsample parameters for this instrument as shell variable assignments
consul kv get -recurse "subsample/${NOMAD_META_instrument}/" | \
  awk -F':' '{split($1,a,"/"); print a[length(a)] "=" $2}' | \
  tee -a >> ${NOMAD_ALLOC_DIR}/data/vars
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }
    }

    task "subsample" {
      driver = "docker"

      config {
        image = "ctberthiaume/seaflowpy:local"
        command = "/local/run.sh"
      }

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      resources {
        memory = 2000
        cpu = 300
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

set -e

# Get variables defined by setup task
source ${NOMAD_ALLOC_DIR}/data/vars

timestamp="$(TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)"
outdir="/jobs_data/subsample/${cruise}/${instrument}/${timestamp}"

seaflowpy version

[[ -d "$outdir" ]] || mkdir -p "$outdir"

# Full sample for noise estimation
seaflowpy evt sample \
  --min-date "${start}" \
  --tail-hours "${sample_tail_hours}" \
  --count "${sample_noise_count}" \
  --file-fraction 1.0 \
  --verbose \
  --outpath "${outdir}/last-${sample_tail_hours}-hours.fullSample.parquet" \
  "/jobs_data/seaflow-transfer/${cruise}/${instrument}/evt"

# Full sample with noise filtered out
seaflowpy evt sample \
  --min-date "${start}" \
  --tail-hours "${sample_tail_hours}" \
  --noise-filter \
  --file-fraction 1.0 \
  --count "${sample_full_count}" \
  --verbose \
  --outpath "${outdir}/last-${sample_tail_hours}-hours.fullSample-noNoise.parquet" \
  "/jobs_data/seaflow-transfer/${cruise}/${instrument}/evt"

# Bead sample
seaflowpy evt sample \
  --min-date "${start}" \
  --tail-hours "${sample_tail_hours}" \
  --count 1500 \
  --noise-filter \
  --min-fsc "${bead_sample_min_fsc}" \
  --min-pe "${bead_sample_min_pe}" \
  --min-chl "${bead_sample_min_chl}"  \
  --multi --file-fraction 1.0 \
  --verbose \
  --outpath "${outdir}/last-${sample_tail_hours}-hours.beadSample.parquet" \
  "/jobs_data/seaflow-transfer/${cruise}/${instrument}/evt"

# Bead finder
seaflowpy evt beads \
  --cruise "${cruise}" \
  --min-fsc "${bead_finder_min_fsc}" \
  --min-pe "${bead_finder_min_pe}" \
  --verbose \
  --out-dir "${outdir}/last-${sample_tail_hours}-hours.beads" \
  "${outdir}/last-${sample_tail_hours}-hours.beadSample.parquet"
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }
    }
  }
}
