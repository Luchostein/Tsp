#!/usr/bin/env bash

# Tsp -- Multiple task spooler queues manager
#
# Tsp --help
#
# Tsp [ --state-dir BASEDIR ] --setenv QUEUE => Sets TS_SOCKET
# Tsp [ --state-dir BASEDIR ] => --setenv /
#
# Tsp [ --state-dir BASEDIR ] --enq QUEUE [ TS_ARGS... ]
# Tsp [ --state-dir BASEDIR ] QUEUE [ TS_ARGS... ] => --enq QUEUE TS_ARGS...
#
# Tsp [ --state-dir BASEDIR ] [-z] { --list | --cleanup }
#
# Tsp [ --state-dir BASEDIR ] --pids   QUEUE                    [JOB_ID_RANGES...]
# Tsp [ --state-dir BASEDIR ] --signal QUEUE {SIGNAME | SIGNUM} [JOB_ID_RANGES...]
# Tsp [ --state-dir BASEDIR ] --sleep  QUEUE [TIME]
# Tsp [ --state-dir BASEDIR ] --wakeup QUEUE                    [JOB_ID_RANGES...]
# Tsp [ --state-dir BASEDIR ] { --wait | --exit | --stop | --kill } QUEUE
#
# Tsp [ --state-dir BASEDIR ] [ { --if-all | --unless } JOB_ID_RANGE ] QUEUE TS_ARGS...
#
#      --help     : this help.
#      --license  : Prints License.
# -D | --state-dir: sets TSP_STATE_DIR per invocation.
# -E | --setenv   : sets TS_SOCKET environment variable.
# -Q | --enq      : sends TS_ARGS to QUEUE tsp.
# -L | --list     : lists QUEUEs.
# -I | --pids     : lists PIDs of jobs in QUEUE.
# -G | --signal   : sends SIGNAME|SIGNUM signal to processes by --pids in QUEUE.
# -S | --sleep    : fills slots with priorized sleeps.
# -s | --wakeup   : kills running and queued sleeps, if any, added through --sleep.
# -K | --kill     : removes every queued job, then kills running jobs, then kills QUEUE.
# -W | --wait     : waits every running and queued job to finish.
# -X | --exit     : --wait QUEUE, then --kill QUEUE .
# -T | --stop     : removes every queued jobs in QUEUE, then --wait QUEUE.
# -C | --cleanup  : remove every unused sockets.
#
#
# --if-all JOB_ID_RANGE: queues a job to be ran if all jobs in the range succeed.
# --unless JOB_ID_RANGE: queues a job to be ran if any job in the range fails.
#
# JOB_ID_RANGE can have two forms: FROM_JOB_ID-TO_JOB_ID (both inclusive) or FROM_JOB_ID+COUNT; multiple ranges can be separated by ",".
#
# Environment variables:
# TSP_STATE_DIR: directory where to store sockets.
# TSP_STATE_DIR=$XDG_STATE_HOME/tsp
# TS_SOCKET: is to be set before calling the actual task spooler; it is set when sourced.
# TSP_EXE: Specifies the PATH to the Task Spooler binary. Defaults to tsp.
#
#
# LICENSE
# This program is released under license GNU GENERAL PUBLIC LICENSE Version 3
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.
#
#
# AUTHOR: Luis León Cárdenas Graide <luchostein [@] g mail [.] com>
# Copyright © 2023-2024 - Luis León Cárdenas Graide < luchostein [@] g mail [.] com >

((${TSP[sourced]:-0})) && return 0
export TS_SOCKET XDG_STATE_HOME="${XDG_STATE_HOME:-"$HOME"/.local/state}"
declare -A TSP=(
  [sourced]=1
  [exe]="${TSP_EXE:-tsp}"
  [stateDir]="${TSP_STATE_DIR:-"$XDG_STATE_HOME"/tsp}"
  [longopts]=:Dstate-dir:Esetenv:Wwait:Xexit:Tstop:Kkill:Llist:Ccleanup:Qenq:Gsignal:Ipids:Ssleep:swakeup:_help:_license:
  [zero]="${TSP_ZERO:-0}"
)

function Tsp::action::help() {
  while read -r; do
    ((${#REPLY})) || break
  done
  while read -r; do
    ((${#REPLY})) || break
    echo -E "${REPLY:2}"
  done
} <"${BASH_SOURCE[0]}"

function Tsp::action::license() {
  while read -r; do
    [ '# LICENSE' = "${REPLY:0:9}" ] && break
  done
  echo -E "${REPLY:2}"
  while read -r; do
    ((${#REPLY})) || break
    echo -E "${REPLY:2}"
  done
} <"${BASH_SOURCE[0]}"

function Tsp::_shopts::store() {
  local -n _shopts="${1?}"
  # $@: [us]:opt ...

  local -a opts=('' '') # -s -u
  local usopt US='us'
  for usopt in "${@:2}"; do
    local us opt
    IFS=: read -r us opt <<<"$usopt"
    ! shopt -q -p -- "$opt"
    local shopt=$?
    ! [ s = "$us" ]
    local s=$?
    if ((shopt ^ s)); then
      shopt -"$us" -- "$opt"
      opts[s]+=",$opt"
    fi
  done
  _shopts="${opts[0]:1}:${opts[1]:1}"
}
function Tsp::_shopts::restore() {
  local -n _shopts="${1?}"
  local -a opts=()
  local optpack opt us=s
  # -s:-u
  for optpack in "${_shopts%:*}" "${_shopts#*:}"; do
    IFS=, read -r -a opts <<<"$optpack"
    for opt in "${opts[@]}"; do
      shopt -"$us" -- "$opt"
    done
    us=u
  done
  :
}
function Tsp::_queue::quote() { # queueName
  local q="${1:-/}"
  [ / = "${q:0:1}" ] || q="/$q"
  while [[ "$q" == *//* ]]; do
    q="${q//\/\///}"
  done
  q="${q//\/_//__}"
  printf '%s' "${q//\/.//_.}"
}
function Tsp::_queue::unquote() { # quotedQueueName
  local qq="${1:-}"
  qq="${qq//\/_.//.}"
  printf '%s' "${qq//\/__//_}"
}

function Tsp::_jobs::range() {
  local -n _jArr="${1?Missing target array.}"
  shift
  _jArr=()
  local jobsSpec
  for jobsSpec in "$@"; do
    local -a jobsParts=()
    IFS=, read -r -a jobsParts <<<"$jobsSpec"
    ((${#jobsParts[@]})) || continue
    local jobPart
    for jobPart in "${jobsParts[@]}"; do
      ((${#jobPart})) || continue
      if ! [[ "$jobPart" =~ ^([0-9]+)(([+-])([0-9]+))?$ ]]; then
        printf 2>&1 '#Tsp! Invalid jobPart "%s" in jobsSpec "%s"\n' "$jobPart" "$jobsSpec"
        return 1
      fi
      local j jobFrom="${BASH_REMATCH[1]}" rangeKind="${BASH_REMATCH[3]:-+}" jobArg="${BASH_REMATCH[4]:-0}"
      if [ + = "$rangeKind" ]; then
        jobArg=$((jobFrom + jobArg))
        rangeKind=-
      fi
      # [ - = "$rangeKind" ]
      for ((j = jobFrom; j <= jobArg; ++j)); do
        _jArr+=($j)
      done
    done
  done
  ((${#_jArr[@]}))
}

function Tsp::_socket::name2path() { # stateDir queue
  local stateDir="${1?Missing sockets base directory.}" queue="${2?Missing queue name.}"
  printf '%s%s.S' "$stateDir" "$(Tsp::_queue::quote "$queue")"
}
function Tsp::_socket::path2name() { # stateDir path
  local stateDir="${1?Missing sockets base directory.}" queuePath="${2?Missing queue name.}"
  queuePath="${queuePath#"$stateDir"}"
  printf '%s' "$(Tsp::_queue::unquote "${queuePath%.S}")"
}
function Tsp::_socket::create() { # socketPath
  local socketPath="${1?Missing socket path.}"
  [ -e "$socketPath" ] && return 0
  local d="${socketPath%/*}"
  [ -d "$d" ] || mkdir -p -- "$d"
  local tid="$(
    Tsp::_tsp "$socketPath" -L TS_SOCKET="$socketPath" -- \
      true TS_SOCKET="$socketPath" "$(printf '%(%Y-%m-%dT%H:%M:%S)T' -1)" 2>&1
  )"
  if ! [[ "$tid" =~ ^[0-9]*$ ]]; then
    echo 1>&2 -E "#Tsp! Error starting daemon: $tid"
    return 1
  fi
  [ -e "$socketPath" ]
}
function Tsp::_socket() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  local socketPath="$(Tsp::_socket::name2path "$stateDir" "$queue")"
  Tsp::_socket::create "$socketPath" && printf '%s' "$socketPath"
}
function Tsp::_stateDir() {
  if (($#)); then
    local -n _v="${1?}"
  else
    local _v=''
  fi
  ((${#_v})) || _v="${TSP_STATE_DIR:-"${TSP[stateDir]}"}"
  (($#)) || printf '%s' "$_v"
}

function Tsp::action::setenv() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  export TS_SOCKET="$socketPath"
}

function Tsp::_tsp() {
  local socketPath="${1?}"
  # $@: TS_ARGS
  TS_SOCKET="$socketPath" "${TSP[exe]}" "${@:2}"
}
function Tsp::action::enq() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}" # $@
  Tsp::_tsp "$(Tsp::_socket "$stateDir" "$queue")" "${@:3}"
}

function Tsp::action::list() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" zero="${2:-"${TSP_ZERO:-"${TSP[zero]}"}"}"
  local sep='\n'
  ((zero)) && sep='\000'
  local f="%s$sep"

  local shopts socketPath
  Tsp::_shopts::store shopts s:globstar s:nullglob s:dotglob
  for socketPath in "$stateDir"/**/*.S; do
    [ -S "$socketPath" ] && printf "$f" "$(Tsp::_socket::path2name "$stateDir" "$socketPath")"
  done
  Tsp::_shopts::restore shopts
}

# $@: socketPath="${1?}" state="${2?}" arr="${3?}" limit="${4:--1}"
function Tsp::_tsp::grep() {
  local socketPath="${1?}" state="${2?}" arr="${3?}" limit="${4:--1}"
  if ((${#arr})); then
    ! [ + = "${arr:0:1}" ]
    local append=$?
    ((append)) && arr="${arr:1}"
    local -n _arr="$arr"
    ((append)) || _arr=()
  else
    local -a __arr=()
    local -n _arr=__arr
  fi
  local line s0="${#_arr[@]}" l=$((10 + 2 + 8)) # l: tID + 2 espacios + strState
  while ((limit < 0 || ${#_arr[@]} < limit)) && read -r line; do
    [[ "${line:0:l}" =~ ^([0-9]+)\ +${state}\  ]] || continue
    _arr+=("${BASH_REMATCH[1]}")
  done < <(Tsp::_tsp "$socketPath" -l)
  ((${#_arr[@]} - s0))
}

function Tsp::_tsp::pids() {
  local socketPath="${1?}" pidsArrName="${2?}"
  # $@: JOB_RANGES...
  ! [ + = "${pidsArrName:0:1}" ]
  local append=$?
  ((append)) && pidsArrName="${pidsArrName:1}"
  local -n _pids="$pidsArrName"
  ((append)) || _pids=()
  local -a tids=()
  if (($# > 2)); then
    Tsp::_jobs::range tids "${@:3}"
  else
    Tsp::_tsp::grep "$socketPath" running tids
  fi
  local tid pid s0="${#_pids[@]}"
  for tid in "${tids[@]}"; do
    pid="$(Tsp::_tsp "$socketPath" -p "$tid")"
    [[ "$pid" =~ ^[0-9]+$ ]] && _pids+=("$pid")
  done 2>/dev/null
  ((${#_pids[@]} - s0))
}
function Tsp::action::pids() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  # $@: JOB_RANGES...
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  local -a pids=()
  Tsp::_tsp::pids "$socketPath" pids "${@:3}" && printf '%d\n' "${pids[@]}"
  :
}
function Tsp::_tsp::signal() {
  local socketPath="${1?}" signal="${2:-0}"
  # $@: JOB_RANGES...
  local -a pids=()
  Tsp::_tsp::pids "$socketPath" pids "${@:3}"
  local i pid
  for ((i = 0; i < ${#pids[@]}; i += 16)); do
    kill -s "$signal" -- "${pids[@]:i:16}"
    echo -E "$signal" "${pids[@]:i:16}"
  done
}
function Tsp::action::signal() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}" signal="${3:-0}"
  # $@: JOB_RANGES...

  if ! [[ "$signal" =~ ^[0-9]+|([Ss][Ii][Gg])?[a-zA-Z][a-zA-Z0-9+-]*$ ]]; then
    printf 1>&2 '#Tsp! Invalid signal name: %s\n' "$signal"
    return 1
  fi
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  Tsp::_tsp::signal "$socketPath" "$signal" "${@:4}"
}
function Tsp::action::sleep() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}" time="${3:-365d}"
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  local -a tids=()
  local tag tid
  printf -v tag '%d@%(%Y%m%d%H%M%S)T.%04x%04x%04x' $PPID -1 $RANDOM $RANDOM $RANDOM
  local S="$(Tsp::_tsp "$socketPath" -S)"
  ((${#S})) || S=0
  while ((S--)); do
    tid="$(Tsp::_tsp "$socketPath" -L "Tsp:sleep:$tag" -- sleep -- "$time")"
    ((${#tid})) || continue
    Tsp::_tsp "$socketPath" -u "$tid"
    tids+=("$tid")
  done >/dev/null 2>&1
  local oIFS="$IFS"
  IFS=,
  echo -E "${tids[*]}"
  IFS="$oIFS"
}
function Tsp::action::wakeup() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  # $@: JOB_RANGE...
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"

  local -a tids=()
  if (($# > 2)); then
    Tsp::_jobs::range tids "${@:3}"
  else
    local l
    while read -r l; do
      [[ "$l" =~ ^([0-9]+)\ +(running|queued)\ .*\ \[Tsp:sleep:[0-9]+@[0-9]+\.[0-9a-f]+\]sleep\ -- ]] || continue
      tids+=("${BASH_REMATCH[1]}")
    done < <(Tsp::_tsp "$socketPath" -l)
  fi
  local tid
  for tid in "${tids[@]}"; do
    Tsp::_tsp "$socketPath" -r "$tid"
    Tsp::_tsp "$socketPath" -k "$tid"
  done >/dev/null 2>&1
  :
}
function Tsp::action::kill() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  local -a tids=()
  while Tsp::_tsp::grep "$socketPath" queued tids 128; do
    Tsp::_tsp "$socketPath" -r "${tids[@]}"
  done
  while Tsp::_tsp::grep "$socketPath" running tids 128; do
    Tsp::_tsp "$socketPath" -k "${tids[@]}"
  done
  Tsp::_tsp "$socketPath" -K
  [ -e "$socketPath" ] && rm -vf -- "$socketPath"
  ! [ -e "$socketPath" ]
}
function Tsp::action::wait() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-/}"
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"
  local -a tids=()
  if (($# > 2)); then
    Tsp::_jobs::range tids "${@:3}"
    local j
    for ((j = 0; j <= ${#tids[@]}; j += 128)); do
      Tsp::_tsp "$socketPath" -w "${tids[@]:j:128}"
    done
  else
    while Tsp::_tsp::grep "$socketPath" 'queued|running' tids 128; do
      Tsp::_tsp "$socketPath" -w "${tids[@]}"
    done
  fi
  :
}
function Tsp::action::stop() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" queue="${2:-}"
  local socketPath="$(Tsp::_socket "$stateDir" "$queue")"

  local -a tids=()
  while Tsp::_tsp::grep "$socketPath" queued tids 128; do
    "${TSP[exe]}" -r "${tids[@]}"
  done
  Tsp::action::wait "$@"
  :
}
function Tsp::_socket::_rmdirs() {
  (($#)) || return 0
  local dir="${1?}" rc=0
  for dir in "$dir"/*/; do
    Tsp::_socket::_rmdirs "$dir"
    ((rc |= $?))
  done
  ((rc)) || rmdir --verbose -- "$dir"
}
function Tsp::_socket::rmdirs() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}"
  local shopts
  Tsp::_shopts::store shopts s:globstar s:nullglob s:dotglob
  Tsp::_socket::_rmdirs "$stateDir"/.
  Tsp::_shopts::restore shopts
}
function Tsp::action::cleanup() {
  local stateDir="${1:-"$(Tsp::_stateDir)"}" zero="${2:-"${TSP_ZERO:-"${TSP[zero]}"}"}"
  local sep='\n'
  ((zero)) && sep='\000'
  local f="%s$sep"

  local -a tids=()
  local shopts socketPath
  Tsp::_shopts::store shopts s:globstar s:nullglob s:dotglob
  for socketPath in "$stateDir"/**/*.S; do
    [ -S "$socketPath" ] || continue
    Tsp::_tsp "$socketPath" -C
    Tsp::_tsp::grep "$socketPath" 'running|queued' tids 1 && continue
    Tsp::action::kill "$stateDir" "$(Tsp::_socket::path2name "$stateDir" "$socketPath")"
    [ -e "$socketPath" ] && rm -vf -- "$socketPath"
  done
  if cd -- "$stateDir"; then
    local -a dirs=()
    dirs=(**/)
    local dir d
    for ((d = ${#dirs[@]} - 1; d >= 0; --d)); do
      dir="${dirs[d]}"
      [ -d "$dir" ] && rmdir --verbose --parents --ignore-fail-on-non-empty -- "$dir"
    done
    cd -- "$OLDPWD"
  fi
  Tsp::_shopts::restore shopts
  :
}

# $@: stateDir queue
function Tsp::action::exit() {

  Tsp::action::wait "$@"
  Tsp::action::kill "$@"
  :
}

function Tsp() {
  local action='' queue='' q=0
  local zeroSeparator=0 stateDir="$(Tsp::_stateDir)"

  # Options parsing
  while (($#)); do
    case "$1" in
    --)
      shift
      break
      ;;
    -z)
      zeroSeparator=1
      shift
      break
      ;;
    --state-dir | -D)
      stateDir="${2?Missing state directory.}"
      shift
      shift
      ;;
    --setenv | --enq | --exit | --stop | --kill | --pids | --signal | --sleep | --wakeup | --wait | -[EQXTKIGSsW])
      if ((${#action})); then
        echo 1>&2 -E '#Tsp!' Only one action must be specified: "$action" "$1"
        return 1
      fi
      action="$1" queue="${2:-/}" q=1
      shift
      shift
      case "$action" in
      --signal | -G)
        # $@: SIGNAME|SIGNUM [jobs...]
        break
        ;;
      esac
      ;;
    --list | --cleanup | --help | --license | -[LC])
      if ((${#action})); then
        echo 1>&2 -E '#Tsp!' Only one action must be specified: "$action" "$1"
        return 1
      fi
      action="$1"
      shift
      ;;
      #--if-all | --unless)
      #  if [ -n "$action" ]; then
      #    echo 1>&2 -E '#!' Only one action must be specified: "$action" "$1"
      #    return 1
      #  fi
      #  action="$1"
      #  jobsRange="${2?Missing jobs range.}"
      #  shift 2
      #  ;;
    -*)
      ((q)) && break
      echo 1>&2 -E '#Tsp!' Invalid option: "$1" '(queue names must not begin with -)'
      return 1
      ;;
    *)
      ((q)) && break
      queue="$1" q=1
      shift
      [ -- = "${1:-}" ] && shift
      break
      ;;
    esac
  done
  action="${action#--}"
  action="${action#-}"
  ((${#action})) || action='enq'
  ((${#action} == 1)) && [[ "${TSP[longopts]}" =~ :$action([^:]+): ]] && action="${BASH_REMATCH[1]}"

  # Options validation

  # Queue must not be present
  case "$action" in
  list | cleanup)
    if ((${#queue})); then
      echo 1>&2 -E '#Tsp!' Queue must not be set with action --"$action": "$queue"
      return 1
    fi
    ;;
  esac

  # -Queue?
  if [ - = "${queue:0:1}" ]; then
    echo 1>&2 -E '#Tsp!' Queue name must not begin with '"-"': "$queue"
    return 1
  fi

  # Jobs range
  #case "$action" in
  #if_all | unless)
  #  if ! [[ "$jobsRange" =~ ^([0-9]+)(([+-])([0-9]+))?$ ]]; then
  #    echo -E '#!' Invalid jobs range: "$jobsRange" 1>&2
  #    return 1
  #  fi
  #  local -a jobsRange
  #  jobsRange=("${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
  #  ;;
  #esac

  local fAction=Tsp::action::"$action"
  if ! [ function = "$(type -t "$fAction")" ]; then
    echo 1>&2 -E '#Tsp!' Unknown action: "$action"
    return 1
  fi

  ((${#queue})) || queue=/
  case "$action" in
  list | cleanup | help | license)
    "$fAction" "$stateDir" "$zeroSeparator"
    ;;
  enq | pids | signal | sleep | wakeup | setenv | wait | exit | stop | kill)
    "$fAction" "$stateDir" "$queue" "$@"
    ;;
    #if_all | unless)
    #  "$action" "$tsBaseDir" "$queue" "${jobsRange[@]}" "$@"
    #  ;;
  esac
} </dev/null

# Sourced
(return 0) >/dev/null 2>&1 && return 0

# CLI Script
set -o nounset # -o errexit
if [ -z "${TSP_EXE:-}" ]; then
  for TSP_EXE in tsp ts; do
    TSP_EXE="$(type -P "$TSP_EXE")"
    ((${#TSP_EXE})) && [[ "$("$TSP_EXE" -V)" =~ ^Task\ Spooler ]] && break
    TSP_EXE=''
  done
fi
if ! ((${#TSP_EXE})); then
  echo 1>&2 '#Tsp!' Task spooler binary not found: nor tsp neither ts.
  exit 1
fi

Tsp "$@"
