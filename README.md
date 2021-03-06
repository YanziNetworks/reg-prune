# reg-prune

This utility will prune a (remote) Docker registry from old and irrelevant
images, provided proper credentials. Selection of images to remove is based on a
combination of the following filters:

+ A regular expression matching their names
+ A regular expression matching their tags
+ An age, expressed in a human-friendly format.

This is a script written in POSIX shell on top of two fantastic giants: [reg] is
used to operate on the remote Docker registry, and its answers are parsed
through a POSIX shell [JSON parser][JSON] or [jq]. The script prefers running
[reg] directly from its installed PATH, but can revert to a Docker container in
case the binary cannot be found. A locally installed [jq] will be automatically
picked up in most cases. The script also exists as a Docker [image][reg-prune]
to be run from a container.

  [reg]: https://github.com/genuinetools/reg
  [JSON]: https://github.com/rcrowley/json.sh
  [jq]: https://stedolan.github.io/jq/
  [reg-prune]: https://hub.docker.com/r/yanzinetworks/prune

**NOTE** This script hasn't had too much testing, your mileage may vary. In all
cases, running it first with the `--dry-run` option is advised.

## Example

Suppose the following command:

```shell
./reg-prune.sh \
    --auth admin:supersecret \
    --verbose \
    --age 6mo \
    --images '.*' \
    --tags '(RC|pre|SNAPSHOT)' \
    --repo r.j3ss.co
```

This command would remove all images (the `.*` regular expression given to
`--images`) generated by various CI/CD pipelines (the `(RC|pre|SNAPSHOT)` given
to `--tags`) that are 6 months old (the `6mo` given to `--age`) at the remote
repository `r.j3ss.co`. This would use hypothetical credentials, but `reg` will
automatically try to find Docker credentials from your home directory if none
are provided.

## Command-Line Options

The script accepts both short "one-letter" options, and double-dashed longer
options. Short options cannot be combined. Long options can be written with an
`=` sign or with their argument separated from the option using a space
separator. The options are as described below. In addition, all remaining
arguments will be understood as a command to execute once cleanup has finished,
if relevant. It is possible to separate the options and their values, from the
remaining finalising command using a double dash, `--`.

Many options exist with various spelling to ease on your memory.

### `-v` or `--verbose`

This will set the verbosity of the script, which defaults to `info`. Output will
be sent to the `stderr` and lines will contain the name of the script, together
with the timestamp. Recognised levels are `debug`, `info`, `notice`, `warn` and
`error`. When used in interactive mode, the script will automatically colour the
log, unless directed not to.

### `-h` or `--help`

Print out help and exit.

### `-n`, `--dry-run` or `--dryrun`

Just print out what would be perform, do not remove anything at all. This option
can be used to assess what the script would do when experimenting with options
such as `--imagess`, `--tags` or `--age`.

### `-i`, `--images` or `--image`

A regular expression to match against the names of the images present at the
remote repository and to select them for removal. This defaults to an empty
string so the script will not remove any image by mistake.

### `-t`, `--tags` or `--tag`

A regular expression to match against the tags of the images selected by the
`--images` option.  Only images which tag match this regular expression at the
remote repository will be selected for removal. This defaults to `.*`, thus will
select all tags for the selected images.

### `-e`, `--exclude`, `--exclude-tag` or `--exclude-tags`

A regular expression for a subset of the selected `--tags` to be excluded from
the ones taken into consideration. The default is an empty string, meaning that
no out of the selected set of tags will be removed.

### `-g` or `--age`

Age of the selected images to consider for removal (default: `3mo`). The age can
be expressed in human-readable format, e.g. `6m` (for 6 months), `3 days`, etc.
or as an integer number of seconds. An empty age is understood as all images
under the relevant tags, however old they are.

### `-l` or `--latest`

Integer amount of images to keep among the ones matching the tags selected by
the combination of the `--tags` and `--excluded` options, and ordered by
creation date. For this parameter to be considered, the `--age` needs to be an
empty string. As removal is per set of matching tags for a given image, this
might remove a lot of images.

### `-r`, `--registry` or `--reg`

DNS of the remote registry to operate on. This has no default and needs to be
provided for the script to run.

### `--auth-url`

Provide an alternative URL at which to authorise.

### `-a`, `--auth`, `--authorisation` or `--authorization`

A colon `:` separated string containing, respectively the username and the
password. When no authorisation is provided, authorisation is delegated to
[reg], which is able to find Docker authorisation details in your home
directory.

### `--auth-file`, `--authorisation-file` or `--authorization-file`

Path to a file containing authorisation details in colon-separated form (see
`--auth` option). This option plays nicely with Docker secrets.

### `--reg-bin` or `--regbin`

Command to use for the [reg] utility. This can be handy to provide the path to a
specific location, or a different Docker command than the default one. This
option is empty by default, which leads to the documented behaviour of looking
for [reg] in the path and defaulting to temporary containers if an executable
could not be found.

### `--reg-opts` or `--regopts`

List of additional options to blindly pass to each invocation of [reg]. This
option can be used to provide access to features that are not interfaced through
the regular set of options recognised by the script.

### `--jq`

Path (or name of binary) where to find [jq]. The default is set to `jq`, which
will look for `jq` in the path. When this option is set to an empty string, or
when [jq] binary pointed at by this option cannot be found, the internal JSON
[parser][JSON] will be used instead.

### `--non-interactive`, `--no-colour` or `--no-color`

Forces no colouring in log output. When this is not specified, colouring is
automatically turned on whenver the script detects that it is run in interactive
mode.

## Environment Variables

The behaviour of this script can also be controlled through environment
variables. Command-line [options](#command-line-options) always have precedence
over the value of environment variables. The script recognises environment
variables starting with the prefix `REGPRUNE_`. The rest of the variable name is
formed using the name of the matching long option, where dashes have been
replaced by underscores. So, for example, to specify the URL of the remote
registry to operate against, you could set the environment variable
`REGPRUNE_REGISTRY` instead of using the command-line option `--registry`.

## Docker

This utility also comes as a Docker [image][reg-prune] so that it can run from a
container. When running from a container, you will have to pay specific
attention to passing credentials through files if this is something you prefer.
The `--auth-file` option is tuned for being used via Docker secrets or similar
techniques. If you would prefer to let [reg] find your credentials, you would
need to map your `.docker` hidden directory onto the one of the `root` user in
the container with read-only access, as in the dummy command example below. This
is what is automatically done when [reg] is not find under the path and used
directly as a Docker container. You should understand the risk of passing your
credentials to this script and underlying [reg] tool.

```shell
docker run -it --rm -v ${HOME}/.docker:/root/.docker:ro yanzinetworks/reg-prune --help
```

## Implementation

This script is the first script that makes use of the [yu.sh] library.

  [yu.sh]: https://github.com/YanziNetworks/yu.sh