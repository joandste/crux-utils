// repl.cpp — embeds Guile and exposes the C++ PackageDB as Scheme procedures.
// Compile with:
//   c++ -std=c++20 -O2 -Wno-volatile \
//       $(pkg-config --cflags guile-3.0) \
//       -o repl pkgdb.cpp repl.cpp \
//       $(pkg-config --libs guile-3.0)

#include "pkgdb.hpp"
#include <libguile.h>
#include <cstring>

// single global DB instance, created in main()
static pkgdb::PackageDB* db = nullptr;

// each SCM_ function below maps to a Guile procedure registered in
// register_procedures(). naming convention follows Guile's lisp style.

static SCM scm_load_ports() {
    if (!db->load_ports("/usr/ports")) {
        return SCM_BOOL_F;
    }
    return SCM_BOOL_T;
}

static SCM scm_load_installed() {
    if (!db->load_installed()) {
        return SCM_BOOL_F;
    }
    return SCM_BOOL_T;
}

static SCM scm_has_port(SCM name) {
    return scm_from_bool(db->has_port(scm_to_utf8_string(name)));
}

static SCM scm_port_version(SCM name) {
    return scm_from_utf8_string(db->port_record(scm_to_utf8_string(name)).version.c_str());
}

static SCM scm_port_release(SCM name) {
    return scm_from_utf8_string(db->port_record(scm_to_utf8_string(name)).release.c_str());
}

static SCM scm_port_dir(SCM name) {
    return scm_from_utf8_string(db->port_dir(scm_to_utf8_string(name)).c_str());
}

static SCM scm_port_deps(SCM name) {
    auto deps = db->port_record(scm_to_utf8_string(name)).dependencies;
    SCM list = SCM_EOL;
    for (auto it = deps.rbegin(); it != deps.rend(); ++it) {
        list = scm_cons(scm_from_utf8_string(it->c_str()), list);
    }
    return list;
}

static SCM scm_is_installed(SCM name) {
    return scm_from_bool(db->is_installed(scm_to_utf8_string(name)));
}

static SCM scm_installed_version(SCM name) {
    auto& all = db->installed();
    auto it = all.find(scm_to_utf8_string(name));
    if (it == all.end()) return SCM_BOOL_F;
    return scm_from_utf8_string(it->second.version.c_str());
}

static SCM scm_installed_release(SCM name) {
    auto& all = db->installed();
    auto it = all.find(scm_to_utf8_string(name));
    if (it == all.end()) return SCM_BOOL_F;
    return scm_from_utf8_string(it->second.release.c_str());
}

static SCM scm_all_ports() {
    SCM list = SCM_EOL;
    auto& ports = db->ports();
    for (auto it = ports.rbegin(); it != ports.rend(); ++it) {
        list = scm_cons(scm_from_utf8_string(it->first.c_str()), list);
    }
    return list;
}

static SCM scm_all_installed() {
    SCM list = SCM_EOL;
    auto& installed = db->installed();
    for (auto it = installed.rbegin(); it != installed.rend(); ++it) {
        list = scm_cons(scm_from_utf8_string(it->first.c_str()), list);
    }
    return list;
}

// ---------------------------------------------------------------------------
// register all procedures so Guile can see them
// ---------------------------------------------------------------------------

static void* register_procedures(void*) {
    auto fn = [](auto f) { return reinterpret_cast<scm_t_subr>(f); };
    scm_c_define_gsubr("load-ports", 0, 0, 0, fn(scm_load_ports));
    scm_c_define_gsubr("load-installed", 0, 0, 0, fn(scm_load_installed));
    scm_c_define_gsubr("has-port?", 1, 0, 0, fn(scm_has_port));
    scm_c_define_gsubr("port-version", 1, 0, 0, fn(scm_port_version));
    scm_c_define_gsubr("port-release", 1, 0, 0, fn(scm_port_release));
    scm_c_define_gsubr("port-dir", 1, 0, 0, fn(scm_port_dir));
    scm_c_define_gsubr("port-deps", 1, 0, 0, fn(scm_port_deps));
    scm_c_define_gsubr("installed?", 1, 0, 0, fn(scm_is_installed));
    scm_c_define_gsubr("installed-version", 1, 0, 0, fn(scm_installed_version));
    scm_c_define_gsubr("installed-release", 1, 0, 0, fn(scm_installed_release));
    scm_c_define_gsubr("all-ports", 0, 0, 0, fn(scm_all_ports));
    scm_c_define_gsubr("all-installed", 0, 0, 0, fn(scm_all_installed));
    return nullptr;
}

// Load the DB into memory, register Scheme procedures, then hand control to Guile.
// If called with -c or a script file, Guile runs that and exits.
// If called with no arguments, Guile drops into an interactive REPL.
int main(int argc, char* argv[]) {
    db = new pkgdb::PackageDB();
    scm_with_guile(register_procedures, nullptr);
    scm_shell(argc, argv);
    delete db;
    return 0;
}
