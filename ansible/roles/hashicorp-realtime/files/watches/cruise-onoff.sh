#!/usr/bin/env bash
# Stop realtime jobs

# Get value for the consul key that triggered this script
VALUE=$(jq -r '.Value | values' | base64 -d)

if [[ "$VALUE" = "on" ]]; then
  nomad job run -detach /etc/nomad.d/jobs/cruisemic_job.nomad
  nomad job run -detach /etc/nomad.d/jobs/seaflow-transfer_job.nomad
  nomad job run -detach /etc/nomad.d/jobs/seaflog_job.nomad
elif [[ "$VALUE" = "off" ]]; then
  nomad job stop -yes -detach cruisemic_job
  nomad job stop -yes -detach seaflow-transfer_job
  nomad job stop -yes -detach seaflog_job
fi
