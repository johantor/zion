#!/usr/bin/env bash
# Runs one review-gate command detached and bounded, so it ends inside the
# worker's turn (#239) and a headless worker can run it under one allow rule
# (#245): each call is a single simple command, where the inline recipe it
# replaces was a compound one that Claude's permission check refuses.
#
#   gate.sh start <id> <command>   launch; fails if <id> was used before
#   gate.sh poll  <id>             wait up to ~9 min; print the exit code or `running`
#   gate.sh stop  <id>             kill the process group; print `stopped` or `still-running`
#
# <id> is minted per handoff by the dispatcher (lane plus 8 hex characters).
# State lives in /tmp/crew-gate-<id>/{log,exit,pid}; grep the log for findings.
set -u

usage() { echo "usage: gate.sh start <id> <command> | poll <id> | stop <id>" >&2; exit 2; }

[ $# -ge 2 ] || usage
op="$1" id="$2"
case "$id" in
  ''|*[!a-z0-9-]*) echo "gate.sh: <id> must be lowercase letters, digits and dashes" >&2; exit 2 ;;
esac
d="/tmp/crew-gate-$id"

case "$op" in
  start)
    [ $# -eq 3 ] || usage
    mkdir -m 700 "$d" 2>/dev/null || { echo "gate.sh: $d already exists; mint a new <id>" >&2; exit 3; }
    # Job control gives the background job its own process group, so stop can
    # kill the whole tree the command starts.
    set -m
    # The code lands via a rename, so poll never reads a half-written file.
    ( bash -c "$3" >"$d/log" 2>&1; echo $? >"$d/exit.tmp"; mv "$d/exit.tmp" "$d/exit" ) >/dev/null 2>&1 &
    echo $! >"$d/pid"
    echo "$d"
    ;;
  poll)
    [ -d "$d" ] || { echo "gate.sh: no gate $d" >&2; exit 3; }
    for ((i = 0; i < 110; i++)); do [ -s "$d/exit" ] && break; sleep 5; done
    if [ -s "$d/exit" ]; then head -c 8 "$d/exit"; else echo running; fi
    ;;
  stop)
    [ -f "$d/pid" ] || { echo "gate.sh: no gate $d" >&2; exit 3; }
    p="$(head -c 16 "$d/pid")"
    kill -TERM -- "-$p" 2>/dev/null
    for ((i = 0; i < 60; i++)); do kill -0 -- "-$p" 2>/dev/null || break; sleep 1; done
    if kill -0 -- "-$p" 2>/dev/null; then echo still-running; else echo stopped; fi
    ;;
  *) usage ;;
esac
