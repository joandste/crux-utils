// repl.cpp - embeds s7 Scheme and exposes the C++ PackageDB.
//
// Compile with:
//   c++ -std=c++20 -O2 -Wno-volatile -I cpp -o prttil-repl cpp/pkgdb.cpp cpp/repl.cpp cpp/s7.c

#include "pkgdb.hpp"
#include "s7.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <iostream>

static pkgdb::PackageDB* db = nullptr;

// s7 C function signature:  s7_pointer fn(s7_scheme *sc, s7_pointer args)
// where args is a proper list of arguments.
// All port names are Scheme strings, never symbols.

static s7_pointer load_ports(s7_scheme *sc, s7_pointer args) {
    return s7_make_boolean(sc, db->load_ports("/usr/ports"));
}

static s7_pointer load_installed(s7_scheme *sc, s7_pointer args) {
    return s7_make_boolean(sc, db->load_installed());
}

static s7_pointer has_port(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    return s7_make_boolean(sc, db->has_port(name));
}

static s7_pointer port_version(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    return s7_make_string(sc, db->port_record(name).version.c_str());
}

static s7_pointer port_release(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    return s7_make_string(sc, db->port_record(name).release.c_str());
}

static s7_pointer port_dir(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    return s7_make_string(sc, db->port_dir(name).c_str());
}

static s7_pointer port_deps(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    auto deps = db->port_record(name).dependencies;
    s7_pointer list = s7_nil(sc);
    for (auto it = deps.rbegin(); it != deps.rend(); ++it) {
        list = s7_cons(sc, s7_make_string(sc, it->c_str()), list);
    }
    return list;
}

static s7_pointer is_installed(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    return s7_make_boolean(sc, db->is_installed(name));
}

static s7_pointer installed_version(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    auto& all = db->installed();
    auto it = all.find(name);
    if (it == all.end()) return s7_f(sc);
    return s7_make_string(sc, it->second.version.c_str());
}

static s7_pointer installed_release(s7_scheme *sc, s7_pointer args) {
    const char* name = s7_string(s7_car(args));
    auto& all = db->installed();
    auto it = all.find(name);
    if (it == all.end()) return s7_f(sc);
    return s7_make_string(sc, it->second.release.c_str());
}

static s7_pointer all_ports(s7_scheme *sc, s7_pointer args) {
    s7_pointer list = s7_nil(sc);
    auto& ports = db->ports();
    for (auto it = ports.rbegin(); it != ports.rend(); ++it) {
        list = s7_cons(sc, s7_make_string(sc, it->first.c_str()), list);
    }
    return list;
}

static s7_pointer all_installed(s7_scheme *sc, s7_pointer args) {
    s7_pointer list = s7_nil(sc);
    auto& installed = db->installed();
    for (auto it = installed.rbegin(); it != installed.rend(); ++it) {
        list = s7_cons(sc, s7_make_string(sc, it->first.c_str()), list);
    }
    return list;
}

// s7 doesn't have a built-in process exit, so we provide one.
static s7_pointer scm_exit(s7_scheme *sc, s7_pointer args) {
    int code = 0;
    if (s7_is_pair(args)) {
        code = (int)s7_integer(s7_car(args));
    }
    std::exit(code);
    return s7_unspecified(sc); // unreachable
}

// ---------------------------------------------------------------------------
// register all procedures into the s7 environment
// ---------------------------------------------------------------------------

static void register_procedures(s7_scheme *sc) {
    s7_define_function(sc, "exit",             scm_exit,         0, 1, false, "(exit [code]) - exit the process");
    s7_define_function(sc, "load-ports",         load_ports,       0, 0, false, "(load-ports) - scan /usr/ports for Pkgfiles");
    s7_define_function(sc, "load-installed",     load_installed,   0, 0, false, "(load-installed) - parse /var/lib/pkg/db");
    s7_define_function(sc, "has-port?",          has_port,         1, 0, false, "(has-port? name) - #t if port exists in ports tree");
    s7_define_function(sc, "port-version",       port_version,     1, 0, false, "(port-version name) - version string");
    s7_define_function(sc, "port-release",       port_release,     1, 0, false, "(port-release name) - release string");
    s7_define_function(sc, "port-dir",           port_dir,         1, 0, false, "(port-dir name) - parent dir of Pkgfile");
    s7_define_function(sc, "port-deps",          port_deps,        1, 0, false, "(port-deps name) - list of dependencies");
    s7_define_function(sc, "installed?",         is_installed,     1, 0, false, "(installed? name) - #t if package is installed");
    s7_define_function(sc, "installed-version",  installed_version, 1, 0, false, "(installed-version name) - version or #f");
    s7_define_function(sc, "installed-release",  installed_release, 1, 0, false, "(installed-release name) - release or #f");
    s7_define_function(sc, "all-ports",          all_ports,        0, 0, false, "(all-ports) - list all port names");
    s7_define_function(sc, "all-installed",      all_installed,    0, 0, false, "(all-installed) - list all installed packages");
}

int main(int argc, char* argv[]) {
    db = new pkgdb::PackageDB();
    s7_scheme *sc = s7_init();
    if (!sc) {
        std::cerr << "Can't start s7!\n";
        delete db;
        return -1;
    }

    register_procedures(sc);

    if (argc >= 2) {
        // Script mode: set *command-line* and load the script.
        s7_pointer cmdline = s7_nil(sc);
        for (int i = argc - 1; i >= 1; --i)
            cmdline = s7_cons(sc, s7_make_string(sc, argv[i]), cmdline);
        s7_define_variable(sc, "*command-line*", cmdline);
        s7_load(sc, argv[1]);
    } else {
        // Interactive REPL.
        std::cout << "crx-utils s7 Scheme\n";
        while (true) {
            std::string line;
            std::cout << "\ns7> ";
            if (!std::getline(std::cin, line)) break;
            s7_pointer val = s7_eval_c_string(sc, line.c_str());
            std::cout << s7_object_to_c_string(sc, val);
        }
    }

    s7_free(sc);
    delete db;
    return 0;
}
