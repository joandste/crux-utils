#include "pkgdb.hpp"

#include <algorithm>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace pkgdb {

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

std::string PackageDB::trim(const std::string& value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }

    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::vector<std::string> PackageDB::parse_dep_line(const std::string& line) const {
    std::vector<std::string> deps;
    std::istringstream stream(line);
    std::string dep;

    while (stream >> dep) {
        deps.push_back(dep);
    }

    return deps;
}

// Pkgfiles are bash-sourcable - this extracts all key=value lines.
// CRUX Pkgfiles always use plain key=value (no quotes, no export),
// so the parser is deliberately simple: find `=`, split once.
static std::map<std::string, std::string> parse_assignments(std::istream& input) {
    std::map<std::string, std::string> vars;
    std::string line;

    while (std::getline(input, line)) {
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;

        std::string key = line.substr(0, eq);
        std::string val = line.substr(eq + 1);

        vars[key] = val;
    }

    return vars;
}

// ---------------------------------------------------------------------------
// loaders
// ---------------------------------------------------------------------------

bool PackageDB::load_ports(const std::filesystem::path& ports_dir) {
    ports_dir_ = ports_dir;
    ports_.clear();

    if (!std::filesystem::exists(ports_dir_) || !std::filesystem::is_directory(ports_dir_)) {
        return false;
    }

    // eager loading is fast enough (~30 ms for 2000 ports on this machine)
    // so lazy loading is probably unnecessary. revisit if it becomes a bottleneck.
    for (const auto& entry : std::filesystem::recursive_directory_iterator(ports_dir_)) {
        if (!entry.is_regular_file() || entry.path().filename() != "Pkgfile") {
            continue;
        }

        PackageRecord record = load_pkgfile(entry.path());
        ports_[record.name] = std::move(record);
    }

    return !ports_.empty();
}

// /var/lib/pkg/db format: blank-line-separated entries, each being:
//   pkgname
//   version-release
//   file1
//   file2
//   ...
//   (blank line)
bool PackageDB::load_installed() {
    installed_.clear();

    std::ifstream input("/var/lib/pkg/db");
    if (!input) {
        return false;
    }

    std::string line;
    while (std::getline(input, line)) {
        line = trim(line);
        if (line.empty()) {
            continue;
        }

        // first non-empty line is the package name
        PackageRecord record;
        record.name = line;

        // next non-empty line is version-release  (e.g. "2.4.0-1")
        if (!std::getline(input, line)) {
            break;
        }
        line = trim(line);

        // split on last `-` so version=2.4.0, release=1
        const auto split = line.rfind('-');
        if (split == std::string::npos) {
            record.version = line;
        } else {
            record.version = line.substr(0, split);
            record.release = line.substr(split + 1);
        }

        installed_[record.name] = std::move(record);

        // skip the file manifest lines until the next blank line or EOF
        while (std::getline(input, line)) {
            line = trim(line);
            if (line.empty()) {
                break;
            }
        }
    }

    return !installed_.empty();
}

// Parse a single Pkgfile into a PackageRecord.
// Pkgfile format (bash-sourcable):
//   name=bash
//   version=5.3.15
//   release=1
//   # Depends on: readline ncurses
PackageRecord PackageDB::load_pkgfile(const std::filesystem::path& pkgfile) const {
    std::ifstream input(pkgfile);
    if (!input) {
        throw std::runtime_error("failed to open pkgfile: " + pkgfile.string());
    }

    // pass 1: extract all key=value assignments
    auto vars = parse_assignments(input);

    PackageRecord record;
    record.pkgfile = pkgfile;
    record.name = vars["name"];
    record.version = vars["version"];
    record.release = vars["release"];

    // pass 2: read the # Depends on: comment (separate since it's not key=value)
    std::ifstream again(pkgfile);
    std::string line;
    while (std::getline(again, line)) {
        if (line.rfind("# Depends on: ", 0) == 0) {
            const std::string deps = line.substr(std::string("# Depends on: ").size());
            record.dependencies = parse_dep_line(deps);
            break;
        }
    }

    return record;
}

// ---------------------------------------------------------------------------
// query helpers
// ---------------------------------------------------------------------------

bool PackageDB::has_port(const std::string& name) const {
    return ports_.find(name) != ports_.end();
}

std::filesystem::path PackageDB::port_dir(const std::string& name) const {
    const auto it = ports_.find(name);
    if (it == ports_.end()) {
        return {};
    }

    return it->second.pkgfile.parent_path();
}

PackageRecord PackageDB::port_record(const std::string& name) const {
    const auto it = ports_.find(name);
    if (it == ports_.end()) {
        throw std::runtime_error("unknown port: " + name);
    }

    return it->second;
}

bool PackageDB::is_installed(const std::string& name) const {
    return installed_.contains(name);
}

const std::map<std::string, PackageRecord>& PackageDB::ports() const noexcept {
    return ports_;
}

const std::map<std::string, PackageRecord>& PackageDB::installed() const noexcept {
    return installed_;
}

} // namespace pkgdb
