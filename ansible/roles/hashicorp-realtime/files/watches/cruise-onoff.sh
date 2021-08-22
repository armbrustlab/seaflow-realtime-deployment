#!/usr/bin/env bash
# Start/stop realtime jobs

# Get value for the consul key that triggered this script
VALUE=$(jq -r '.Value | values' | base64 -d)

if [[ "$VALUE" = "on" ]]; then
  nomad job run -detach /etc/realtime/nomad-jobs/cruisemic_job.nomad
  nomad job run -detach /etc/realtime/nomad-jobs/seaflow-transfer_job.nomad
  nomad job run -detach /etc/realtime/nomad-jobs/seaflog_job.nomad
  nomad job run -detach /etc/realtime/nomad-jobs/subsample_job.nomad
  nomad job run -detach /etc/realtime/nomad-jobs/seaflow-analysis_job.nomad
elif [[ "$VALUE" = "off" ]]; then
  nomad job stop -yes -detach cruisemic_job
  nomad job stop -yes -detach seaflow-transfer_job
  nomad job stop -yes -detach seaflog_job
  nomad job stop -yes -detach subsample_job
  nomad job stop -yes -detach seaflow-analysis_job
fi
