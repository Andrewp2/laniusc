#define _GNU_SOURCE
#include <dlfcn.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <unistd.h>

/* Test observation only. All operations reach the installed SQLite library. */
static _Thread_local unsigned depth;
static sqlite3 *database_owner;
static sqlite3_stmt *statement_owner;

static void event(char code) {
    const char *value = getenv("LANIUS_SQLITE_ALLOCATION_FD");
    if (!value || write(atoi(value), &code, 1) != 1) _exit(90);
}
int sqlite3_open_v2(const char *path, sqlite3 **output, int flags, const char *vfs) {
    int (*real)(const char *, sqlite3 **, int, const char *) = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    if (depth == 0) event('O');
    depth++;
    int result = real(path, output, flags, vfs);
    depth--;
    if (depth == 0 && *output) {
        if (database_owner) _exit(91);
        database_owner = *output;
    }
    return result;
}
int sqlite3_prepare_v3(sqlite3 *database, const char *sql, int count, unsigned flags, sqlite3_stmt **output, const char **tail) {
    int (*real)(sqlite3 *, const char *, int, unsigned, sqlite3_stmt **, const char **) = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    if (depth == 0) { if (database != database_owner) _exit(92); event('P'); }
    depth++;
    int result = real(database, sql, count, flags, output, tail);
    depth--;
    if (depth == 0 && *output) {
        if (database != database_owner || statement_owner) _exit(92);
        statement_owner = *output;
    }
    return result;
}
int sqlite3_bind_text(sqlite3_stmt *statement, int index, const char *bytes, int count, void (*destroy)(void *)) {
    int (*real)(sqlite3_stmt *, int, const char *, int, void (*)(void *)) = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    if (depth == 0) { if (statement != statement_owner) _exit(93); event('T'); }
    depth++;
    int result = real(statement, index, bytes, count, destroy);
    depth--;
    return result;
}
int sqlite3_bind_blob(sqlite3_stmt *statement, int index, const void *bytes, int count, void (*destroy)(void *)) {
    int (*real)(sqlite3_stmt *, int, const void *, int, void (*)(void *)) = dlsym(RTLD_NEXT, "sqlite3_bind_blob");
    if (depth == 0) { if (statement != statement_owner) _exit(94); event('B'); }
    depth++;
    int result = real(statement, index, bytes, count, destroy);
    depth--;
    return result;
}
int sqlite3_finalize(sqlite3_stmt *statement) {
    int (*real)(sqlite3_stmt *) = dlsym(RTLD_NEXT, "sqlite3_finalize");
    depth++;
    int result = real(statement);
    depth--;
    if (depth == 0 && statement) {
        if (statement != statement_owner) _exit(95);
        statement_owner = NULL;
        event('F');
    }
    return result;
}
int sqlite3_close(sqlite3 *database) {
    int (*real)(sqlite3 *) = dlsym(RTLD_NEXT, "sqlite3_close");
    depth++;
    int result = real(database);
    depth--;
    if (depth == 0 && database && result == 0) {
        if (database != database_owner || statement_owner) _exit(96);
        database_owner = NULL;
        event('C');
    }
    return result;
}
