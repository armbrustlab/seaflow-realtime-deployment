#!/usr/bin/env bash
# Stop all future and running periodic jobs
# usage: stop-periodic-jobs.sh [-purge]

if [[ $1 = "-purge" ]]; then
  echo "stopping and purging all periodic jobs"
else
  echo "stopping all periodic jobs"
fi

for jobfile in /etc/realtime/nomad-jobs/periodic/*.nomad; do
  jobname=$(basename "$jobfile" .nomad)
  if [[ $1 = "-purge" ]]; then
    nomad job status | awk -v patt="$jobname" '$1 ~ patt {print $1}' | xargs -n 1 -I {} nomad job stop -yes -detach -purge {}
  else
    nomad job status | awk -v patt="$jobname" '$1 ~ patt {print $1}' | xargs -n 1 -I {} nomad job stop -yes -detach {}
  fi
done
