#!/usr/bin/with-contenv bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [tunnel-up] $*"
}

# This script will be called with tun/tap device name as parameter 1, and local IP as parameter 4
# See https://openvpn.net/index.php/open-source/documentation/manuals/65-openvpn-20x-manpage.html (--up cmd)
log "Up script executed with $*"
if [ "$4" = "" ]; then
  log "ERROR, unable to obtain tunnel address"
  log "Killing $PPID"
  kill -9 $PPID
  exit 1
fi

# If deluge-pre-start.sh exists, run it
if [ -x /config/deluge-pre-start.sh ]
then
  log "Executing /config/deluge-pre-start.sh"
  /config/deluge-pre-start.sh "$@"
  log "/config/deluge-pre-start.sh returned $?"
fi

log "Using ip of interface $1: $4"
export DELUGE_BIND_ADDRESS_IPV4=$4

if [ -e /config/core.conf ]
then
  log "Updating Deluge conf file: listen_interface=$DELUGE_BIND_ADDRESS_IPV4"
  sed -i -e "s/\"listen_interface\": \".*\"/\"listen_interface\": \"$DELUGE_BIND_ADDRESS_IPV4\"/" /config/core.conf
fi

if [ "true" = "$DROP_DEFAULT_ROUTE" ]; then
  log "Dropping default route"
  ip r del default || exit 1
fi

log "Starting Deluge"
s6-svc -u /var/run/s6/services/deluged

log "Setting Deluge listen_interface"
deluge-console -c /config "config --set listen_interface '$DELUGE_BIND_ADDRESS_IPV4'"

## If we use UFW or the LOCAL_NETWORK we need to grab network config info
if [[ "${ENABLE_UFW,,}" == "true" ]] || [[ -n "${LOCAL_NETWORK-}" ]]; then
  eval $(/sbin/ip r l | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')
  ## IF we use UFW_ALLOW_GW_NET along with ENABLE_UFW we need to know what our netmask CIDR is
  if [[ "${ENABLE_UFW,,}" == "true" ]] && [[ "${UFW_ALLOW_GW_NET,,}" == "true" ]]; then
    eval $(ip r l dev ${INT} | awk '{if($5=="link"){print "GW_CIDR="$1; exit}}')
  fi
fi

## Open port to any address
function ufwAllowPort {
  typeset -n portNum=${1}
  if [[ "${ENABLE_UFW,,}" == "true" ]] && [[ -n "${portNum-}" ]]; then
    log "Allowing ${portNum} through the firewall"
    ufw allow ${portNum}
  fi
}

## Open port to specific address.
function ufwAllowPortLong {
  typeset -n portNum=${1} sourceAddress=${2}

  if [[ "${ENABLE_UFW,,}" == "true" ]] && [[ -n "${portNum-}" ]] && [[ -n "${sourceAddress-}" ]]; then
    log "Allowing ${sourceAddress} through the firewall to port ${portNum}"
    ufw allow from ${sourceAddress} to any port ${portNum}
  fi
}

if [[ "${ENABLE_UFW,,}" == "true" ]]; then
  if [[ "${UFW_DISABLE_IPTABLES_REJECT,,}" == "true" ]]; then
    # A horrible hack to ufw to prevent it detecting the ability to limit and REJECT traffic
    sed -i 's/return caps/return []/g' /usr/lib/python3/dist-packages/ufw/util.py
    # force a rewrite on the enable below
    log "Disable and blank firewall"
    ufw disable
    echo "" > /etc/ufw/user.rules
  fi
  # Enable firewall
  log "Enabling firewall"
  sed -i -e s/IPV6=yes/IPV6=no/ /etc/default/ufw
  ufw enable

  PEER_PORT=$(jq -cr '.["listen_ports"]' ./config/deluge/core.conf | grep -v null | head -1 | tr -d "[]" | tr "," ":")
  DAEMON_PORT=$(jq -cr '.["daemon_port"]' ./config/deluge/core.conf | grep -v null | head -1)

  ufwAllowPort PEER_PORT

  if [[ "${WEBPROXY_ENABLED,,}" == "true" ]]; then
    ufwAllowPort WEBPROXY_PORT
  fi
  if [[ "${UFW_ALLOW_GW_NET,,}" == "true" ]]; then
    ufwAllowPortLong DAEMON_PORT GW_CIDR
  else
    ufwAllowPortLong DAEMON_PORT GW
  fi

  if [[ -n "${UFW_EXTRA_PORTS-}"  ]]; then
    for port in ${UFW_EXTRA_PORTS//,/ }; do
      if [[ "${UFW_ALLOW_GW_NET,,}" == "true" ]]; then
        ufwAllowPortLong port GW_CIDR
      else
        ufwAllowPortLong port GW
      fi
    done
  fi
fi

if [[ -n "${LOCAL_NETWORK-}" ]]; then
  if [[ -n "${GW-}" ]] && [[ -n "${INT-}" ]]; then
    for localNet in ${LOCAL_NETWORK//,/ }; do
      log "Adding route to local network ${localNet} via ${GW} dev ${INT}"
      /sbin/ip r a "${localNet}" via "${GW}" dev "${INT}"
      if [[ "${ENABLE_UFW,,}" == "true" ]]; then
        ufwAllowPortLong DAEMON_PORT localNet
        if [[ -n "${UFW_EXTRA_PORTS-}" ]]; then
          for port in ${UFW_EXTRA_PORTS//,/ }; do
            ufwAllowPortLong port localNet
          done
        fi
      fi
    done
  fi
fi

if [ "$OPENVPN_PROVIDER" = "PIA" ]
then
  log "Configuring port forwarding"
  exec /etc/deluge/updatePort.sh &
elif [ "$OPENVPN_PROVIDER" = "PERFECTPRIVACY" ]
then
  log "Configuring port forwarding"
  exec /etc/deluge/updatePPPort.sh ${DELUGE_BIND_ADDRESS_IPV4} &
else
  log "No port updated for this provider!"
fi

# If deluge-post-start.sh exists, run it
if [ -x /config/deluge-post-start.sh ]
then
  log "Executing /config/deluge-post-start.sh"
  /config/deluge-post-start.sh "$@"
  log "/config/deluge-post-start.sh returned $?"
fi

log "Deluge startup script complete."
