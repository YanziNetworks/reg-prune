#!/usr/bin/env sh

# Pick relevant yu.sh modules at once.
ROOT_DIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )
[ -d "$ROOT_DIR/yu.sh" ] && YUSH_DIR="$ROOT_DIR/yu.sh"
[ -z "$YUSH_DIR" ] && [ -d "$ROOT_DIR/../lib/yu.sh" ] && YUSH_DIR="$ROOT_DIR/../lib/yu.sh"
[ -z "$YUSH_DIR" ] && echo "Cannot find yu.sh root!" >/dev/stderr && exit 1
# shellcheck disable=SC1091
. "$YUSH_DIR/log.sh"
# shellcheck disable=SC1091
. "$YUSH_DIR/date.sh"
# shellcheck disable=SC1091
. "$YUSH_DIR/json.sh"

# Set this to 1 to only show what would be done without actually removing images
# from the remote registry.
REGPRUNE_DRYRUN=${REGPRUNE_DRYRUN:-0}

# This is a regular expression that image names should match to be considered
# for deletion. The default is an empty string, meaning no image will match and
# this utility will do no harm!
REGPRUNE_IMAGES=${REGPRUNE_IMAGES:-}

# This is a regular expression that tag names should match to be considered
# for deletion. The default is to match all possible tags!
REGPRUNE_TAGS=${REGPRUNE_TAGS:-".*"}

# A regular expression to exclude tags from the ones that would otherwise have
# been considered. The default is an empty string, meaning none of the selected
# tags will be excluded.
REGPRUNE_EXCLUDE=${REGPRUNE_EXCLUDE:-}

# Only images older than this age will be considered for removal. The age is
# computed out of the creation date for the images. Human-readable strings can
# be used to express the age.
REGPRUNE_AGE=${REGPRUNE_AGE:-3mo}

# Will only keep this number of latest images matching the tags. Image counting
# will happen per image, not per tag, so this might remove a whole lot more than
# what you think it would! The age needs to be an empty string for this
# parameter to be taken into account and this variable needs to be a positive
# integer.
REGPRUNE_LATEST=${REGPRUNE_LATEST:-1}

# This is the path to the remote registry, i.e. hub.docker.io or similar.
REGPRUNE_REGISTRY=${REGPRUNE_REGISTRY:-}

# This can contain a colon separated pair of a username and password for that
# user. Note however that reg is able to read this information from your local
# environment. When reg is used as a docker container, your local environment is
# passed to the container so that reg can perform the same check.
REGPRUNE_AUTH=${REGPRUNE_AUTH:-}

# Set this to be able to authorise at registries that rely on a separate URL for
# authentication. The Docker registry is one of those registries and requires
# auth.docker.io for authentication to work properly.
REGPRUNE_AUTH_URL=${REGPRUNE_AUTH_URL:-}

# Specific path to the reg utility. When empty, the binary called reg will be
# looked in the path and used if found, otherwise this script will default to
# using a Docker container when interfacing with the remote registry.
REGPRUNE_REG_BIN=${REGPRUNE_REG_BIN:-}

# Specific path to the jq utility. When not found, an internal JSON parser will
# be used. The parser is slow and sometimes buggy, but works in most cases.
REGPRUNE_JQ=${REGPRUNE_JQ:-jq}

# Specific opts to blindly pass to all calls to the reg utility. This can be
# used to specify some of the global flags supported by reg.
REGPRUNE_REG_OPTS=${REGPRUNE_REG_OPTS:-}

# Docker image to use when reg is not available at the path. Note: dev. in flux,
# pick your version carefully
REGPRUNE_DOCKER_REG=${REGPRUNE_DOCKER_REG:-jess/reg:v0.16.0};

# Print usage on stderr and exit
usage() {
	[ -n "$1" ] && echo "$1" >/dev/stderr
    exitcode="${2:-1}"
    cat <<USAGE >/dev/stderr

Description:

  $YUSH_APPNAME will remove Docker images at a registry. Deletion is based on a
  combination of regular expression matching names and tags, and images age.

Usage:
  $(basename "$0") [-option arg --long-option(=)arg] [--] command

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    -v | --verbose      Set verbosity level: debug, info (default), notice, warn or
                        error
    -n | --dry(-)run    Do not delete, simply show what would be done.
    -i | --image(s)     Regular expression to select image names to delete (defaults
                        to none)
    -t | --tag(s)       Regular expression to select tag names to delete (defaults
                        to all, i.e. .*)
    -e | --exclude      Regular expression to exclude some of the tags selected
                        with the option above. Default to empty, no exclusion.
    -g | --age          Age of images to delete, in seconds. Can be expressed in
                        human-readable format. Default to 3mo, i.e. 3 months.
    -l | --latest       Keep this many images instead, among the youngest. This
                        only works when age is turned off (empty string).
    -r | --reg(istry)   URL to remote registry.
    -a | --auth         Colon separated username and password to authorise at
                        remote registry.
    --auth-file         Same as --auth, but path to file with content
    --auth-url          Separate URL for authorisation
    --reg(-)bin         Full path to reg binary or alternative command (default:
                        empty, meaning binary in path or Docker container when not
                        found)
    --reg(-)opts        List of options to blindly pass to reg tool

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

  $(basename "$0") --auth-file ./secrets/backup.ath --verbose --images '.*' --tags '(RC|pre|SNAPSHOT)' --age 2mo --repo r.j3ss.co

Complete Manual:
  https://github.com/YanziNetworks/reg-prune

USAGE
    exit "$exitcode"
}

while [ $# -gt 0 ]; do
    case "$1" in
    -v | --verbose | --verbosity)
        YUSH_LOG_LEVEL="$2"; shift 2;;
    --verbose=* | --verbosity=*)
        # shellcheck disable=SC2034 # This is declared in log.sh
        YUSH_LOG_LEVEL="${1#*=}"; shift 1;;

    -i | --image | --images)
        REGPRUNE_IMAGES="$2"; shift 2;;
    --image=* | --images=*)
        REGPRUNE_IMAGES="${1#*=}"; shift 1;;

    -t | --tag | --tags)
        REGPRUNE_TAGS="$2"; shift 2;;
    --tag=* | --tags=*)
        REGPRUNE_TAGS="${1#*=}"; shift 1;;

    -e | --exclude | --exclude-tag | --exclude-tags)
        REGPRUNE_EXCLUDE="$2"; shift 2;;
    --exclude=* | --exclude-tag=* | --exclude-tags=*)
        REGPRUNE_EXCLUDE="${1#*=}"; shift 1;;

    -g | --age)
        REGPRUNE_AGE="$2"; shift 2;;
    --age=*)
        REGPRUNE_AGE="${1#*=}"; shift 1;;

    -l | --latest)
        REGPRUNE_LATEST="$2"; shift 2;;
    --latest=*)
        REGPRUNE_LATEST="${1#*=}"; shift 1;;

    -n | --dryrun | --dry-run)
        REGPRUNE_DRYRUN=1; shift 1;;

    -r | --reg | --registry)
        REGPRUNE_REGISTRY="$2"; shift 2;;
    --reg=* | --registry=*)
        REGPRUNE_REGISTRY="${1#*=}"; shift 1;;

    -a | --auth | --authorisation | --authorization)
        REGPRUNE_AUTH="$2"; shift 2;;
    --auth=* | --authorisation=* | --authorization=*)
        REGPRUNE_AUTH="${1#*=}"; shift 1;;

    --auth-file | --authorisation-file | --authorization-file)
        REGPRUNE_AUTH=$(cat "$2"); shift 2;;
    --auth-file=* | --authorisation-file=* | --authorization-file=*)
        REGPRUNE_AUTH=$(cat "${1#*=}"); shift 1;;

    --auth-url)
        REGPRUNE_AUTH_URL=$(cat "$2"); shift 2;;
    --auth-url=*)
        REGPRUNE_AUTH_URL=$(cat "${1#*=}"); shift 1;;

    --reg-bin | --regbin)
        REGPRUNE_REG_BIN="$2"; shift 2;;
    --reg-bin=* | --regbin=*)
        REGPRUNE_REG_BIN="${1#*=}"; shift 1;;

    --reg-opts | --regopts)
        REGPRUNE_REG_OPTS="$2"; shift 2;;
    --reg-opts=* | --regopts=*)
        REGPRUNE_REG_OPTS="${1#*=}"; shift 1;;

    --jq)
        REGPRUNE_JQ="$2"; shift 2;;
    --jq=*)
        REGPRUNE_JQ="${1#*=}"; shift 1;;

    --non-interactive | --no-colour | --no-color)
        # shellcheck disable=SC2034 # This is declared in log.sh
        YUSH_LOG_COLOUR=0; shift 1;;

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

abort() {
	yush_error "$1"
	exit 1
}

locate_keyword() {
    expr $(echo "$1"|awk "END{print index(\$0,\"$2\")}"|head -n 1) - $(echo "$2"|wc -c)
}

# Call reg with a command, insert various authorisation details whenever
# necessary.
reg() {
	cmd=$1; shift 1;

	runreg="$REGPRUNE_REG_BIN $cmd"
	[ -n "$REGPRUNE_AUTH_URL" ] && runreg="$runreg --auth-url $REGPRUNE_AUTH_URL"
	if [ -n "$USERNAME" ]; then
		runreg="$runreg --username $USERNAME"
		[ -n "$PASSWORD" ] && runreg="$runreg --password $PASSWORD"
	fi
	[ -n "$REGPRUNE_REG_OPTS" ] && runreg="$runreg $REGPRUNE_REG_OPTS"
	$runreg "$@"
}

rm_image() {
    if [ "$REGPRUNE_DRYRUN" = "1" ]; then
        if [ -z "$2" ]; then
            yush_info "Would remove image $(yush_yellow "$1")"
		else
            yush_info "Would remove image $(yush_yellow "$1"), $(yush_human_period "$2")old"
		fi
    else
        if [ -z "$2" ]; then
            yush_notice "Removing image $(yush_red "$1")"
        else
			yush_notice "Removing image $(yush_red "$1"), $(yush_human_period "$2")old"
		fi
        reg rm "${REGPRUNE_REGISTRY%/}/$1"
    fi
}

creation_date() {
    yush_debug "Checking age of ${name}:${tag}"
    # Get the sha256 of the config layer, which is a JSON file
    if [ -n "$REGPRUNE_JQ" ]; then
        config=$(   reg manifest "$1" |
                    "$REGPRUNE_JQ" -crM .config.digest)
    else
        config=$(   reg manifest "$1" |
                    yush_json |
                    grep '/config/digest' | awk '{print $3}')
    fi
    if [ -z "$config" ]; then
        yush_warn "Cannot find config layer for $1!"
    else
        # Extract the layer, parse its JSON and look for the image creation date, in ISO8601 format
        if [ -n "$REGPRUNE_JQ" ]; then
            creation=$( reg layer "$1@${config}" |
                        "$REGPRUNE_JQ" -crM .created)
        else
            creation=$( reg layer "$1@${config}" |
                        yush_json |
                        grep -E '^/created\s+' | awk '{print $3}')
        fi
        printf %s\\n "$creation"
    fi
}


[ -z "$REGPRUNE_REGISTRY" ] && usage "You must provide a registry through --reg(istry) option!"

# Convert period
if echo "$REGPRUNE_AGE"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
    NEWAGE=$(yush_howlong "$REGPRUNE_AGE")
    yush_info "Converted human-readable age $REGPRUNE_AGE to $NEWAGE seconds"
    REGPRUNE_AGE=$NEWAGE
fi

# Failover to a transient Docker container whenever the reg binary is not found
# in the PATH. Note that this automatically mounts your .docker directory into
# the container so as to give a chance to the reg binary in the container to
# find your credentials. This will not work in all settings and might not be
# something that you want from a security standpoint.
if [ -z "$REGPRUNE_REG_BIN" ]; then
	if [ -x "$(command -v reg)" ]; then
		REGPRUNE_REG_BIN=$(command -v reg)
        yush_debug "Using reg accessible as $reg for registry operations"
	elif [ -x "$(which reg 2>/dev/null)" ]; then
		REGPRUNE_REG_BIN=$(which reg)
        yush_debug "Using reg accessible as $reg for registry operations"
	else
		yush_debug "Will run reg as a Docker container using $REGPRUNE_DOCKER_REG"
		REGPRUNE_REG_BIN="docker run -i --rm -v $HOME/.docker:/root/.docker:ro $REGPRUNE_DOCKER_REG"
	fi
fi

# When told to use jq, make sure we can access it or revert to setting REGPRUNE_JQ to an
# empty string, which will use the internal JSON parser instead.
if [ -n "$REGPRUNE_JQ" ]; then
	if [ -x "$(command -v "$REGPRUNE_JQ")" ]; then
		REGPRUNE_JQ=$(command -v "$REGPRUNE_JQ")
	elif [ -x "$(which "$REGPRUNE_JQ" 2>/dev/null)" ]; then
		REGPRUNE_JQ=$(which "$REGPRUNE_JQ")
    else
        yush_notice "Cannot find jq at $REGPRUNE_JQ, reverting to internal JSON parser"
        REGPRUNE_JQ=
    fi
fi

# Output some info over JSON parsing and jq as decision is automated (and might
# be wrong?)
if [ -z "$REGPRUNE_JQ" ]; then
    yush_debug "Using slow, shell-based and imprecise JSON parser"
else
    yush_debug "Using jq accessible as $REGPRUNE_JQ for JSON parsing"
fi

# Initialise globals used below or in called functions
now=$(date -u +'%s');    # Will do with once and not everytime!
USERNAME=$(echo "$REGPRUNE_AUTH" | cut -d':' -f1)
PASSWORD=$(echo "$REGPRUNE_AUTH" | cut -d':' -f2)

# Get the inventory, locate the real header line and guess where the name of the
# image will end. Starting from that line, cut away anything else than the name
# of the image at the beginning and only keep the ones that match the official
# regexp for image names.
yush_debug "Listing all images and tags at $REGPRUNE_REGISTRY"
inventory=$(reg ls "$REGPRUNE_REGISTRY")
header=$(printf "%s" "$inventory" | grep -E "REPO\s+TAGS")
tags_col=$(locate_keyword "$header" "TAGS")
start=$(printf "%s" "$inventory" | grep -En "REPO\s+TAGS" | cut -d':' -f1)
for name in $(printf "%s" "$inventory" |
                tail -n +$((start+1)) |
                cut -c1-$((tags_col-1)) |
                sed -E 's/\s+$//g' |
                grep -Eo '^([a-z0-9]+([._]|__|[-]|[a-z0-9])*(\/[a-z0-9]+([._]|__|[-]|[a-z0-9])*)*)'); do
    if [ -n "$REGPRUNE_IMAGES" ] && printf %s\\n "$name" | grep -Eqo "$REGPRUNE_IMAGES"; then
        yush_debug "Selecting among tags of image $name"
        # Create a temporary file to host the list of relevant images, together
        # with the creation date.
        by_dates=
        if [ -z "$REGPRUNE_AGE" ] && [ -n "$REGPRUNE_LATEST" ] && [ "$REGPRUNE_LATEST" -gt "0" ]; then
            by_dates=$(mktemp)
        fi
        for tag in $(reg tags "${REGPRUNE_REGISTRY%/}/${name}"); do
            if [ -n "$REGPRUNE_TAGS" ] && printf %s\\n "$tag" | grep -Eqo "$REGPRUNE_TAGS"; then
                if [ -n "$REGPRUNE_EXCLUDE" ] && printf %s\\n "$tag" | grep -Eqo "$REGPRUNE_EXCLUDE"; then
                    yush_info "Skipping ${name}:${tag}, tag excluded by $REGPRUNE_EXCLUDE"
                else
                    # When deletion should happen by age, compute the age of the
                    # image and remove it if relevant.
                    if [ -n "$REGPRUNE_AGE" ]; then
                        creation=$(creation_date "${REGPRUNE_REGISTRY%/}/${name}:${tag}")
                        if [ -z "$creation" ]; then
                            yush_warn "Cannot find creation date for ${REGPRUNE_REGISTRY%/}/${name}:${tag}!"
                        else
                            howold=$((now-$(yush_iso8601 "$creation")))
                            if [ "$howold" -lt "$REGPRUNE_AGE" ]; then
                                yush_info "Keeping $(yush_green "${name}:${tag}"), $(yush_human_period "$howold")old"
                            else
                                rm_image "${name}:${tag}" "$howold"
                            fi
                        fi
                    elif [ -n "$REGPRUNE_LATEST" ] && [ "$REGPRUNE_LATEST" -gt "0" ]; then
                        # When deletion should instead happen by count, push
                        # the name of the image and tag, together with the
                        # creation date to the temporary file created for that
                        # purpose.
                        creation=$(creation_date "${REGPRUNE_REGISTRY%/}/${name}:${tag}")
                        if [ -z "$creation" ]; then
                            yush_warn "Cannot find creation date for ${REGPRUNE_REGISTRY%/}/${name}:${tag}!"
                        else
                            printf "%d\t%s\n" "$((now-$(yush_iso8601 "$creation")))" "${REGPRUNE_REGISTRY%/}/${name}:${tag}" >> "$by_dates"
                        fi
                    else
                        # When no age, nor count selection should happen, just
                        # delete the image at once (scary, uh?!).
                        rm_image "${name}:${tag}"
                    fi
                fi
            else
                yush_info "Skipping ${name}:${tag}, tag does not match $REGPRUNE_TAGS"
            fi
        done
        # If we have a temporary file with possible images and their creation
        # dates, sort by creation date, oldest first (this is because the date
        # is ISO8601 format), then remove all but the REGPRUNE_LATEST at the
        # tail of the file.
        if [ -n "$by_dates" ] && [ -f "$by_dates" ]; then
            sort -n -r -k 1 "$by_dates" | head -n -"$REGPRUNE_LATEST" | while IFS=$(printf \\t\\n) read -r howold image; do
                rm_image "$image" "$howold"
            done
            rm -f "$by_dates";  # Remove the file, we are done for this image.
        fi
    else
        yush_info "Skipping $name, name does not match $REGPRUNE_IMAGES"
    fi
done

# Execute remaining arguments as a command, if any
if [ $# -ne "0" ]; then
    yush_notice "Executing $*"
    exec "$@"
fi