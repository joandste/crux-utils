CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wno-volatile

DESTDIR ?=
PREFIX ?= /usr
BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBDIR := $(DESTDIR)$(PREFIX)/lib/prttil

.PHONY: all build install clean

all: build

build: prttil-repl

prttil-repl: cpp/pkgdb.cpp cpp/repl.cpp cpp/s7.c
	$(CXX) $(CXXFLAGS) -I cpp -o $@ $^

install: build
	install -d $(BINDIR) $(LIBDIR)
	install -m 755 prttil-repl $(LIBDIR)/repl
	install -m 755 scm/cli.scm $(LIBDIR)/cli.scm
	install -m 755 ports $(LIBDIR)/ports
	install -m 755 prttil $(BINDIR)/prttil
	install -m 755 prt-get $(BINDIR)/prt-get

clean:
	rm -f prttil-repl
