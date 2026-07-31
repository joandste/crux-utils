#ifndef PRTTIL_WORLD_H
#define PRTTIL_WORLD_H

#include <stdbool.h>

/* The CRUX world file is a plain list of package names, one per line.
 * Blank lines and lines starting with '#' are ignored. */

/* Read a world file into the in-memory list (replacing whatever was
 * there).  Returns the number of packages, or -1 if the file can't be
 * opened (the list is left empty). */
int world_read(const char *path);

int world_count(void);
const char *world_get(int i);
bool world_has(const char *name);

/* Modify the in-memory list. */
bool world_add(const char *name);    /* true if added, false if already present */
bool world_remove(const char *name); /* true if removed, false if not present */

/* Write the in-memory list back to path.  Returns 0 on success, -1 on
 * failure. */
int world_write(const char *path);

void world_free(void);

#endif /* PRTTIL_WORLD_H */
