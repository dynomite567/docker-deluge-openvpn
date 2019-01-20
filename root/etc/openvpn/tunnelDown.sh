#!/usr/bin/with-contenv bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [tunnel-down] $*"
}

# If deluge-pre-stop.sh exists, run it
if [ -x /config/deluge-pre-stop.sh ]
then
   log "Executing /config/deluge-pre-stop.sh"
   /config/deluge-pre-stop.sh "$@"
   log "/config/deluge-pre-stop.sh returned $?"
fi

log "STOPPING DELUGE"
s6-svc -d /var/run/s6/services/deluged

# If deluge-post-stop.sh exists, run it
if [ -x /config/deluge-post-stop.sh ]
then
   log "Executing /config/deluge-post-stop.sh"
   /config/deluge-post-stop.sh "$@"
   log "/config/deluge-post-stop.sh returned $?"
fi
