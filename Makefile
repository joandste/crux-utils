CXX ?= c++
CXXFLAGS = -std=c++20 -O2 -Wno-volatile
GUILE_CFLAGS := $(shell pkg-config --cflags guile-3.0)
GUILE_LIBS := $(shell pkg-config --libs guile-3.0)

DESTDIR ?=
PREFIX ?= /usr
BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBDIR := $(DESTDIR)$(PREFIX)/lib/prttil

.PHONY: all build install clean

all: build

build: prttil-repl

prttil-repl: cpp/pkgdb.cpp cpp/repl.cpp
	$(CXX) $(CXXFLAGS) $(GUILE_CFLAGS) -I cpp -o $@ $^ $(GUILE_LIBS)

install: build
	install -d $(BINDIR) $(LIBDIR)
	install -m 755 prttil-repl $(LIBDIR)/repl
	install -m 755 scm/cli.scm $(LIBDIR)/cli.scm
	install -m 755 ports $(LIBDIR)/ports
	install -m 755 prttil $(BINDIR)/prttil
	install -m 755 prt-get $(BINDIR)/prt-get

clean:
	rm -f prttil-repl
