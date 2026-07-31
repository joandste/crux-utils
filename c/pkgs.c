/* pkgs.c - parse the installed package database (/var/lib/pkg/db).
 *
 * Format: blank-line-separated entries, each being:
 *   pkgname
 *   version-release
 *   file1
 *   file2
 *   ...
 *   (blank line)
 *
 * Produces a growable array of pkg_t structs.
 */

#define _POSIX_C_SOURCE 200809L

#include "pkgs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static pkg_t *pkgs = NULL;
static int npkgs = 0;
static int cap = 0;

static void *xrealloc(void *p, size_t n)
{
    void *q = realloc(p, n);
    if (!q) { perror("realloc"); exit(1); }
    return q;
}

static char *xstrdup(const char *s)
{
    char *p = strdup(s);
    if (!p) { perror("strdup"); exit(1); }
    return p;
}

/* trim leading/trailing whitespace in place; returns pointer to start */
static char *trim(char *s)
{
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
        s++;
    size_t n = strlen(s);
    while (n > 0 && (s[n-1] == ' ' || s[n-1] == '\t' || s[n-1] == '\r' || s[n-1] == '\n'))
        s[--n] = '\0';
    return s;
}

static void pkg_free(pkg_t *p)
{
    free(p->name);
    free(p->version);
    free(p->release);
    memset(p, 0, sizeof(*p));
}

static void add_pkg(pkg_t *p)
{
    if (npkgs == cap) {
        cap = cap ? cap * 2 : 512;
        pkgs = xrealloc(pkgs, sizeof(pkg_t) * cap);
    }
    pkgs[npkgs++] = *p;
}

int pkgs_load(const char *db_path)
{
    for (int i = 0; i < npkgs; i++)
        pkg_free(&pkgs[i]);
    free(pkgs);
    pkgs = NULL;
    npkgs = 0;
    cap = 0;

    FILE *f = fopen(db_path, "r");
    if (!f) return -1;

    char *line = NULL;
    size_t len = 0;

    while (getline(&line, &len, f) != -1) {
        char *name = trim(line);
        if (*name == '\0') continue;
        char *name_copy = xstrdup(name);

        /* next non-blank line is version-release, e.g. "2.4.0-1" */
        char *vr = NULL;
        while (getline(&line, &len, f) != -1) {
            vr = trim(line);
            if (*vr != '\0') break;
            vr = NULL;
        }
        if (!vr) {
            /* EOF right after the name: record it with no version */
            pkg_t p = { .name = name_copy };
            add_pkg(&p);
            break;
        }

        pkg_t p = { .name = name_copy };
        /* split on the last '-' so version=2.4.0, release=1 */
        char *dash = strrchr(vr, '-');
        if (dash) {
            *dash = '\0';
            p.version = xstrdup(vr);
            p.release = xstrdup(dash + 1);
        } else {
            p.version = xstrdup(vr);
        }
        add_pkg(&p);

        /* skip the file manifest until a blank line or EOF */
        while (getline(&line, &len, f) != -1) {
            if (*trim(line) == '\0') break;
        }
    }

    free(line);
    fclose(f);
    return npkgs;
}

int pkgs_count(void)
{
    return npkgs;
}

const pkg_t *pkgs_get(int i)
{
    return (i >= 0 && i < npkgs) ? &pkgs[i] : NULL;
}

const pkg_t *pkgs_find(const char *name)
{
    for (int i = 0; i < npkgs; i++)
        if (strcmp(pkgs[i].name, name) == 0)
            return &pkgs[i];
    return NULL;
}

void pkgs_free(void)
{
    for (int i = 0; i < npkgs; i++)
        pkg_free(&pkgs[i]);
    free(pkgs);
    pkgs = NULL;
    npkgs = 0;
    cap = 0;
}
