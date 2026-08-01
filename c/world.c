/* world.c - read and edit the CRUX world file.
 *
 * The world file is a plain list of package names, one per line; blank
 * lines and lines starting with '#' are ignored.
 *
 * Keeps an in-memory list of package names and provides read/write and
 * add/remove helpers on it.  Exposed to Scheme by main.c.
 */

#define _POSIX_C_SOURCE 200809L

#include "world.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char **world = NULL;
static int nworld = 0;
static int cap = 0;

static void add_name(const char *name)
{
    if (nworld == cap) {
        cap = cap ? cap * 2 : 64;
        world = realloc(world, sizeof(char *) * cap);
    }
    world[nworld++] = strdup(name);
}

int world_read(const char *path)
{
    world_free();

    FILE *f = fopen(path, "r");
    if (!f) return -1;

    char *line = NULL;
    size_t len = 0;
    while (getline(&line, &len, f) != -1) {
        char *s = trim(line);
        if (*s == '\0' || *s == '#') continue;
        add_name(s);
    }

    free(line);
    fclose(f);
    return nworld;
}

int world_count(void)
{
    return nworld;
}

const char *world_get(int i)
{
    return (i >= 0 && i < nworld) ? world[i] : NULL;
}

bool world_has(const char *name)
{
    for (int i = 0; i < nworld; i++)
        if (strcmp(world[i], name) == 0)
            return true;
    return false;
}

bool world_add(const char *name)
{
    if (world_has(name))
        return false;
    add_name(name);
    return true;
}

bool world_remove(const char *name)
{
    for (int i = 0; i < nworld; i++) {
        if (strcmp(world[i], name) == 0) {
            free(world[i]);
            memmove(&world[i], &world[i + 1], sizeof(char *) * (nworld - i - 1));
            nworld--;
            return true;
        }
    }
    return false;
}

int world_write(const char *path)
{
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    for (int i = 0; i < nworld; i++)
        fprintf(f, "%s\n", world[i]);
    if (fclose(f) != 0) return -1;
    return 0;
}

void world_free(void)
{
    for (int i = 0; i < nworld; i++)
        free(world[i]);
    free(world);
    world = NULL;
    nworld = 0;
    cap = 0;
}
