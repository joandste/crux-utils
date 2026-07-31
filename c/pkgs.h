#ifndef PRTTIL_PKGS_H
#define PRTTIL_PKGS_H

/* An installed package from the pkg database. */
typedef struct {
    char *name;      /* e.g. "bash" */
    char *version;   /* e.g. "5.3.15" */
    char *release;   /* e.g. "1" */
} pkg_t;

/* Parse the installed-package database (db_path, e.g. /var/lib/pkg/db)
 * into the pkg array.  Returns the number of packages loaded, or -1 on
 * failure. */
int pkgs_load(const char *db_path);

int pkgs_count(void);
const pkg_t *pkgs_get(int i);
const pkg_t *pkgs_find(const char *name);

void pkgs_free(void);

#endif /* PRTTIL_PKGS_H */
