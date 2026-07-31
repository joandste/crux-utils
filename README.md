# crux-utils

CRUX package management tools. The core is written in plain C, with an
embedded s7 Scheme interpreter that provides the command-line interface.

## Layout

- `c/ports.c` / `c/ports.h` - scans the CRUX ports tree for Pkgfiles and
  builds a list of available ports (name, version, release, dependencies).
- `c/pkgs.c` / `c/pkgs.h` - parses `/var/lib/pkg/db` and builds a list of
  installed packages.
- `c/main.c` - the main program. Loads the port and package databases and
  exposes them to Scheme as functions like `load-ports` and `load-pkgs`,
  then hands control over to s7.
- `c/s7.c` / `c/s7.h` - the vendored s7 Scheme interpreter (see Licensing).
- `scm/cli.scm` - the command-line commands (install, upgrade, depends,
  world, diff) written in Scheme.
- `prttil` - wrapper script that runs the whole thing.
- `prt-get` - a small compatibility shim providing `prt-get isinst` for
  scripts that expect prt-get to exist.

## Build

    make

This produces the `prttil-main` binary.

## Use

    ./prttil-main scm/cli.scm depends <port>
    ./prttil-main scm/cli.scm diff
    ./prttil-main scm/cli.scm install <port>    # needs root
    ./prttil-main scm/cli.scm upgrade [--world] [<port>]
    ./prttil-main scm/cli.scm world [--missing|--orphan] [<file>]

Or use the wrapper script, which locates the binary and cli.scm for you:

    ./prttil depends firefox

## Licensing

The project code (`c/` except for s7, and `scm/`) is GPLv3.

The vendored s7 interpreter in `c/s7.c` and `c/s7.h` is released under the
0-Clause BSD licence. That licence is compatible with GPLv3, so the two can
be distributed together without any additional restrictions. s7 is bundled
unmodified; its upstream is <https://ccrma.stanford.edu/software/s7/>.

