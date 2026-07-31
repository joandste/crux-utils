CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra
# s7.c is vendored - don't flood the build with its pre-existing warnings.
S7_CFLAGS ?= -std=c11 -O2
# s7 uses libm math functions (fmod, pow, floor, ...); cc doesn't link it by default.
LDLIBS ?= -lm

DESTDIR ?=
PREFIX ?= /usr
BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBDIR := $(DESTDIR)$(PREFIX)/lib/prttil

.PHONY: all build install clean

all: build

build: prttil-main

prttil-main: c/main.o c/ports.o c/pkgs.o c/s7.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

c/main.o: c/main.c c/ports.h c/pkgs.h c/s7.h
	$(CC) $(CFLAGS) -I c -c -o $@ c/main.c

c/ports.o: c/ports.c c/ports.h
	$(CC) $(CFLAGS) -I c -c -o $@ c/ports.c

c/pkgs.o: c/pkgs.c c/pkgs.h
	$(CC) $(CFLAGS) -I c -c -o $@ c/pkgs.c

c/s7.o: c/s7.c c/s7.h
	$(CC) $(S7_CFLAGS) -I c -c -o $@ c/s7.c

install: build
	install -d $(BINDIR) $(LIBDIR)
	install -m 755 prttil-main $(LIBDIR)/main
	install -m 755 scm/cli.scm $(LIBDIR)/cli.scm
	install -m 755 ports $(LIBDIR)/ports
	install -m 755 prttil $(BINDIR)/prttil
	install -m 755 prt-get $(BINDIR)/prt-get

clean:
	rm -f prttil-main c/*.o
