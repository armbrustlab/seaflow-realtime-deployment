Realtime analysis is installed as set of MacOS Launchd job definition files and their corresponding shell scripts.

The specific configuration for each job (file locations, networking, credentials, names) is defined in a populated `seaflow-realtime.conf`.

## Launchd job definitions and shell script

### Copy, filter, and gate

* `local.seaflow-realtime-job.plist` (launchd)
* `seaflow-realtime-job` (shell)

### Mount the SeaFLow instruments data folder Windows share

* `local.seaflow-realtime-mount.plist` (launchd)
* `seaflow-realtime-mount` (shell)

### Create a reverse SSH tunnel to shore

* `local.seaflow-realtime-ssh-reverse-tunnel.plist` (launchd)
* `seaflow-realtime-ssh-reverse-tunnel` (shell)

### Sync data back to shore with rsync

* `local.seaflow-realtime-sync.plist` (launchd)
* `seaflow-realtime-sync` (shell)

## Install Launchd jobs
Copy `*.plist` files to `~/LibraryLaunchAgents` and load them.

```
cp *.plist ~/Library/LaunchAgents
launchctl load ~/Library/LaunchAgents/local.seaflow-realtime-job.plist
launchctl load ~/Library/LaunchAgents/local.seaflow-realtime-mount.plist
launchctl load ~/Library/LaunchAgents/local.seaflow-realtime-ssh-reverse-tunnel.plist
launchctl load ~/Library/LaunchAgents/local.seaflow-realtime-sync.plist
```

## Stop then restart realtime analysis
This also applies to any other launchd job

```
launchctl stop ~/Library/LaunchAgents/local.seaflow-realtime-job.plist
# changes filter or gating ...
launchctl start ~/Library/LaunchAgents/local.seaflow-realtime-job.plist
```

## Reconfigure launchd job
If a `plist` file is modified, the job must be unloaded then loaded to make the change take effect.

```
launchctl unload ~/Library/LaunchAgents/local.seaflow-realtime-job.plist
# changes filter or gating ...
launchctl load ~/Library/LaunchAgents/local.seaflow-realtime-job.plist
```
