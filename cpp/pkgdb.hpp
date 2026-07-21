#pragma once

#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace pkgdb {

// A package seen from either the ports tree or the installed db.
// The same struct is used for both sources — which map it lives in tells you
// whether it's a port or installed.
struct PackageRecord {
    std::string name;
    std::string version;
    std::string release;
    std::vector<std::string> dependencies;  // from # Depends on: in Pkgfile
    std::filesystem::path pkgfile;           // path to the Pkgfile on disk
};

// Core data layer: loads and indexes the ports tree + installed packages.
// No subprocesses, no side effects — pure file I/O and in-memory indexing.
class PackageDB {
public:
    PackageDB() = default;

    // loaders — populate the two internal maps
    bool load_ports(const std::filesystem::path& ports_dir);    // scan for Pkgfiles
    bool load_installed();                                      // parse /var/lib/pkg/db
    PackageRecord load_pkgfile(const std::filesystem::path& pkgfile) const;  // single Pkgfile

    // port queries — look up data in the ports_ map
    bool has_port(const std::string& name) const;
    std::filesystem::path port_dir(const std::string& name) const;     // parent of Pkgfile
    PackageRecord port_record(const std::string& name) const;

    // installed queries — look up data in the installed_ map
    bool is_installed(const std::string& name) const;

    // expose the full maps for iteration
    const std::map<std::string, PackageRecord>& ports() const noexcept;
    const std::map<std::string, PackageRecord>& installed() const noexcept;

private:
    std::filesystem::path ports_dir_;
    std::map<std::string, PackageRecord> ports_;       // keyed by package name
    std::map<std::string, PackageRecord> installed_;   // keyed by package name

    // helpers
    std::vector<std::string> parse_dep_line(const std::string& line) const;  // split on whitespace
    static std::string trim(const std::string& value);
};

} // namespace pkgdb
