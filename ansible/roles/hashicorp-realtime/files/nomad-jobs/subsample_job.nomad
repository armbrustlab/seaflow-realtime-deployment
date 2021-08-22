job "subsample_job" {
  datacenters = ["dc1"]

  type = "batch"

  periodic {
    cron = "0 */2 * * *"  // every 2 hours at 10 past the hour
    prohibit_overlap = true
    time_zone = "UTC"
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

    task "subsample_task" {
      driver = "docker"

      user = "ubuntu"

      volume_mount {
        volume = "jobs_data"
        destination = "/jobs_data"
      }

      template {
        data = <<EOH
#!/usr/bin/env bash

CRUISE="{{ key "cruise/name" }}"
START="{{ key "cruise/start" }}"
TIMESTAMP="$(TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)"
OUTDIR="/jobs_data/subsample/${CRUISE}/${TIMESTAMP}"
TAILHOURS="{{ key "appconfig/subsample/sample-tail-hours" }}"
SAMPLE_NOISE_COUNT="{{ key "appconfig/subsample/sample-noise-count" }}"
SAMPLE_FULL_COUNT="{{ key "appconfig/subsample/sample-full-count" }}"
BEAD_SAMPLE_MIN_FSC="{{ key "appconfig/subsample/bead-sample-min-fsc" }}"
BEAD_SAMPLE_MIN_PE="{{ key "appconfig/subsample/bead-sample-min-pe" }}"
BEAD_SAMPLE_MIN_CHL="{{ key "appconfig/subsample/bead-sample-min-chl" }}"
BEAD_FINDER_MIN_FSC="{{ key "appconfig/subsample/bead-finder-min-fsc" }}"
BEAD_FINDER_MIN_PE="{{ key "appconfig/subsample/bead-finder-min-pe" }}"


seaflowpy version

[[ -d "$OUTDIR" ]] || mkdir -p "$OUTDIR"

# Full sample for noise estimation
seaflowpy evt sample \
  --min-date "${START}" \
  --tail-hours "${TAILHOURS}" \
  --count "${SAMPLE_NOISE_COUNT}" \
  --file-fraction 1.0 \
  --verbose \
  --outpath "${OUTDIR}/last-${TAILHOURS}-hours.fullSample.parquet" \
  "/jobs_data/seaflow-transfer/${CRUISE}/evt"

# Full sample with noise filtered out
seaflowpy evt sample \
  --min-date "${START}" \
  --tail-hours "${TAILHOURS}" \
  --noise-filter \
  --file-fraction 1.0 \
  --count "${SAMPLE_FULL_COUNT}" \
  --verbose \
  --outpath "${OUTDIR}/last-${TAILHOURS}-hours.fullSample-noNoise.parquet" \
  "/jobs_data/seaflow-transfer/${CRUISE}/evt"

# Bead sample
seaflowpy evt sample \
  --min-date "${START}" \
  --tail-hours "${TAILHOURS}" \
  --count 1500 \
  --noise-filter \
  --min-fsc "${BEAD_SAMPLE_MIN_FSC}" \
  --min-pe "${BEAD_SAMPLE_MIN_PE}" \
  --min-chl "${BEAD_SAMPLE_MIN_CHL}"  \
  --multi --file-fraction 1.0 \
  --verbose \
  --outpath "${OUTDIR}/last-${TAILHOURS}-hours.beadSample.parquet" \
  "/jobs_data/seaflow-transfer/${CRUISE}/evt"

# Bead finder
seaflowpy evt beads \
  --cruise "${CRUISE}" \
  --min-fsc "${BEAD_FINDER_MIN_FSC}" \
  --min-pe "${BEAD_SAMPLE_MIN_PE}" \
  --verbose \
  --out-dir "${OUTDIR}/last-${TAILHOURS}-hours.beads" \
  "${OUTDIR}/last-${TAILHOURS}-hours.beadSample.parquet"
        EOH
        destination = "/local/run.sh"
        change_mode = "restart"
        perms = "755"
      }

      config {
        image = "ctberthiaume/seaflowpy:local"
        command = "/local/run.sh"
      }

      resources {
        memory = 2000
        cpu = 2000
      }
    }
  }
}
