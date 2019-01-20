#!/usr/bin/with-contenv bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [update-port] $*"
}

log "Wait for tunnel to be fully initialized and PIA is ready to give us a port"
sleep 15

pia_client_id_file=/etc/deluge/pia_client_id

#
# First get a port from PIA
#

new_client_id() {
    head -n 100 /dev/urandom | sha256sum | tr -d " -" | tee $pia_client_id_file
}

pia_client_id="$(cat $pia_client_id_file 2>/dev/null)"
if [ -z "${pia_client_id}" ]; then
   log "Generating new client id for PIA"
   pia_client_id=$(new_client_id)
fi

# Get the port
port_assignment_url="http://209.222.18.222:2000/?client_id=$pia_client_id"
pia_response=$(curl -s -f "$port_assignment_url")
pia_curl_exit_code=$?

if [ -z "$pia_response" ]; then
    log "Port forwarding is already activated on this connection, has expired, or you are not connected to a PIA region that supports port forwarding"
fi

# Check for curl error (curl will fail on HTTP errors with -f flag)
if [ $pia_curl_exit_code -ne 0 ]; then
   log "curl encountered an error looking up new port: $pia_curl_exit_code"
   exit
fi

# Check for errors in PIA response
error=$(echo "$pia_response" | grep -oE "\"error\".*\"")
if [ ! -z "$error" ]; then
   log "PIA returned an error: $error"
   exit
fi

# Get new port, check if empty
new_port=$(echo "$pia_response" | grep -oE "[0-9]+")
if [ -z "$new_port" ]; then
    log "Could not find new port from PIA"
    exit
fi
log "Got new port $new_port from PIA"

#
# Now, set port in Deluge
#

# get current listening port
deluge_peer_port=$(deluge-console -c /config "config listen_ports" | grep listen_ports | grep -oE '[0-9]+' | head -1)
if [ "$new_port" != "$deluge_peer_port" ]; then
  if [ "true" = "$ENABLE_UFW" ]; then
    log "Update UFW rules before changing port in Deluge"

    log "Denying access to $deluge_peer_port"
    ufw deny "$deluge_peer_port"

    log "Allowing $new_port through the firewall"
    ufw allow "$new_port"
  fi

  deluge-console -c /config "config --set listen_ports ($new_port,$new_port)"
  deluge-console -c /config "config --set random_port false"
else
    log "No action needed, port hasn't changed"
fi
