#ifndef PRTTIL_PORTS_H
#define PRTTIL_PORTS_H

/* A port from the ports tree, loaded from a Pkgfile. */
typedef struct {
    char *name;      /* e.g. "bash" */
    char *version;   /* e.g. "5.3.15" */
    char *release;   /* e.g. "1" */
    char **deps;     /* names from the "# Depends on:" comment */
    int ndeps;
    char *pkgfile;   /* full path to the Pkgfile on disk */
} port_t;

/* Scan one port collection directory (e.g. /usr/ports/core) for Pkgfiles
 * and append the found ports to the array.
 *
 * The directory is scanned one level deep - every immediate subdirectory
 * is treated as a port and its Pkgfile is loaded.  No recursion.
 *
 * Ports are deduplicated by name: a Pkgfile already loaded by an earlier
 * ports_load() call is skipped, so calling collections in order (as
 * cli.scm does) makes earlier directories take priority.
 *
 * Returns the number of ports loaded so far, or -1 if the directory can't
 * be opened.  Use ports_clear() to reset the array before loading. */
int ports_load(const char *dir);
void ports_clear(void);

int ports_count(void);
const port_t *ports_get(int i);
const port_t *ports_find(const char *name);

#endif /* PRTTIL_PORTS_H */
