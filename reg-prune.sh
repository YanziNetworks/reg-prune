#!/bin/sh

# Pick relevant yu.sh modules at once.
ROOT_DIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )
[ -d "$ROOT_DIR/yu.sh" ] && YUSH_DIR="$ROOT_DIR/yu.sh"
[ -z "$YUSH_DIR" ] && [ -d "$ROOT_DIR/../lib/yu.sh" ] && YUSH_DIR="$ROOT_DIR/../lib/yu.sh"
[ -z "$YUSH_DIR" ] && echo "Cannot find yu.sh root!" >/dev/stderr && exit 1
. "$YUSH_DIR/log.sh"
. "$YUSH_DIR/date.sh"
. "$YUSH_DIR/json.sh"

DRYRUN=0
IMAGES=
TAGS=".*"
AGE=3mo
REPO=
AUTH=
AUTH_URL=
REG=
REG_OPTS=
DOCKER_REG=jess/reg:v0.16.0;       # Note: dev. in flux, pick your version carefully


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
    -g | --age          Age of images to delete, in seconds. Can be expressed in
                        human-readable format. Default to 3mo, i.e. 3 months.
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
        YUSH_LOG_LEVEL="${1#*=}"; shift 1;;

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

    --reg-opts | --regopts)
        REG_OPTS="$2"; shift 2;;
    --reg-opts=* | --regopts=*)
        REG_OPTS="${1#*=}"; shift 1;;

    --non-interactive | --no-colour | --no-color)
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

	runreg="$REG $cmd"
	[ -n "$AUTH_URL" ] && runreg="$runreg --auth-url $AUTH_URL"
	if [ -n "$USERNAME" ]; then
		runreg="$runreg --username $USERNAME"
		[ -n "$PASSWORD" ] && runreg="$runreg --password $PASSWORD"
	fi
	[ -n "$REG_OPTS" ] && runreg="$runreg $REG_OPTS"
	$runreg "$@"
}

rm_image() {
    if [ "$DRYRUN" = "1" ]; then
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
        reg rm "${REPO%/}/$1"
    fi
}

[ -z "$REPO" ] && usage "You must provide a registry through --reg(istry) option!"

# Convert period
if echo "$AGE"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
    NEWAGE=$(yush_howlong "$AGE")
    yush_info "Converted human-readable age $AGE to $NEWAGE seconds"
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
		yush_debug "Will run reg as a Docker container using $DOCKER_REG"
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
yush_debug "Listing all images and tags at $REPO"
inventory=$(reg ls "$REPO")
header=$(printf "%s" "$inventory" | grep -E "REPO\s+TAGS")
tags_col=$(locate_keyword "$header" "TAGS")
start=$(printf "%s" "$inventory" | grep -En "REPO\s+TAGS" | cut -d':' -f1)
for name in $(printf "%s" "$inventory" | tail -n +$((start+1)) | cut -c1-$((tags_col-1)) | sed -E 's/\s+$//g' | grep -Eo '^([a-z0-9]+([._]|__|[-]|[a-z0-9])*(\/[a-z0-9]+([._]|__|[-]|[a-z0-9])*)*)'); do
    if [ -n "$IMAGES" ] && echo "$name" | grep -Eqo "$IMAGES"; then
        yush_debug "Selecting among tags of image $name"
        for tag in $(reg tags "${REPO%/}/${name}"); do
            if [ -n "$TAGS" ] && echo "$tag" | grep -Eqo "$TAGS"; then
                if [ -n "$AGE" ]; then
                    yush_debug "Checking age of ${name}:${tag}"
                    # Get the sha256 of the config layer, which is a JSON file
                    config=$(reg manifest "${REPO%/}/${name}:${tag}" | yush_json | grep '/config/digest' | awk '{print $3}')
					if [ -z "$config" ]; then
						warn "Cannot find config layer for ${REPO%/}/${name}:${tag}!"
					else
						# Extract the layer, parse its JSON and look for the image creation date, in ISO8601 format
						creation=$(reg layer "${REPO%/}/${name}:${tag}@${config}" | yush_json | grep -E '^/created\s+' | awk '{print $3}')
						if [ -z "$creation" ]; then
							warn "Cannot find creation date for ${REPO%/}/${name}:${tag}!"
						else
							howold=$((now-$(yush_iso8601 "$creation")))
							if [ "$howold" -lt "$AGE" ]; then
								yush_info "Keeping $(yush_green "${name}:${tag}"), $(human "$howold")old"
							else
								rm_image "${name}:${tag}" "$howold"
							fi
						fi
					fi
                else
                    rm_image "${name}:${tag}"
                fi
            else
                yush_info "Skipping ${name}:${tag}, tag does not match $TAGS"
            fi
        done
    else
        yush_info "Skipping $name, name does not match $IMAGES"
    fi
done

# Execute remaining arguments as a command, if any
if [ $# -ne "0" ]; then
    yush_notice "Executing $*"
    exec "$@"
fi