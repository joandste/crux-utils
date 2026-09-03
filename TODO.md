# TODO

## Done (2026-08-31)

- [x] World handling is entirely in Scheme, inside `scm/cli.scm` (the "World"
      section): the effective world is `dedupe`(core collection + the
      auto-maintained user file `*user-world-file*`), set after the
      ports/pkgs load. `c/world.c` / `c/world.h` and `scm/world.scm` were
      removed; the `world-*` s7 bindings and the world file-loading machinery
      are gone.
- [x] `pkgmk-cmd` / `pkgadd-cmd` string builders replaced by the overridable
      settings `pkgmk`, `pkgadd`, `world-add`, `world-del` (shell defaults,
      all return `#t`). The CLI calls them directly - no pure-Scheme world
      handling, no abstract string/file helper layer. `world add` / `world
      remove` just call `world-add` / `world-del`; `world <file>` was dropped.
- [x] `scm/cli.scm` reorganized into consistent sections: Configuration,
      World, Helpers, Commands.
- [x] Parse the full Pkgfile header in C (`c/ports.c`) and expose it to
      Scheme: `port-description`, `port-url`, `port-maintainer`,
      `port-optional` (plus the existing `port-deps`). `source` / `build`
      are intentionally not parsed. Missing ports/fields surface as `#f`;
      `port-deps` / `port-optional` are `()` when a port has none. Enables a
      `search` over descriptions.

Backlog from the `cli.scm` design review (2026-08-01). None started.

## High

- [ ] `search <pattern>` command - find ports by name (uses `all-ports`)
- [ ] Implement /etc/ports/drivers and add cli for it, maybe call it sync. at the same
      time consider how diff should work, these commands go hand in hand.
- [ ] Implement post and pre -install scripts

## Medium

- [ ] Fix the default `pkgadd-cmd` path - it globs `/tmp/...` but this
      machine's `pkgmk.conf` sets `PKGMK_PACKAGE_DIR=/home/user/musl-pkgs`, so
      `install`/`upgrade` would fail at the `pkgadd` step unless overridden.
- [ ] DRY the four near-identical spawn loops (`install`, `build`,
      `upgrade`, `upgrade --world`) into `pkgmk!` / `pkgadd!` helpers.
- [ ] `upgrade --world` silently skips world packages that aren't installed
      (`needs-upgrade?` requires `installed?`) - announce them or install them.
- [ ] `depends a b` should dedupe shared dependencies across multiple roots.

## Low

- [ ] Warn on unknown flags in `install` / `build` (flags are currently
      computed but silently ignored).
- [ ] `world add` / `world remove` should exit 0 on a no-op (idempotent
      scripting).
- [ ] Sort the output of `diff` and `world --orphan`.
- [ ] Add `info` / `cat <port>` and `list [--installed]` commands (once the
      Pkgfile header is parsed).
- [ ] Add `--dry-run` for `install` / `upgrade`; make `upgrade` with no args
      default to `--world`.
- [ ] Idea: split the commands into separate `.scm` files (one per command)
      with a small dispatcher, instead of one monolithic `cli.scm`. Explore
      shebang'ing each script directly to the `repl` binary, or having the
      `prttil` wrapper route to the right script. Architectural idea only -
      not committed to.

## Bigger

- [ ] `remove` with orphan cleanup (needs `pkgrm` / C-side support).

## Trim

- [ ] Drop the "is already in the world file" noise on reinstall.
- [ ] Send `diff`'s "installed (not in ports tree)" line to stderr instead of
      stdout.
