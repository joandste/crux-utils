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

## Build & install

```bash
make
sudo make install
```

## Shims

| file | what |
|------|------|
| `prt-get` | minimal `prt-get isinst` shim for scripts that expect it |
| `ports` | syncs all port collections via rsync (called by `prttil sync`) |

## Build & install

```bash
make
sudo make install
```

Requires Guile 3.0 development headers.
