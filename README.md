# crux-utils

CRUX package tools — C++ core with a Scheme command layer.

## Usage

```
./prttil install <port>
./prttil remove <port>
./prttil upgrade [--world] [<port>]
./prttil depends [--missing] <port>
./prttil world [--missing|--orphan]
./prttil diff
./prttil sync
```

## World definition

The set of packages that belong on your system is declared in
`/var/lib/pkg/world.scm` — a Scheme file that is evaluated at
runtime.  `prttil install` and `remove` never touch this file;
you control it entirely by editing `*world*`.

See `scm/world.scm` in the repo for the default template.

```scheme
;; Example: conditionally add server packages
(define *world*
  (append
    (list "acl" "attr" "autoconf" ...)
    (if (file-exists? "/etc/crux/server")
        (list "nginx" "postgresql")
        '())))
```

## Build & install

```bash
make
sudo make install
```

Requires Guile 3.0 development headers.

## Shims

| file | what |
|------|------|
| `prt-get` | minimal `prt-get isinst` shim for scripts that expect it |
| `ports` | syncs all port collections via rsync (called by `prttil sync`) |
