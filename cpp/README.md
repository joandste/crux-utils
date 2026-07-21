# C++ Core

- `pkgdb.hpp` / `pkgdb.cpp` — package database: scans ports tree, reads `/var/lib/pkg/db`, parses Pkgfiles
- `repl.cpp` — Guile-embedded REPL that exposes the DB as Scheme procedures (loads `../scm/cli.scm` for the CLI)
