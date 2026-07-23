# crux-utils

CRUX package tools - C++ core with an embedded s7 Scheme REPL.

## Build

```bash
make
sudo make install        # optional
```

Only needs a C++20 compiler and a POSIX environment - no extra
libraries beyond what the compiler ships.

## Usage

```
./prttil-repl scm/cli.scm install <port>
./prttil-repl scm/cli.scm upgrade [--world] [<port>]
./prttil-repl scm/cli.scm depends <port>
./prttil-repl scm/cli.scm depends --missing <port>
./prttil-repl scm/cli.scm world [--missing|--orphan] [<file>]
./prttil-repl scm/cli.scm diff
```

| command | what |
|---------|------|
| `install <port>` | build and install port with missing deps |
| `upgrade <port>` | rebuild and upgrade a specific port |
| `upgrade --world` | rebuild all outdated ports from the world file |
| `depends <port>` | print full dependency graph |
| `depends --missing <port>` | only deps not yet installed |
| `world` | resolve `/var/lib/pkg/world` through the dep graph |
| `world --missing` | world deps not yet installed |
| `world --orphan` | installed packages not in the world graph |
| `diff` | shows installed packages where ports tree has a newer version |

## Files

| path | role |
|------|------|
| `cpp/pkgdb.cpp` / `.hpp` | C++ port database - scans Pkgfiles, reads `/var/lib/pkg/db` |
| `cpp/repl.cpp` | s7-embedded REPL exposing the DB as Scheme procedures |
| `cpp/s7.c` / `.h` | s7 Scheme interpreter (0-Clause BSD) |
| `scm/cli.scm` | CLI commands written in Scheme |
| `prttil` | entry-point wrapper - passes commands through to `prttil-repl` |

## Licensing

The C++ core and Scheme glue (`cpp/`, `scm/`) are GPLv3.
The project bundles [s7](https://ccrma.stanford.edu/software/s7/) -
a Scheme interpreter released under the 0-Clause BSD licence -
in `cpp/s7.c` and `cpp/s7.h`.  Both licences are compatible;
no additional notice or restriction is introduced by the bundling.
