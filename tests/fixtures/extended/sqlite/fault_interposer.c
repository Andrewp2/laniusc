// Test-only faults. Successful calls delegate to the real system SQLite.
// O/X/Y/R/P: open/configure/readonly/prepare. i/d/t/b: scalar/byte binds.
// K/Q/S: clear/reset/step. T/B/N/E: column ptr/bytes/immediate errcode.
// F/C: external finalize/close. Nested calls inside SQLite are not traced.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static sqlite3 *database;
static sqlite3_stmt *statement;
static unsigned native_depth;
static int fired;
static int poisoned;
static int invalid_text;

static int mode(const char *name) {
    const char *value = getenv("LANIUS_SQLITE_FAULT");
    return value && strcmp(value, name) == 0;
}
static int take(const char *name) {
    if (fired || !mode(name)) return 0;
    fired = 1; return 1;
}
static void trace(char event) {
    const char *path = getenv("LANIUS_SQLITE_TRACE");
    if (!path) _exit(90);
    int file = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (file < 0 || write(file, &event, 1) != 1) _exit(91);
    close(file);
}
static void *symbol(const char *name) {
    void *value = dlsym(RTLD_NEXT, name);
    if (!value) _exit(92);
    return value;
}
#define NEXT(name) __typeof__(&(name)) real = (__typeof__(&(name)))symbol(#name)
#define FORWARD(...) do { ++native_depth; int result = real(__VA_ARGS__); --native_depth; return result; } while (0)

int sqlite3_open_v2(const char *path, sqlite3 **output, int flags, const char *vfs) {
    NEXT(sqlite3_open_v2);
    if (native_depth) return real(path, output, flags, vfs);
    trace('O');
    if (take("open-null")) { *output = NULL; return SQLITE_CANTOPEN; }
    if (take("open-ok-null")) { *output = NULL; return SQLITE_OK; }
    ++native_depth; int result = real(path, output, flags, vfs); --native_depth;
    database = *output;
    if (take("open-handle")) return SQLITE_CANTOPEN;
    return result;
}
int sqlite3_extended_result_codes(sqlite3 *db, int enabled) {
    NEXT(sqlite3_extended_result_codes);
    if (native_depth || db != database) return real(db, enabled);
    trace('X'); if (take("configure-extended")) return SQLITE_MISUSE;
    FORWARD(db, enabled);
}
int sqlite3_busy_timeout(sqlite3 *db, int milliseconds) {
    NEXT(sqlite3_busy_timeout);
    if (native_depth || db != database) return real(db, milliseconds);
    trace('Y'); if (take("configure-busy")) return SQLITE_NOMEM;
    FORWARD(db, milliseconds);
}
int sqlite3_db_readonly(sqlite3 *db, const char *schema) {
    NEXT(sqlite3_db_readonly);
    if (native_depth || db != database) return real(db, schema);
    trace('R'); if (take("readonly-fallback")) return 1;
    FORWARD(db, schema);
}
int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int count, unsigned flags,
                       sqlite3_stmt **output, const char **tail) {
    NEXT(sqlite3_prepare_v3);
    if (native_depth || db != database) return real(db, sql, count, flags, output, tail);
    trace('P');
    ++native_depth; int result = real(db, sql, count, flags, output, tail); --native_depth;
    statement = *output;
    if (take("prepare-handle")) return SQLITE_NOMEM;
    if (take("prepare-tail")) *tail = sql + count + 1;
    return result;
}
int sqlite3_bind_int64(sqlite3_stmt *stmt, int index, sqlite3_int64 value) {
    NEXT(sqlite3_bind_int64);
    if (native_depth || stmt != statement) return real(stmt, index, value);
    trace('i'); if (take("bind-int")) return SQLITE_RANGE;
    FORWARD(stmt, index, value);
}
int sqlite3_bind_double(sqlite3_stmt *stmt, int index, double value) {
    NEXT(sqlite3_bind_double);
    if (native_depth || stmt != statement) return real(stmt, index, value);
    trace('d'); if (take("bind-real")) return SQLITE_NOMEM;
    FORWARD(stmt, index, value);
}
int sqlite3_bind_text(sqlite3_stmt *stmt, int index, const char *bytes, int count,
                      void (*destroy)(void *)) {
    NEXT(sqlite3_bind_text);
    if (native_depth || stmt != statement) return real(stmt, index, bytes, count, destroy);
    trace('t');
    if (!bytes || destroy != SQLITE_TRANSIENT) _exit(94);
    if (take("bind-text")) return SQLITE_NOMEM;
    FORWARD(stmt, index, bytes, count, destroy);
}
int sqlite3_bind_blob(sqlite3_stmt *stmt, int index, const void *bytes, int count,
                      void (*destroy)(void *)) {
    NEXT(sqlite3_bind_blob);
    if (native_depth || stmt != statement) return real(stmt, index, bytes, count, destroy);
    trace('b');
    if (!bytes || destroy != SQLITE_TRANSIENT) _exit(94);
    if (take("bind-blob")) return SQLITE_NOMEM;
    FORWARD(stmt, index, bytes, count, destroy);
}
int sqlite3_clear_bindings(sqlite3_stmt *stmt) {
    NEXT(sqlite3_clear_bindings);
    if (native_depth || stmt != statement) return real(stmt);
    trace('K'); if (take("clear")) return SQLITE_NOMEM;
    FORWARD(stmt);
}
int sqlite3_reset(sqlite3_stmt *stmt) {
    NEXT(sqlite3_reset);
    if (native_depth || stmt != statement) return real(stmt);
    trace('Q');
    ++native_depth; int result = real(stmt); --native_depth;
    if (poisoned) { poisoned = 0; return SQLITE_NOMEM; }
    if (take("reset")) return SQLITE_CONSTRAINT;
    return result;
}
int sqlite3_step(sqlite3_stmt *stmt) {
    NEXT(sqlite3_step);
    if (native_depth || stmt != statement) return real(stmt);
    trace('S'); if (take("step")) return SQLITE_BUSY;
    FORWARD(stmt);
}
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int index) {
    NEXT(sqlite3_column_text);
    if (native_depth || stmt != statement) return real(stmt, index);
    trace('T');
    if (take("column-text-null")) { poisoned = 1; return NULL; }
    if (take("column-invalid-utf8")) { static const unsigned char bad[] = {255, 0}; invalid_text = 1; return bad; }
    ++native_depth; const unsigned char *result = real(stmt, index); --native_depth;
    return result;
}
const void *sqlite3_column_blob(sqlite3_stmt *stmt, int index) {
    NEXT(sqlite3_column_blob);
    if (native_depth || stmt != statement) return real(stmt, index);
    trace('B');
    if (take("column-blob-null")) { poisoned = 1; return NULL; }
    ++native_depth; const void *result = real(stmt, index); --native_depth;
    return result;
}
int sqlite3_column_bytes(sqlite3_stmt *stmt, int index) {
    NEXT(sqlite3_column_bytes);
    if (native_depth || stmt != statement) return real(stmt, index);
    trace('N');
    if (invalid_text && index == 0) return 1;
    if (take("column-bytes-zero")) { poisoned = 1; return 0; }
    FORWARD(stmt, index);
}
int sqlite3_errcode(sqlite3 *db) {
    NEXT(sqlite3_errcode);
    if (native_depth || db != database) return real(db);
    trace('E'); if (poisoned) return SQLITE_NOMEM;
    FORWARD(db);
}
int sqlite3_finalize(sqlite3_stmt *stmt) {
    NEXT(sqlite3_finalize);
    if (native_depth || stmt != statement || !stmt) return real(stmt);
    trace('F'); statement = NULL;
    ++native_depth; int result = real(stmt); --native_depth;
    if (take("finalize") || mode("prepare-handle")) return SQLITE_IOERR;
    if (poisoned) { poisoned = 0; return SQLITE_NOMEM; }
    return result;
}
int sqlite3_close(sqlite3 *db) {
    NEXT(sqlite3_close);
    if (native_depth || db != database || !db) return real(db);
    trace('C'); if (take("close")) return SQLITE_BUSY;
    ++native_depth; int result = real(db); --native_depth;
    if (result == SQLITE_OK) database = NULL;
    if (mode("open-handle") || mode("configure-extended") || mode("configure-busy")) return SQLITE_IOERR;
    return result;
}
