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

/* Scan ports_dir recursively for Pkgfiles and build the port array.
 * Returns the number of ports loaded, or -1 on failure. */
int ports_load(const char *ports_dir);

int ports_count(void);
const port_t *ports_get(int i);
const port_t *ports_find(const char *name);

void ports_free(void);

#endif /* PRTTIL_PORTS_H */
