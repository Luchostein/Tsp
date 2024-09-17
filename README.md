 Tsp -- Multiple task spooler queues manager

Tsp --help

Tsp [ --state-dir BASEDIR ] --setenv QUEUE => Sets TS_SOCKET
Tsp [ --state-dir BASEDIR ] => --setenv /

Tsp [ --state-dir BASEDIR ] --enq QUEUE [ TS_ARGS... ]
Tsp [ --state-dir BASEDIR ] QUEUE [ TS_ARGS... ] => --enq QUEUE TS_ARGS...

Tsp [ --state-dir BASEDIR ] [-z] { --list | --cleanup }

Tsp [ --state-dir BASEDIR ] --pids   QUEUE                    [JOB_ID_RANGES...]
Tsp [ --state-dir BASEDIR ] --signal QUEUE {SIGNAME | SIGNUM} [JOB_ID_RANGES...]
Tsp [ --state-dir BASEDIR ] --sleep  QUEUE [TIME]
Tsp [ --state-dir BASEDIR ] --wakeup QUEUE                    [JOB_ID_RANGES...]
Tsp [ --state-dir BASEDIR ] { --wait | --exit | --stop | --kill } QUEUE

Tsp [ --state-dir BASEDIR ] [ { --if-all | --unless } JOB_ID_RANGE ] QUEUE TS_ARGS...

     --help     : this help.
     --license  : Prints License.
-D | --state-dir: sets TSP_STATE_DIR per invocation.
-E | --setenv   : sets TS_SOCKET environment variable.
-Q | --enq      : sends TS_ARGS to QUEUE tsp.
-L | --list     : lists QUEUEs.
-I | --pids     : lists PIDs of jobs in QUEUE.
-G | --signal   : sends SIGNAME|SIGNUM signal to processes by --pids in QUEUE.
-S | --sleep    : fills slots with priorized sleeps.
-s | --wakeup   : kills running and queued sleeps, if any, added through --sleep.
-K | --kill     : removes every queued job, then kills running jobs, then kills QUEUE.
-W | --wait     : waits every running and queued job to finish.
-X | --exit     : --wait QUEUE, then --kill QUEUE .
-T | --stop     : removes every queued jobs in QUEUE, then --wait QUEUE.
-C | --cleanup  : remove every unused sockets.


--if-all JOB_ID_RANGE: queues a job to be ran if all jobs in the range succeed.
--unless JOB_ID_RANGE: queues a job to be ran if any job in the range fails.

JOB_ID_RANGE can have two forms: FROM_JOB_ID-TO_JOB_ID (both inclusive) or FROM_JOB_ID+COUNT; multiple ranges can be separated by ",".

Environment variables:
TSP_STATE_DIR: directory where to store sockets.
TSP_STATE_DIR=$XDG_STATE_HOME/tsp
TS_SOCKET: is to be set before calling the actual task spooler; it is set when sourced.
TSP_EXE: Specifies the PATH to the Task Spooler binary. Defaults to tsp.


LICENSE
This program is released under license GNU GENERAL PUBLIC LICENSE Version 3

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.


AUTHOR: Luis León Cárdenas Graide <luchostein [@] g mail [.] com>
Copyright © 2023-2024 - Luis León Cárdenas Graide < luchostein [@] g mail [.] com >