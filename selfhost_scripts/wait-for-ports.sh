#!/bin/sh

function show_usage() {
  echo "Syntax $0 [-t|--time-limit N] host:port..."
}

function show_help() {
  echo "Syntax $0 [-t|--time-limit N] host:port..."
  echo "  -t, --time-limit  Set time limit for wait to N seconds [default 20]"
  echo "  -q, --quiet       Quiet output"
  echo "  -v, --verbose     Verbose output (show connection info and errors)"
  echo "  -p, --progress    Show progress indicators"
  echo "  -P, --no-progress Do not show progress indicators"
  echo "Any number of host:port combinations can be passed"
  echo "Will wait until it is possible to open a TCP socket to each host:port combination"
  echo "Exits with 0 if successful or 1 if not after timeout"
}

[ "$time_limit" == "" ] && time_limit=20 # default time limit
[ "$show_progress" == "" ] && show_progress=true # default setting
[ "$log_level" == "" ] && log_level=20 # default log level

host_ports=
ready_ports=
unready_ports=

while [ "$#" -gt 0 ]; do
  [ "$1" == "-q" ] && { log_level=30 ; shift 1 ; continue ; }
  [ "$1" == "--quiet" ] && { log_level=30 ; shift 1 ; continue ; }
  [ "$1" == "-v" ] && { log_level=10 ; shift 1 ; continue ; }
  [ "$1" == "--verbose" ] && { log_level=10 ; shift 1 ; continue ; }
  [ "$1" == "-p" ] && { show_progress=true ; shift 1 ; continue ; }
  [ "$1" == "--progress" ] && { show_progress=true ; shift 1 ; continue ; }
  [ "$1" == "-P" ] && { show_progress=false ; shift 1 ; continue ; }
  [ "$1" == "--no-progress" ] && { show_progress=false ; shift 1 ; continue ; }
  [ "$1" == "-t" ] && { shift 1 ; time_limit="$1" ; shift 1 ; continue ; }
  [ "$1" == "--time-limit" ] && { shift 1 ; time_limit="$1" ; shift 1 ; continue ; }
  [ "${1#--time-limit=}" != "$1" ] && { time_limit="${1#--time-limit=}" ; shift 1 ; continue ; }
  [ "$1" == "-h" ] && { show_help ; exit 1 ; }
  [ "$1" == "--help" ] && { show_help ; exit 1 ; }
  [ "$1" == "-?" ] && { show_usage ; exit 1 ; }
  [ "${1#-}" != "$1" ] && { echo "Unknown parameter" "$1" >&2 ; show_usage >&2 ; exit 1 ; }
  [ "${1##*:}" != "$1" ] && { host_ports="$host_ports $1" ; shift 1 ; continue ; }
  echo "Unknown parameter" "$1" >&2 ; show_usage >&2 ; exit 1
done

function port_ready() {
  host="$1"
  post="$2"
  if [ "$log_level" -le 10 ]; then
    nc -w 1 "$host" "$port" </dev/null
  else
    nc -w 1 "$host" "$port" </dev/null 2>/dev/null
  fi
  if [ "$?" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

function ports_ready() {
  ready_ports=
  unready_ports=
  for host_port in $host_ports; do
    host="${host_port%:*}"
    port="${host_port##*:}"
    if ! port_ready "$host" "$port"; then
      unready_ports="$host_port $unready_ports"
    else
      ready_ports="$host_port $ready_ports"
    fi
  done
  unready_ports="${unready_ports# }"
  ready_ports="${ready_ports# }"
  if [ "$unready_ports" == "" ]; then
    return 0
  else
    return 1
  fi
}

start_ts=$(date +%s)
end_ts=$((start_ts+time_limit))
timeout=false
[ $log_level -le 10 ] && echo "Waiting for dependent service ports ($host_ports) to become available, up to ${time_limit}s"

until ports_ready ; do
  [ $end_ts -le $(date +%s) ] && { timeout=true ; break ; }
  [ $log_level -le 20 ] && [ $show_progress == true ] && echo -n .
  sleep 1
done
if [ "$timeout" == "false" ]; then
  if [ $log_level -le 10 ]; then echo "All dependent service ports ($host_ports) available"
  elif [ $log_level -le 20 ]; then echo "All dependent service ports available"
  fi
  exit 0
else
  [ $log_level -le 30 ] && echo "Could not connect to dependent service ports before time_limit of ${time_limit}s" >&2
  [ $log_level -le 10 ] && echo "Ready ports: ${ready_ports}" >&2
  [ $log_level -le 10 ] && echo "Unready ports: ${unready_ports}" >&2
  exit 1
fi


