#!/bin/sh
#
# checkpoint_scrub.sh: scrub a ZFS pool's checkpointed state with zdb.
#
# Modes:
#   -f  full: verify the whole checkpointed state at once (default).
#   -i  incremental: one window of STEP txgs at a time
#

set -u

PROG=${0##*/}

# Defaults; can be override first by the config file or command line.
POOL=
MODE=full
STEP=10000
BREATH=60
MEMLIMIT_KB=
STATE_FILE=
ZPOOL=${ZPOOL:-zpool}
ZDB=${ZDB:-zdb}
ZDB_OPTS=${ZDB_OPTS:-}

# State file.
STATE_DIR=/var/lib/checkpoint_scrub

ONE_WINDOW=0
RESET_STATE=0
CONFIG_FILE=

# Globals.
CKPT_OWNED=0
CURSOR=0
CHILD_PID=

usage()
{
	cat <<EOF
usage: $PROG [-f | -i] [-1R] [-c config] [-s step_txgs] [-b seconds]
       [-M kb] [-S state_file] [pool]

  -f            full mode: verify the whole checkpointed state (default)
  -i            incremental mode: verify in txg windows
  -1            run a single window, then exit (implies -i)
  -R            remove the state file first (restart from txg 0)
  -c config     read configuration from this file (shell syntax)
  -s step_txgs  TXGs per incremental window (default $STEP)
  -b seconds    breathing space between incremental windows (default $BREATH)
  -M kb         virtual address space limit for zdb, in kilobytes
                (ulimit -v); this is not a resident-memory cap, and
                zdb needs gigabytes of it -- size it generously
  -S state_file where to keep the scrub cursor
                (default $STATE_DIR/<pool>.state)
EOF
	exit "${1:-2}"
}

die()
{
	printf '%s: %s\n' "$PROG" "$*" >&2
	exit 1
}

warn()
{
	printf '%s: %s\n' "$PROG" "$*" >&2
}

log()
{
	printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"
}

is_uint()
{
	printf '%s\n' "${1:-}" | grep -Eq '^(0|[1-9][0-9]*)$' &&
	    [ "$(printf '%s\n' "${1:-}" | wc -l)" -eq 1 ]
}

load_config()
{
	[ -r "$1" ] || die "cannot read config file '$1'"
	. "$1" || die "cannot load config file '$1'"
}

check_state_file_owner()
{
	[ -f "$STATE_FILE" ] || return 0
	state_pool=$(sed -n 's/^POOL=//p' "$STATE_FILE")
	if [ "$state_pool" != "$POOL" ]; then
		die "state file '$STATE_FILE' belongs to pool '$state_pool', not '$POOL'"
	fi
}

load_state()
{
	CURSOR=0
	[ -f "$STATE_FILE" ] || return 0
	state_cursor=$(sed -n 's/^CURSOR=//p' "$STATE_FILE")
	is_uint "$state_cursor" ||
	    die "state file '$STATE_FILE' has an invalid cursor '$state_cursor'"
	CURSOR=$state_cursor
}

write_state()
{
	state_tmp=$(mktemp "$STATE_FILE.XXXXXX") ||
	    die "cannot create a temporary file next to '$STATE_FILE'"
	cat > "$state_tmp" <<-EOF || die "cannot write '$state_tmp'"
		# Managed by $PROG; do not edit.
		POOL=$POOL
		CURSOR=$1
		UPDATED=$(date '+%Y-%m-%dT%H:%M:%S')
	EOF
	mv "$state_tmp" "$STATE_FILE" || die "cannot update '$STATE_FILE'"
}

#
# Report whether the pool has a checkpoint:
#
#	0  it has one (or is still discarding one)
#	1  it has none
#	2  the state could not be determined
#
pool_has_checkpoint()
{
	ckpt_status=$(LC_ALL=C "$ZPOOL" status -j "$POOL" 2>&1)
	if [ $? -ne 0 ]; then
		warn "'$ZPOOL status -j $POOL' failed: $ckpt_status"
		return 2
	fi
	echo "$ckpt_status" | grep -q '"checkpoint_stats"'
}

take_checkpoint()
{
	pool_has_checkpoint
	case $? in
	0)
		die "pool '$POOL' already has a checkpoint. Refusing to run (and to discard somebody else's checkpoint)"
		;;
	2)
		die "cannot read the status of pool '$POOL'"
		;;
	esac
	log "taking a checkpoint of pool '$POOL'"
	CKPT_OWNED=1
	"$ZPOOL" checkpoint "$POOL"
	if [ $? -ne 0 ]; then
		CKPT_OWNED=0
		die "cannot take a checkpoint of pool '$POOL'"
	fi
}

discard_our_checkpoint()
{
	[ "$CKPT_OWNED" -eq 1 ] || return 0
	pool_has_checkpoint
	if [ $? -eq 1 ]; then
		CKPT_OWNED=0
		return 0
	fi
	log "discarding the checkpoint of pool '$POOL'"
	"$ZPOOL" checkpoint -d -w "$POOL" || return 1
	CKPT_OWNED=0
}

# HUP/INT/TERM land here. They interrupt the "wait" in run_zdb and the
# breathing sleep.
handle_signal()
{
	if [ -n "$CHILD_PID" ]; then
		kill "$CHILD_PID" 2>/dev/null
		wait "$CHILD_PID" 2>/dev/null
	fi
	exit "$1"
}

cleanup()
{
	rc=$?
	trap - EXIT
	trap '' HUP INT TERM PIPE
	discard_our_checkpoint
	if [ $? -ne 0 ]; then
		warn "FAILED to discard the checkpoint of pool '$POOL'. Discard it manually with '$ZPOOL checkpoint -d -w $POOL'"
		if [ "$rc" -eq 0 ]; then
			rc=1
		fi
	fi
	exit "$rc"
}

run_zdb()
{
	log "running: $ZDB -cLk $ZDB_OPTS $* $POOL"

	(
		if [ -n "$MEMLIMIT_KB" ]; then
			ulimit -v "$MEMLIMIT_KB" || exit 1
		fi
		exec "$ZDB" -cLk $ZDB_OPTS "$@" "$POOL"
	) &

	CHILD_PID=$!
	wait "$CHILD_PID"
	zdb_rc=$?
	CHILD_PID=
	return "$zdb_rc"
}

do_full()
{
	take_checkpoint
	run_zdb || die "zdb verification of pool '$POOL' FAILED"
	discard_our_checkpoint ||
	    die "cannot discard the checkpoint of pool '$POOL'"
	log "full scrub of the checkpointed state of pool '$POOL' completed (txg $TARGET_TXG)"
	write_state "$TARGET_TXG"
}

do_incremental()
{
	load_state
	if [ "$CURSOR" -ge "$TARGET_TXG" ]; then
		log "nothing to do: cursor $CURSOR >= pool txg $TARGET_TXG"
		return 0
	fi
	while [ "$CURSOR" -lt "$TARGET_TXG" ]; do
		window_top=$((CURSOR + STEP))
		if [ "$window_top" -gt "$TARGET_TXG" ]; then
			window_top=$TARGET_TXG
		fi
		take_checkpoint
		log "scrubbing txg window ($CURSOR, $window_top] of pool '$POOL'"
		run_zdb --scrub-min-txg="$((CURSOR + 1))" \
		    --scrub-max-txg="$window_top" ||
		    die "zdb verification of pool '$POOL' FAILED in txg window ($CURSOR, $window_top]; cursor stays at $CURSOR"
		discard_our_checkpoint ||
		    die "cannot discard the checkpoint of pool '$POOL'"
		CURSOR=$window_top
		write_state "$CURSOR"
		log "window done, cursor now $CURSOR of $TARGET_TXG"
		if [ "$ONE_WINDOW" -eq 1 ]; then
			log "single window mode, stopping"
			break
		fi
		if [ "$CURSOR" -lt "$TARGET_TXG" ] &&
		    [ "$BREATH" -gt 0 ]; then
			log "breathing for $BREATH seconds"
			# Backgrounded like zdb so signals are not
			# postponed until the sleep runs out.
			sleep "$BREATH" &
			CHILD_PID=$!
			wait "$CHILD_PID"
			CHILD_PID=
		fi
	done
}

opt_mode=
opt_step=
opt_breath=
opt_mem=
opt_state=

while getopts '1b:c:fhiM:Rs:S:' opt; do
	case $opt in
	1)	ONE_WINDOW=1 ;;
	b)	opt_breath=$OPTARG ;;
	c)	CONFIG_FILE=$OPTARG ;;
	f)	opt_mode=full ;;
	i)	opt_mode=incremental ;;
	M)	opt_mem=$OPTARG ;;
	R)	RESET_STATE=1 ;;
	s)	opt_step=$OPTARG ;;
	S)	opt_state=$OPTARG ;;
	h)	usage 0 ;;
	*)	usage 2 >&2 ;;
	esac
done
shift $((OPTIND - 1))

if [ "$(uname -s)" != "Linux" ]; then
	die "this script relies on Linux ulimit/zdb behavior; Linux only"
fi

if [ -n "$CONFIG_FILE" ]; then
	load_config "$CONFIG_FILE"
fi

# The command line overrides the config file.
[ "$ONE_WINDOW" -eq 0 ] || [ -n "$opt_mode" ] || opt_mode=incremental
[ -z "$opt_mode" ] || MODE=$opt_mode
[ -z "$opt_step" ] || STEP=$opt_step
[ -z "$opt_breath" ] || BREATH=$opt_breath
[ -z "$opt_mem" ] || MEMLIMIT_KB=$opt_mem
[ -z "$opt_state" ] || STATE_FILE=$opt_state

if [ $# -gt 0 ]; then
	POOL=$1
	shift
fi
[ $# -eq 0 ] || usage 2 >&2
if [ -z "$POOL" ]; then
	die "no pool given (pass it as an operand or as POOL= in the config)"
fi

case $MODE in
full|incremental)
	;;
*)
	die "invalid MODE '$MODE' (expected 'full' or 'incremental')"
	;;
esac
if ! is_uint "$STEP" || [ "$STEP" -eq 0 ]; then
	die "STEP must be a positive integer, got '$STEP'"
fi
is_uint "$BREATH" || die "BREATH must be a non-negative integer, got '$BREATH'"
if [ -n "$MEMLIMIT_KB" ]; then
	is_uint "$MEMLIMIT_KB" ||
	    die "memory limit must be a non-negative integer (kilobytes), got '$MEMLIMIT_KB'"
	( ulimit -v "$MEMLIMIT_KB" ) 2>/dev/null ||
	    die "cannot set the virtual memory limit to $MEMLIMIT_KB KB"
fi
if [ -z "$STATE_FILE" ]; then
	mkdir -p "$STATE_DIR" ||
	    die "cannot create state directory '$STATE_DIR'"
	STATE_FILE="$STATE_DIR/$POOL.state"
fi

check_state_file_owner

if [ "$RESET_STATE" -eq 1 ]; then
	rm -f "$STATE_FILE"
fi

TARGET_TXG=$("$ZDB" -u "$POOL" | awk '$1 == "txg" {print $3; exit}')
is_uint "$TARGET_TXG" ||
    die "cannot determine the current txg of pool '$POOL'"

trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 141' PIPE

case $MODE in
full)
	do_full
	;;
incremental)
	do_incremental
	;;
esac

exit 0
