/* ports.c - scan the CRUX ports tree for Pkgfiles.
 *
 * Produces a growable array of port_t structs, one per Pkgfile found.
 * Pure file I/O, no subprocesses.  Used by main.c to expose ports to s7.
 */

#define _POSIX_C_SOURCE 200809L

#include "ports.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static port_t *ports = NULL;
static int nports = 0;
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

/* split a whitespace-separated string into a malloc'd array */
static char **split_ws(const char *s, int *count)
{
    char *copy = xstrdup(s);
    int n = 0, c = 8;
    char **out = malloc(sizeof(char *) * c);
    if (!out) { perror("malloc"); exit(1); }

    char *tok = strtok(copy, " \t\r\n");
    while (tok) {
        if (n == c) {
            c *= 2;
            out = xrealloc(out, sizeof(char *) * c);
        }
        out[n++] = xstrdup(tok);
        tok = strtok(NULL, " \t\r\n");
    }

    free(copy);
    *count = n;
    return out;
}

static void port_free(port_t *p)
{
    free(p->name);
    free(p->version);
    free(p->release);
    free(p->pkgfile);
    for (int i = 0; i < p->ndeps; i++)
        free(p->deps[i]);
    free(p->deps);
    memset(p, 0, sizeof(*p));
}

static void add_port(port_t *p)
{
    if (nports == cap) {
        cap = cap ? cap * 2 : 256;
        ports = xrealloc(ports, sizeof(port_t) * cap);
    }
    ports[nports++] = *p;
}

/* Pkgfile is bash-sourcable: plain key=value lines plus a
 * "# Depends on:" comment.  Parse one file into *p.
 * Returns 0 on success, -1 on failure (or a Pkgfile without name=). */
static int load_pkgfile(const char *path, port_t *p)
{
    FILE *f = fopen(path, "r");
    if (!f) return -1;

    memset(p, 0, sizeof(*p));
    p->pkgfile = xstrdup(path);

    char *line = NULL;
    size_t len = 0;

    while (getline(&line, &len, f) != -1) {
        char *s = trim(line);
        if (*s == '\0') continue;

        if (strncmp(s, "name=", 5) == 0) {
            free(p->name);
            p->name = xstrdup(trim(s + 5));
        } else if (strncmp(s, "version=", 8) == 0) {
            free(p->version);
            p->version = xstrdup(trim(s + 8));
        } else if (strncmp(s, "release=", 8) == 0) {
            free(p->release);
            p->release = xstrdup(trim(s + 8));
        } else if (strncmp(s, "# Depends on: ", 14) == 0) {
            p->deps = split_ws(s + 14, &p->ndeps);
        }
    }

    free(line);
    fclose(f);
    return p->name ? 0 : -1;
}

static char *join_path(const char *a, const char *b)
{
    size_t n = strlen(a) + strlen(b) + 2;
    char *p = malloc(n);
    if (!p) { perror("malloc"); exit(1); }
    snprintf(p, n, "%s/%s", a, b);
    return p;
}

/* scan one port collection directory, one level deep: every immediate
 * subdirectory is a port, so look for its Pkgfile.  Returns 0 on success,
 * -1 if the directory can't be opened. */
static int scan_collection(const char *dir)
{
    DIR *d = opendir(dir);
    if (!d) return -1;

    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
            continue;

        char *sub = join_path(dir, e->d_name);
        struct stat st;
        if (stat(sub, &st) == 0 && S_ISDIR(st.st_mode)) {
            char *pf = join_path(sub, "Pkgfile");
            struct stat pst;
            if (stat(pf, &pst) == 0 && S_ISREG(pst.st_mode)) {
                port_t p;
                if (load_pkgfile(pf, &p) == 0)
                    add_port(&p);
                else
                    port_free(&p);
            }
            free(pf);
        }
        free(sub);
    }
    closedir(d);
    return 0;
}

int ports_load(const char *dir)
{
    if (scan_collection(dir) < 0)
        return -1;
    return nports;
}

void ports_clear(void)
{
    for (int i = 0; i < nports; i++)
        port_free(&ports[i]);
    free(ports);
    ports = NULL;
    nports = 0;
    cap = 0;
}

int ports_count(void)
{
    return nports;
}

const port_t *ports_get(int i)
{
    return (i >= 0 && i < nports) ? &ports[i] : NULL;
}

const port_t *ports_find(const char *name)
{
    for (int i = 0; i < nports; i++)
        if (strcmp(ports[i].name, name) == 0)
            return &ports[i];
    return NULL;
}

void ports_free(void)
{
    ports_clear();
}
