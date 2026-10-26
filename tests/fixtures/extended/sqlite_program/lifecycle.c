#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <unistd.h>

/* Test observation only: every operation reaches the system SQLite library. */
static _Thread_local unsigned depth;
static void *database_owner;
static void *statement_owner;
static void event(const char text[3]) {
    const char *value = getenv("LANIUS_SQLITE_TRACE_FD");
    if (!value) return;
    int descriptor = atoi(value);
    if (write(descriptor, text, 3) != 3) _exit(90);
}
int sqlite3_open_v2(const char *path, void **output, int flags, const char *vfs) {
    int (*real)(const char *, void **, int, const char *) = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    depth++;
    int result = real(path, output, flags, vfs);
    depth--;
    if (depth == 0 && *output) { database_owner = *output; event("D+\n"); }
    return result;
}
int sqlite3_close(void *database) {
    int (*real)(void *) = dlsym(RTLD_NEXT, "sqlite3_close");
    depth++;
    int result = real(database);
    depth--;
    if (depth == 0 && result == 0 && database && database == database_owner) {
        database_owner = NULL;
        event("D-\n");
    }
    return result;
}
int sqlite3_prepare_v3(void *database, const char *sql, int count, unsigned flags, void **output, const char **tail) {
    int (*real)(void *, const char *, int, unsigned, void **, const char **) = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    depth++;
    int result = real(database, sql, count, flags, output, tail);
    depth--;
    if (depth == 0 && *output) { statement_owner = *output; event("S+\n"); }
    return result;
}
int sqlite3_finalize(void *statement) {
    int (*real)(void *) = dlsym(RTLD_NEXT, "sqlite3_finalize");
    depth++;
    int result = real(statement);
    depth--;
    /* SQLite consumes the statement even when finalization returns an error. */
    if (depth == 0 && statement && statement == statement_owner) {
        statement_owner = NULL;
        event("S-\n");
    }
    return result;
}
int sqlite3_step(void *statement) {
    int (*real)(void *) = dlsym(RTLD_NEXT, "sqlite3_step");
    depth++;
    int result = real(statement);
    depth--;
    return result;
}
