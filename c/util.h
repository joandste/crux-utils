/* util.h - small shared helpers for the C core. */

#ifndef PRTTIL_UTIL_H
#define PRTTIL_UTIL_H

#include <string.h>

/* trim leading/trailing whitespace in place; returns pointer to start */
static inline char *trim(char *s)
{
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
        s++;
    size_t n = strlen(s);
    while (n > 0 && (s[n-1] == ' ' || s[n-1] == '\t' || s[n-1] == '\r' || s[n-1] == '\n'))
        s[--n] = '\0';
    return s;
}

#endif /* PRTTIL_UTIL_H */
