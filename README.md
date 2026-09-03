# crux-utils

CRUX package management tools. The core is written in plain C, with an
embedded s7 Scheme interpreter that provides the command-line interface.

## Layout

- `c/ports.c` / `c/ports.h` - scans the given port collection directories
  (e.g. `/usr/ports/core`) one level deep, no recursion, for Pkgfiles and
  builds a list of available ports (name, version, release, dependencies,
  optional dependencies, description, URL, maintainer).
- `c/pkgs.c` / `c/pkgs.h` - parses the package database and builds a list
  of installed packages.
- `c/main.c` - the main program. Exposes the port and package databases to
  Scheme as functions like `load-ports` and `load-pkgs`, then hands control
  over to s7.
- `c/s7.c` / `c/s7.h` - the vendored s7 Scheme interpreter (see Licensing).
- `scm/cli.scm` - the command-line commands (install, build, upgrade,
  depends, world, diff) written in Scheme. Configures the port directories
  (`*ports-dirs*`), package db path (`*pkg-db*`), the overridable global
  settings `pkgmk`, `pkgadd`, `world-add`, `world-del`, and defines the
  effective world (the "World" block).
- `prttil` - wrapper script that runs the whole thing.
- `prt-get` - a small compatibility shim providing `prt-get isinst` for
  scripts that expect prt-get to exist.

## Build

    make

This produces the `repl` binary.

## Use

    ./repl scm/cli.scm depends <port>...
    ./repl scm/cli.scm diff
    ./repl scm/cli.scm install <port>...    # needs root
    ./repl scm/cli.scm build <port>...      # pkgmk only, no install
    ./repl scm/cli.scm upgrade [--world] <port>...
    ./repl scm/cli.scm world [--missing|--orphan]
    ./repl scm/cli.scm world add|remove <pkg>

Or use the wrapper script, which locates the binary and cli.scm for you:

    ./prttil depends firefox

The effective world is defined in the "World" block of `scm/cli.scm`: by
default it is the core collection plus the packages `install` and `world add`
record in the auto-maintained user world file (`/var/lib/pkg/world`). Edit
that block to change what your system should look like.

## Customization

The top of `scm/cli.scm` defines the extension points as ordinary procedures
the commands call directly: `pkgmk`, `pkgadd`, `world-add` and `world-del`.
The defaults spawn a shell (`pkgmk`/`pkgadd`, and `echo`/`sed` for the world
file). To stop tracking installs, make `world-add` and `world-del` no-ops
(return `#t`) and describe the whole world in the World block.

## Licensing

The project code (`c/` except for s7, and `scm/`) is GPLv3.

The vendored s7 interpreter in `c/s7.c` and `c/s7.h` is released under the
0-Clause BSD licence. That licence is compatible with GPLv3, so the two can
be distributed together without any additional restrictions. s7 is bundled
unmodified; its upstream is <https://ccrma.stanford.edu/software/s7/>.

