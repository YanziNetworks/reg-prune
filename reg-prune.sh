#!/bin/sh

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

DRYRUN=0
VERBOSE=0
IMAGES=
TAGS=".*"
AGE=3mo
REPO=
AUTH=
AUTH_URL=
REG=
DOCKER_REG=jess/reg:v0.16.0;       # Note: dev. in flux, pick your version carefully
if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# ./bin/nexus/cleaner.sh --auth-file ./secrets/nexus/backup.ath --verbose --dry-run --images 'yanzi\/(linkserver-maven$|fiona-maven$|pan-shrek$|pan-shrek-app-prod$|pan-shrek-exp$)' --tags '(RC|pre|SNAPSHOT)' --reg nexus.yanzinetworks.com

# Print usage on stderr and exit
usage() {
	[ -n "$1" ] && echo "$1" >/dev/stderr
    exitcode="${2:-1}"
    cat <<USAGE >/dev/stderr

Description:

  $cmdname will remove Docker images at a registry. Deletion based on combination
  of name and tag regular expression, and image age

Usage:
  $cmdname [-option arg --long-option(=)arg] [--] command

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    -v | --verbose      Be more verbose
    -n | --dry(-)run    Do not delete, simply show what would be done.
    -i | --image(s)     Regular expression to select image names to delete (defaults
                        to none)
    -t | --tag(s)       Regular expression to select tag names to delete (defaults
                        to all, i.e. .*)
    -g | --age          Age of images to delete, in seconds. Can be expressed in
                        human-readable format. Default to 3mo, i.e. 3 months.
    -r | --reg(istry)   URL to remote registry.
    -a | --auth         Colon separated username and password to authorise at
                        remote registry.
	--auth-file			Same as --auth, but path to file with content
	--auth-url			Separate URL for authorisation
	--reg(-)bin			Full path to reg binary or alternative command (default:
						empty, meaning binary in path or Docker container when not
						found)

  Any command after the (optional) final double-dash will be run once cleanup has
  finished.

Details:
  Most of the nitty-gritty work is perform by the wonderful reg from Jessie
  Frazelle, https://github.com/genuinetools/reg. By default, this script will look
  for an installed version of reg, but can also use a Docker container when reg is
  not found in the PATH.

Example:
  The following command would remove all pre-release images that are more than 2 months
  old at the registry r.j3ss.co, provided colon-separated authorisation details in the
  (preferrably read only by you!) file at ./secrets/backup.ath

  $0 --auth-file ./secrets/backup.ath --verbose --images '.*' --tags '(RC|pre|SNAPSHOT)' --age 2mo --repo r.j3ss.co

USAGE
    exit "$exitcode"
}


while [ $# -gt 0 ]; do
    case "$1" in
    -v | --verbose)
        VERBOSE=1; shift 1;;

    -i | --image | --images)
        IMAGES="$2"; shift 2;;
    --image=* | --images=*)
        IMAGES="${1#*=}"; shift 1;;

    -t | --tag | --tags)
        TAGS="$2"; shift 2;;
    --tag=* | --tags=*)
        TAGS="${1#*=}"; shift 1;;

    -g | --age)
        AGE="$2"; shift 2;;
    --age=*)
        AGE="${1#*=}"; shift 1;;

    -n | --dryrun | --dry-run)
        DRYRUN=1; shift 1;;

    -r | --reg | --registry)
        REPO="$2"; shift 2;;
    --reg=* | --registry=*)
        REPO="${1#*=}"; shift 1;;

    -a | --auth | --authorisation | --authorization)
        AUTH="$2"; shift 2;;
    --auth=* | --authorisation=* | --authorization=*)
        AUTH="${1#*=}"; shift 1;;

    --auth-file | --authorisation-file | --authorization-file)
        AUTH=$(cat "$2"); shift 2;;
    --auth-file=* | --authorisation-file=* | --authorization-file=*)
        AUTH=$(cat "${1#*=}"); shift 1;;

    --auth-url)
        AUTH_URL=$(cat "$2"); shift 2;;
    --auth-url=*)
        AUTH_URL=$(cat "${1#*=}"); shift 1;;

    --reg-bin | --regbin)
        REG="$2"; shift 2;;
    --reg-bin=* | --regbin=*)
        REG="${1#*=}"; shift 1;;

    --non-interactive | --no-colour | --no-color)
        INTERACTIVE=0; shift 1;;

    -h | --help)
        usage; exit;;

    --)
        shift; break;;

    -*)
        usage "$1 not a known option!"; exit;;

    *)
        break;;

    esac
done

green() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;32m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

red() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;40m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

yellow() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;33m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

blue() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;34m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

# Conditional logging
verbose() {
    if [ "$VERBOSE" = "1" ]; then
        echo "[$(blue "$appname")] [$(yellow info)] [$(date +'%Y%m%d-%H%M%S')] $1" >/dev/stderr
    fi
}

warn() {
    echo "[$(blue "$appname")] [$(red WARN)] [$(date +'%Y%m%d-%H%M%S')] $1" >/dev/stderr
}

abort() {
	warn "$1"
	exit 1
}


howlong() {
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[yY]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[yY].*/\1/p')
        expr "$len" \* 31536000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Mm][Oo]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Oo].*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*m'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*m.*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Ww]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ww].*/\1/p')
        expr "$len" \* 604800
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Dd]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Dd].*/\1/p')
        expr "$len" \* 86400
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Hh]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Hh].*/\1/p')
        expr "$len" \* 3600
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Mm][Ii]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Ii].*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*M'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*M.*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Ss]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ss].*/\1/p')
        echo "$len"
        return
    fi
    if echo "$1"|grep -E '[0-9]+'; then
        echo "$1"
        return
    fi
}

human(){
    t=$1

    d=$((t/60/60/24))
    h=$((t/60/60%24))
    m=$((t/60%60))
    s=$((t%60))

    if [ $d -gt 0 ]; then
            [ $d = 1 ] && printf "%d day " $d || printf "%d days " $d
    fi
    if [ $h -gt 0 ]; then
            [ $h = 1 ] && printf "%d hour " $h || printf "%d hours " $h
    fi
    if [ $m -gt 0 ]; then
            [ $m = 1 ] && printf "%d minute " $m || printf "%d minutes " $m
    fi
    if [ $d = 0 ] && [ $h = 0 ] && [ $m = 0 ]; then
            [ $s = 1 ] && printf "%d second" $s || printf "%d seconds" $s
    fi
    printf '\n'
}


# Returns the number of seconds since the epoch for the ISO8601 date passed as
# an argument. This will only recognise a subset of the standard, i.e. dates
# with milliseconds, microseconds, nanoseconds or none specified, and timezone
# only specified as diffs from UTC, e.g. 2019-09-09T08:40:39.505-07:00 or
# 2019-09-09T08:40:39.505214+00:00. The special Z timezone (i.e. UTC) is also
# recognised. The implementation actually computes the ms/us/ns whenever they
# are available, but discards them.
iso8601() {
    # Arrange for ns to be the number of nanoseconds.
    ds=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\8/')
    ns=0
    if [ -n "$ds" ]; then
        if [ "${#ds}" = "10" ]; then
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$ds
        elif [ "${#ds}" = "7" ]; then
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$((1000*ds))
        else
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$((1000000*ds))
        fi
    fi


    # Arrange for tzdiff to be the number of seconds for the timezone.
    tz=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\9/')
    tzdiff=0
    if [ -n "$tz" ]; then
        if [ "$tz" = "Z" ]; then
            tzdiff=0
        else
            hrs=$(printf "%d" "$(echo "$tz" | sed -E 's/[+-]([0-9]{2}):([0-9]{2})/\1/')")
            mns=$(printf "%d" "$(echo "$tz" | sed -E 's/[+-]([0-9]{2}):([0-9]{2})/\2/')")
            sign=$(echo "$tz" | sed -E 's/([+-])([0-9]{2}):([0-9]{2})/\1/')
            secs=$((hrs*3600+mns*60))
            if [ "$sign" = "-" ]; then
                tzdiff=$((-secs))
            else
                tzdiff=$secs
            fi
        fi
    fi

    # Extract UTC date and time into something that date can understand, then
    # add the number of seconds representing the timezone.
    utc=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\1-\2-\3 \4:\5:\6/')
    if [ "$(uname -s)" = "Darwin" ]; then
        secs=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$utc" +"%s")
    else
        secs=$(date -u -d "$utc" +"%s")
    fi
    expr "$secs" + \( "$tzdiff" \)
}

locate_keyword() {
    expr $(echo "$1"|awk "END{print index(\$0,\"$2\")}"|head -n 1) - $(echo "$2"|wc -c)
}


######## START of inlined JSON parser from: https://github.com/rcrowley/json.sh

# Copyright 2011 Richard Crowley. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     1.  Redistributions of source code must retain the above copyright
#         notice, this list of conditions and the following disclaimer.
#
#     2.  Redistributions in binary form must reproduce the above
#         copyright notice, this list of conditions and the following
#         disclaimer in the documentation and/or other materials provided
#         with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY RICHARD CROWLEY AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL RICHARD CROWLEY OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation
# are those of the authors and should not be interpreted as representing
# official policies, either expressed or implied, of Richard Crowley.

# Most users will be happy with the default '/' separator that makes trees
# of keys look like filesystem paths but that breaks down if keys can
# contain slashes.  In that case, set `JSON_SEPARATOR` to desired character.
[ -z "$JSON_SEPARATOR" ] && _J_S="/" || _J_S="$JSON_SEPARATOR"

# File descriptor 3 is commandeered for debug output, which may end up being
# forwarded to standard error.
[ -z "$JSON_DEBUG" ] && exec 3>/dev/null || exec 3>&2

# File descriptor 4 is commandeered for use as a sink for literal and
# variable output of (inverted) sections that are not destined for standard
# output because their condition is not met.
exec 4>/dev/null

# Consume standard input one character at a time to parse JSON.
json() {

	# Initialize the file descriptor to be used to emit characters.  At
	# times this value will be 4 to send output to `/dev/null`.
	_J_FD=1

	# Initialize storage for the "pathname", the concatenation of all
	# the keys in the tree at any point in time, the current state of
	# the machine, and the state to which the machine returns after
	# completing a key or value.
	_J_PATHNAME="$_J_S" _J_STATE="whitespace" _J_STATE_DEFAULT="whitespace"

	# IFS must only contain '\n' so as to be able to read space and tab
	# characters from standard input one-at-a-time.  The easiest way to
	# convince it to actually contain the correct byte, and only the
	# correct byte, is to use a single-quoted literal newline.
	IFS='
'

	# Consuming standard input one character at a time is quite a feat
	# within the confines of POSIX shell.  Bash's `read` builtin has
	# `-n` for limiting the number of characters consumed.  Here it is
	# faked using `sed`(1) to place each character on its own line.
	# The subtlety is that real newline characters are chomped so they
	# must be indirectly detected by checking for zero-length
	# characters, which is done as the character is emitted.
	sed "
		s/./&$(printf "\036")/g
		s/\\\\/\\\\\\\\/g
	" | tr "\036" "\n" | _json

	# TODO Replace the original value of IFS.  Be careful if it's unset.

}

# Consume the one-character-per-line stream from `sed` via a state machine.
# This function will be called recursively in subshell environments to
# isolate values from their containing scope.
#
# The `read` builtin consumes one line at a time but by now each line
# contains only a single character.
_json() {
	while read _J_C
	do
		_json_char
		_J_PREV_C="$_J_C"
	done
}

# Consume a single character as stored in `_J_C`.  This function is broken
# out from `_json` so it may be called to reconsume a character as is
# necessary following the end of any number since numbers do not have a
# well-known ending in the grammar.
#
# The state machine implemented here follows very naturally from the
# diagrams of the JSON grammar on <http://json.org>.
_json_char() {
	echo " _J_C: $_J_C (${#_J_C}), _J_STATE: $_J_STATE" >&3
	case "$_J_STATE" in

		# The machine starts in the "whitespace" state and learns
		# from leading characters what state to enter next.  JSON's
		# grammar doesn't contain any tokens that are ambiguous in
		# their first character so the parser's job is relatively
		# easier.
		#
		# Further whitespace characters are consumed and ignored.
		#
		# Arrays are unique in that their parsing rules are a strict
		# superset of the rules in open whitespace.  When an opening
		# bracket is encountered, the remainder of the array is
		# parsed in a subshell which goes around again when a comma
		# is encountered and exits back to the containing scope when
		# the closing bracket is encountered.
		#
		# Objects are not parsed as a superset of open whitespace but
		# they are parsed in a subshell to protect the containing scope.
		"array-0"|"array-even"|"array-odd"|"whitespace")
			case "$_J_STATE" in
				"array-0")
					case "$_J_C" in
						"]") exit;;
					esac;;
				"array-even")
					case "$_J_C" in
						",")
							_J_DIRNAME="${_J_PATHNAME%"$_J_S"*}"
							[ "$_J_DIRNAME" = "$_J_S" ] && _J_DIRNAME=""
							_J_BASENAME="${_J_PATHNAME##*"$_J_S"}"
							_J_BASENAME="$(($_J_BASENAME + 1))"
							_J_PATHNAME="$_J_DIRNAME$_J_S$_J_BASENAME"
							_J_STATE="array-odd"
							continue;;
						"]") exit;;
					esac;;
			esac
			case "$_J_C" in
				"\"") _J_STATE="string" _J_V="";;
				"-") _J_STATE="number-negative" _J_V="$_J_C";;
				0) _J_STATE="number-leading-zero" _J_V="$_J_C";;
				[1-9]) _J_STATE="number-leading-nonzero" _J_V="$_J_C";;
				"[")
					(
						[ "$_J_PATHNAME" = "/" ] && _J_PATHNAME=""
						_J_PATHNAME="$_J_PATHNAME/0"
						_J_STATE="array-0" _J_STATE_DEFAULT="array-even"
						_json
					)
					_J_STATE="$_J_STATE_DEFAULT" _J_V="";;
				"f"|"t") _J_STATE="boolean" _J_V="$_J_C";;
				"n") _J_STATE="null" _J_V="$_J_C";;
				"{")
					(
						_J_STATE="object-0" _J_STATE_DEFAULT="object-even"
						_json
					)
					_J_STATE="$_J_STATE_DEFAULT" _J_V="";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Boolean values are multicharacter literals but they're unique
		# from their first character.  This means the eventual value is
		# already known when the "boolean" state is entered so we can
		# raise syntax errors as soon as the input goes south.
		"boolean")
			case "$_J_V$_J_C" in
				"f"|"fa"|"fal"|"fals"|"t"|"tr"|"tru") _J_V="$_J_V$_J_C";;
				"false"|"true")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME boolean $_J_V$_J_C" >&$_J_FD;;
				*) _json_die "syntax: $_J_PATHNAME boolean $_J_V$_J_C";;
			esac;;

		# Object values are relatively more complex than array values.
		# They begin in the "object-0" state, which is almost but not
		# quite a subset of the "whitespace" state for strings.  When
		# a string is encountered it is parsed as usual but the parser
		# is set to return to the "object-value" state afterward.
		#
		# As in the "whitespace" state, extra whitespace characters
		# are consumed and ignored.
		#
		# The parser will return to this "object" state later to
		# either consume a comma and go around again or exit the
		# subshell in which this object has been parsed.
		"object-0")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				"}") exit;;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# "object-even" is like "object-0" but additionally commas are
		# consumed to enforce the another key/value pair is coming.
		"object-even")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				",") _J_STATE="object-odd";;
				"}") exit;;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Object values have to return from whence they came.  They use
		# the "object-exit" state to signal the last character consumed
		# to the containing scope.
		"object-exit") #exit;;
			case "$_J_C" in
				",") exit 101;;
				"}") exit 102;;
				*) exit 0;;
			esac;;

		# "object-even" is like "object-0" but cannot consume a closing
		# brace because it has just consumed a comma.
		"object-odd")
			case "$_J_C" in
				"\"")
					_J_FD=4
					_J_STATE="string"
					_J_STATE_DEFAULT="object-value"
					_J_V="";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# After a string key has been consumed, the state machine
		# progresses here where a colon and a value are parsed.  The
		# value is parsed in a subshell so the pathname can have the
		# key appended to it before the parser continues.
		"object-value")
			case "$_J_C" in
				":")
					_J_FD=1
					(
						[ "$_J_PATHNAME" = "/" ] && _J_PATHNAME=""
						_J_PATHNAME="$_J_PATHNAME/$_J_V"
						_J_STATE="whitespace"
						_J_STATE_DEFAULT="object-exit"
						_json
					) || case "$?" in
						101) _J_STATE="object-even" _J_C="," _json_char;;
						102) _J_STATE="object-even" _J_C="}" _json_char;;
					esac
					_J_STATE="object-even";;
				"	"|""|" ") ;;
				*) _json_die "syntax: $_J_PATHNAME";;
			esac;;

		# Null values work exactly like boolean values.  See above.
		"null")
			case "$_J_V$_J_C" in
				"n"|"nu"|"nul") _J_V="$_J_V$_J_C";;
				"null")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME null null" >&$_J_FD;;
				*) _json_die "syntax: $_J_PATHNAME null $_J_V$_J_C";;
			esac;;

		# Numbers that encounter a '.' become floating point and may
		# continue consuming digits forever or may become
		# scientific-notation.  Any other character sends the parser
		# back to its default state.
		"number-float")
			case "$_J_C" in
				[0-9]) _J_V="$_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first digit consumed is non-zero.  From here, a number
		# may continue on a positive integer, become a floating-point
		# number by consuming a '.', or become scientific-notation by
		# consuming an 'E' or 'e'.  Any other character sends the
		# parser back to its default state.
		"number-leading-nonzero")
			case "$_J_C" in
				".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
				[0-9]) _J_V="$_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first digit consumed is zero.  From here, a number
		# may remain zero, become a floating-point number by
		# consuming a '.', or become scientific-notation by consuming
		# an 'E' or 'e'.  Any other character sends the parser back
		# to its default state.
		"number-leading-zero")
			case "$_J_C" in
				".") _J_STATE="number-float" _J_V="$_J_V$_J_C";;
				[0-9]) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
				"E"|"e") _J_STATE="number-sci" _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# This is an entrypoint into parsing a number, used when
		# the first character consumed is a '-'.  From here, a number
		# may progress to the "number-leading-nonzero" or
		# "number-leading-zero" states.  Any other character sends
		# the parser back to its default state.
		"number-negative")
			case "$_J_C" in
				0) _J_STATE="number-leading-zero" _J_V="$_J_V$_J_C";;
				[1-9])
					_J_STATE="number-leading-nonzero"
					_J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# Numbers that encounter an 'E' or 'e' become
		# scientific-notation and consume digits, optionally prefixed
		# by a '+' or '-', forever.  The actual consumption is
		# delegated to the "number-sci-neg" and "number-sci-pos"
		# states.  Any other character immediately following the 'E'
		# or 'e' is a syntax error.
		"number-sci")
			case "$_J_C" in
				"+") _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
				"-") _J_STATE="number-sci-neg" _J_V="$_J_V$_J_C";;
				[0-9]) _J_STATE="number-sci-pos" _J_V="$_J_V$_J_C";;
				*) _json_die "syntax: $_J_PATHNAME number $_J_V$_J_C";;
			esac;;

		# Once in these states, numbers may consume digits forever.
		# Any other character sends the parser back to its default
		# state.
		"number-sci-neg"|"number-sci-pos")
			case "$_J_C" in
				[0-9]) _J_V="$_J_V$_J_C";;
				*)
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME number $_J_V" >&$_J_FD
					_json_char;;
			esac;;

		# Strings aren't as easy as they look.  JSON supports several
		# escape sequences that require the state machine to keep a
		# history of its input.  Basic backslash/newline/etc. escapes
		# are simple because they only require one character of
		# history.  Unicode codepoint escapes require more.  The
		# strategy there is to add states to the machine.
		#
		# TODO It'd be nice to decode all escape sequences, including
		# Unicode codepoints but that would definitely ruin the
		# line-oriented thing we've got goin' on.
		"string")
			case "$_J_PREV_C$_J_C" in
				"\\\""|"\\/"|"\\\\") _J_V="$_J_V$_J_C";;
				"\\b"|"\\f"|"\\n"|"\\r")  _J_V="$_J_V\\\\$_J_C";;
				"\\u") _J_V="$_J_V\\\\$_J_C";;
				*"\"")
					_J_STATE="$_J_STATE_DEFAULT"
					echo "$_J_PATHNAME string $_J_V" >&$_J_FD;;
				*"\\") ;;
				*) _J_V="$_J_V$_J_C";;
			esac;;

	esac
}

# Print an error message and GTFO.  The message is the concatenation
# of all the arguments to this function.
_json_die() {
	echo "json.sh: $*" >&2
	exit 1
}

######## END of inlined JSON parser

# Call reg with a command, insert various authorisation details whenever
# necessary.
reg() {
	cmd=$1; shift 1;

	runreg="$REG $cmd"
	[ -n "$AUTH_URL" ] && runreg="$runreg --auth-url $AUTH_URL"
	if [ -n "$USERNAME" ]; then
		runreg="$runreg --username $USERNAME"
		[ -n "$PASSWORD" ] && runreg="$runreg --password $PASSWORD"
	fi
	$runreg "$@"
}

rm_image() {
    if [ "$DRYRUN" = "1" ]; then
        if [ -z "$2" ]; then
            verbose "Would remove image $(yellow "$1")"
		else
            verbose "Would remove image $(yellow "$1"), $(human $2)old"
		fi
    else
        if [ -z "$2" ]; then
            verbose "Removing image $(red "$1")"
        else
			verbose "Removing image $(red "$1"), $(human $2)old"
		fi
        reg rm "${REPO%/}/$1"
    fi
}

[ -z "$REPO" ] && usage "You must provide a registry through --reg(istry) option!"

# Convert period
if echo "$AGE"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
    NEWAGE=$(howlong "$AGE")
    verbose "Converted human-readable age $AGE to $NEWAGE seconds"
    AGE=$NEWAGE
fi

# Failover to a transient Docker container whenever the reg binary is not found
# in the PATH. Note that this automatically mounts your .docker directory into
# the container so as to give a chance to the reg binary in the container to
# find your credentials. This will not work in all settings and might not be
# something that you want from a security standpoint.
if [ -z "$REG" ]; then
	if [ -x "$(command -v reg)" ]; then
		REG=$(command -v reg)
	elif [ -x "$(which reg)" ]; then
		REG=$(which reg)
	else
		warn "Will run reg as a Docker container using $DOCKER_REG"
		REG="docker run -i --rm -v $HOME/.docker:/root/.docker:ro $DOCKER_REG"
	fi
fi

# Initialise globals used below or in called functions
now=$(date -u +'%s');    # Will do with once and not everytime!
USERNAME=$(echo "$AUTH" | cut -d':' -f1)
PASSWORD=$(echo "$AUTH" | cut -d':' -f2)

# Get the inventory, locate the real header line and guess where the name of the
# image will end. Starting from that line, cut away anything else than the name
# of the image at the beginning and only keep the ones that match the official
# regexp for image names.
verbose "Listing all images and tags at $REPO"
inventory=$(reg ls "$REPO")
header=$(printf "%s" "$inventory" | grep -E "REPO\s+TAGS")
tags_col=$(locate_keyword "$header" "TAGS")
start=$(printf "%s" "$inventory" | grep -En "REPO\s+TAGS" | cut -d':' -f1)
for name in $(printf "%s" "$inventory" | tail -n +$((start+1)) | cut -c1-$((tags_col-1)) | sed -E 's/\s+$//g' | grep -Eo '^([a-z0-9]+([._]|__|[-]|[a-z0-9])*(\/[a-z0-9]+([._]|__|[-]|[a-z0-9])*)*)'); do
    if echo "$name" | grep -Eq "$IMAGES"; then
        verbose "Selecting among tags of image $name"
        for tag in $(reg tags "${REPO%/}/${name}"); do
            if echo "$tag" | grep -Eq "$TAGS"; then
                if [ -n "$AGE" ]; then
                    verbose "Checking age of ${name}:${tag}"
                    # Get the sha256 of the config layer, which is a JSON file
                    config=$(reg manifest "${REPO%/}/${name}:${tag}" | json | grep '/config/digest' | awk '{print $3}')
                    # Extract the layer, parse its JSON and look for the image creation date, in ISO8601 format
                    creation=$(reg layer "${REPO%/}/${name}:${tag}@${config}" | json | grep -E '^/created\s+' | awk '{print $3}')
                    howold=$((now-$(iso8601 "$creation")))
                    if [ "$howold" -lt "$AGE" ]; then
                        verbose "Keeping $(green "${name}:${tag}"), $(human "$howold")old"
                    else
                        rm_image "${name}:${tag}" "$howold"
                    fi
                else
                    rm_image "${name}:${tag}"
                fi
            else
                verbose "Skipping ${name}:${tag}, tag does not match $TAGS"
            fi
        done
    else
        verbose "Skipping $name, name does not match $IMAGES"
    fi
done

# Execute remaining arguments as a command, if any
if [ $# -ne "0" ]; then
    verbose "Executing $*"
    exec "$@"
fi