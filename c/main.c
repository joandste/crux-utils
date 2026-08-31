/* main.c - embed s7 Scheme and expose the ports/pkgs databases to it.
 *
 * Compile with:
 *   cc -std=c11 -O2 -I c -o repl c/main.c c/ports.c c/pkgs.c c/s7.c
 *
 * Registers Scheme procedures (load-ports, load-pkgs, has-port?, ...) that
 * delegate to the C port and pkg modules, then hands control over to s7: it
 * loads a script if one is given on the command line, otherwise drops into
 * an interactive REPL.  Port collection dirs and the pkg db path are passed
 * in from Scheme, so the C side never hardcodes them.  World handling is
 * done entirely in Scheme (see the World section of scm/cli.scm).
 */

#define _POSIX_C_SOURCE 200809L

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ports.h"
#include "pkgs.h"
#include "s7.h"

static s7_pointer load_ports(s7_scheme *sc, s7_pointer args)
{
    return s7_make_boolean(sc, ports_load(s7_string(s7_car(args))) >= 0);
}

static s7_pointer ports_clear_fn(s7_scheme *sc, s7_pointer args)
{
    (void)args;
    ports_clear();
    return s7_unspecified(sc);
}

static s7_pointer load_pkgs(s7_scheme *sc, s7_pointer args)
{
    return s7_make_boolean(sc, pkgs_load(s7_string(s7_car(args))) >= 0);
}

static s7_pointer has_port(s7_scheme *sc, s7_pointer args)
{
    return s7_make_boolean(sc, ports_find(s7_string(s7_car(args))) != NULL);
}

static s7_pointer port_version(s7_scheme *sc, s7_pointer args)
{
    const port_t *p = ports_find(s7_string(s7_car(args)));
    return s7_make_string(sc, p && p->version ? p->version : "");
}

static s7_pointer port_release(s7_scheme *sc, s7_pointer args)
{
    const port_t *p = ports_find(s7_string(s7_car(args)));
    return s7_make_string(sc, p && p->release ? p->release : "");
}

/* parent directory of the port's Pkgfile */
static s7_pointer port_dir(s7_scheme *sc, s7_pointer args)
{
    const port_t *p = ports_find(s7_string(s7_car(args)));
    if (!p) return s7_make_string(sc, "");

    char *copy = strdup(p->pkgfile);
    char *slash = strrchr(copy, '/');
    if (slash) *slash = '\0';
    s7_pointer dir = s7_make_string(sc, copy);
    free(copy);
    return dir;
}

static s7_pointer port_deps(s7_scheme *sc, s7_pointer args)
{
    const port_t *p = ports_find(s7_string(s7_car(args)));
    s7_pointer list = s7_nil(sc);
    if (p) {
        for (int i = p->ndeps - 1; i >= 0; i--)
            list = s7_cons(sc, s7_make_string(sc, p->deps[i]), list);
    }
    return list;
}

static s7_pointer is_installed(s7_scheme *sc, s7_pointer args)
{
    return s7_make_boolean(sc, pkgs_find(s7_string(s7_car(args))) != NULL);
}

static s7_pointer installed_version(s7_scheme *sc, s7_pointer args)
{
    const pkg_t *p = pkgs_find(s7_string(s7_car(args)));
    if (!p) return s7_f(sc);
    return s7_make_string(sc, p->version ? p->version : "");
}

static s7_pointer installed_release(s7_scheme *sc, s7_pointer args)
{
    const pkg_t *p = pkgs_find(s7_string(s7_car(args)));
    if (!p) return s7_f(sc);
    return s7_make_string(sc, p->release ? p->release : "");
}

static s7_pointer all_ports(s7_scheme *sc, s7_pointer args)
{
    (void)args;
    s7_pointer list = s7_nil(sc);
    for (int i = ports_count() - 1; i >= 0; i--)
        list = s7_cons(sc, s7_make_string(sc, ports_get(i)->name), list);
    return list;
}

static s7_pointer all_installed(s7_scheme *sc, s7_pointer args)
{
    (void)args;
    s7_pointer list = s7_nil(sc);
    for (int i = pkgs_count() - 1; i >= 0; i--)
        list = s7_cons(sc, s7_make_string(sc, pkgs_get(i)->name), list);
    return list;
}

/* s7 has no built-in process exit, so provide one */
static s7_pointer scm_exit(s7_scheme *sc, s7_pointer args)
{
    int code = 0;
    if (s7_is_pair(args))
        code = (int)s7_integer(s7_car(args));
    exit(code);
    return s7_unspecified(sc); /* unreachable */
}

/* register all procedures into the s7 environment */
static void register_procedures(s7_scheme *sc)
{
    s7_define_function(sc, "exit",               scm_exit,          0, 1, false, "(exit [code]) - exit the process");
    s7_define_function(sc, "load-ports",         load_ports,        1, 0, false, "(load-ports path) - scan one port directory for Pkgfiles");
    s7_define_function(sc, "ports-clear",        ports_clear_fn,    0, 0, false, "(ports-clear) - clear the loaded ports");
    s7_define_function(sc, "load-pkgs",          load_pkgs,         1, 0, false, "(load-pkgs path) - parse the package db at path");
    s7_define_function(sc, "has-port?",          has_port,          1, 0, false, "(has-port? name) - #t if port exists in ports tree");
    s7_define_function(sc, "port-version",       port_version,      1, 0, false, "(port-version name) - version string");
    s7_define_function(sc, "port-release",       port_release,      1, 0, false, "(port-release name) - release string");
    s7_define_function(sc, "port-dir",           port_dir,          1, 0, false, "(port-dir name) - parent dir of Pkgfile");
    s7_define_function(sc, "port-deps",          port_deps,         1, 0, false, "(port-deps name) - list of dependencies");
    s7_define_function(sc, "installed?",         is_installed,      1, 0, false, "(installed? name) - #t if package is installed");
    s7_define_function(sc, "installed-version",  installed_version, 1, 0, false, "(installed-version name) - version or #f");
    s7_define_function(sc, "installed-release",  installed_release, 1, 0, false, "(installed-release name) - release or #f");
    s7_define_function(sc, "all-ports",          all_ports,         0, 0, false, "(all-ports) - list all port names");
    s7_define_function(sc, "all-installed",      all_installed,     0, 0, false, "(all-installed) - list all installed packages");
}

int main(int argc, char *argv[])
{
    s7_scheme *sc = s7_init();
    if (!sc) {
        fprintf(stderr, "Can't start s7!\n");
        return -1;
    }

    register_procedures(sc);

    if (argc >= 2) {
        /* script mode: set *command-line* and load the script */
        s7_pointer cmdline = s7_nil(sc);
        for (int i = argc - 1; i >= 1; i--)
            cmdline = s7_cons(sc, s7_make_string(sc, argv[i]), cmdline);
        s7_define_variable(sc, "*command-line*", cmdline);
        s7_load(sc, argv[1]);
    } else {
        /* interactive REPL */
        printf("crux-utils s7 Scheme\n");
        char line[4096];
        for (;;) {
            printf("\ns7> ");
            fflush(stdout);
            if (!fgets(line, sizeof(line), stdin)) break;
            s7_pointer val = s7_eval_c_string(sc, line);
            char *out = s7_object_to_c_string(sc, val);
            if (out) {
                printf("%s\n", out);
                free(out);
            }
        }
    }

    s7_free(sc);
    ports_clear();
    pkgs_free();
    return 0;
}
