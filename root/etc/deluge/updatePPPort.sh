#!/usr/bin/with-contenv bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [update-port] $*"
}

# Calculate the port

IPADDRESS=$1
log "ipAddress to calculate port from $IPADDRESS"
oct3=$(echo ${IPADDRESS} | tr "." " " | awk '{ print $3 }')
oct4=$(echo ${IPADDRESS} | tr "." " " | awk '{ print $4 }')
oct3binary=$(bc <<<"obase=2;$oct3" | awk '{ len = (8 - length % 8) % 8; printf "%.*s%s\n", len, "00000000", $0}')
oct4binary=$(bc <<<"obase=2;$oct4" | awk '{ len = (8 - length % 8) % 8; printf "%.*s%s\n", len, "00000000", $0}')

sum=${oct3binary}${oct4binary}
portPartBinary=${sum:4}
portPartDecimal=$((2#$portPartBinary))
if [ ${#portPartDecimal} -ge 4 ]
	then
	new_port="1"${portPartDecimal}
else
	new_port="10"${portPartDecimal}
fi
log "Calculated port $new_port"

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
