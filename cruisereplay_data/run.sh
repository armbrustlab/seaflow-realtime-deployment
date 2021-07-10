#!/usr/bin/env bash
# To be run from the source vagrant VM
cruisereplay \
  --evt /cruisereplay_data/HOT325-datafiles/ \
  --seaflowlog /cruisereplay_data/SFlog.txt \
  --underway /cruisereplay_data/HOT325-underway/HOT325-raw.tab.gz \
  --throttle 60 \
  --port 20000 \
  --outdir /cruisereplay_data/output \
  --start 2020-12-18T00:25:00Z \
  --warp 10 \
  --host "$BROADCAST_IP"
