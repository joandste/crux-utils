# C++ Core

- `pkgdb.hpp` / `pkgdb.cpp` - package database: scans ports tree,
  reads `/var/lib/pkg/db`, parses Pkgfiles
- `repl.cpp` - s7-embedded REPL that registers the database functions
  as Scheme procedures, then loads a script or drops into interactive mode
- `s7.c` / `s7.h` - the s7 Scheme interpreter (vendored, 0-Clause BSD)

## Build (standalone)

```bash
c++ -std=c++20 -O2 -I cpp -o prttil-repl cpp/pkgdb.cpp cpp/repl.cpp cpp/s7.c
```
