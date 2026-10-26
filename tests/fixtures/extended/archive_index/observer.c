#define _GNU_SOURCE
#include <dlfcn.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Test-only native faults/lifetime observation, never production storage. */
static _Thread_local unsigned depth;
static sqlite3 *owner;
static sqlite3_stmt *statement_owner;
static int replacing, entries, failed;
static void event(char code) {
    const char *fd = getenv("ARCHIVE_TRACE_FD");
    if (fd && write(atoi(fd), &code, 1) != 1) _exit(90);
}
static int mode(const char *name) {
    const char *value = getenv("ARCHIVE_FAIL");
    return value && strcmp(value, name) == 0;
}
int sqlite3_open_v2(const char *path, sqlite3 **out, int flags, const char *vfs) {
    int (*real)(const char *,sqlite3 **,int,const char *) = dlsym(RTLD_NEXT,"sqlite3_open_v2");
    depth++; int result = real(path,out,flags,vfs); depth--;
    if (!depth && *out) { if (owner) _exit(91); owner = *out; event('O'); }
    return result;
}
int sqlite3_prepare_v3(sqlite3 *db,const char *sql,int n,unsigned flags,sqlite3_stmt **out,const char **tail) {
    int (*real)(sqlite3 *,const char *,int,unsigned,sqlite3_stmt **,const char **) = dlsym(RTLD_NEXT,"sqlite3_prepare_v3");
    depth++; int result = real(db,sql,n,flags,out,tail); depth--;
    if (!depth && *out) { if (owner != db || statement_owner) _exit(92); statement_owner = *out; event('P'); }
    return result;
}
int sqlite3_step(sqlite3_stmt *statement) {
    int (*real)(sqlite3_stmt *) = dlsym(RTLD_NEXT,"sqlite3_step");
    const char *sql = sqlite3_sql(statement);
    if (!depth && sql) {
        if (strncmp(sql,"DELETE FROM archive_index_entries",33) == 0) replacing = 1;
        if (replacing && strncmp(sql,"INSERT INTO archive_index_entries",33) == 0) {
            entries++;
            if (!failed && entries == 2 && (mode("step") || mode("rollback"))) { failed = 1; event('E'); return SQLITE_IOERR; }
        }
        if (replacing && strcmp(sql,"COMMIT") == 0 && !failed) {
            if (mode("commit-before")) { failed = 1; event('E'); return SQLITE_IOERR; }
            if (mode("commit-after")) { depth++; int result = real(statement); depth--; if (result != SQLITE_DONE) _exit(93); failed = 1; event('E'); return SQLITE_IOERR; }
        }
        if (replacing && strcmp(sql,"ROLLBACK") == 0 && mode("rollback")) { event('R'); return SQLITE_IOERR; }
    }
    depth++; int result = real(statement); depth--; return result;
}
int sqlite3_finalize(sqlite3_stmt *statement) {
    int (*real)(sqlite3_stmt *) = dlsym(RTLD_NEXT,"sqlite3_finalize");
    depth++; int result = real(statement); depth--;
    if (!depth && statement) { if (statement_owner != statement) _exit(94); statement_owner = NULL; event('F'); }
    return result;
}
int sqlite3_close(sqlite3 *db) {
    int (*real)(sqlite3 *) = dlsym(RTLD_NEXT,"sqlite3_close");
    depth++; int result = real(db); depth--;
    if (!depth && db && result == SQLITE_OK) { if (owner != db || statement_owner) _exit(95); owner = NULL; event('C'); }
    return result;
}
