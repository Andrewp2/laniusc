/* Test-only ownership/fault/transport observer. TLS always delegates to libssl. */
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

struct owner { const void *pointer; int live; };
static struct owner contexts[64], sessions[64];
static int context_owners, session_owners, invalid_frees, calls, io_calls;
static int inside_session, fault_mode, fault_hits, forced_io;
static struct timespec deadline;

static void *resolve(const char *name) {
    void *function = dlsym(RTLD_NEXT, name);
    if (!function) { fprintf(stderr, "server TLS observer cannot resolve %s\n", name); _Exit(98); }
    return function;
}
static void record(struct owner *owners, const void *pointer) {
    for (int index = 0; index < 64; index++) {
        if (!owners[index].live) { owners[index] = (struct owner) { pointer, 1 }; return; }
    }
    _Exit(97);
}
static int release(struct owner *owners, const void *pointer) {
    for (int index = 0; index < 64; index++) {
        if (owners[index].live && owners[index].pointer == pointer) { owners[index].live = 0; return 1; }
    }
    invalid_frees++;
    return 0;
}
static int fail(int mode) {
    calls++;
    if (fault_mode != mode || fault_hits) { return 0; }
    fault_hits++;
    ERR_raise(ERR_LIB_USER, 400 + mode);
    return 1;
}

const SSL_METHOD *TLS_server_method(void) {
    const SSL_METHOD *(*native)(void) = resolve("TLS_server_method");
    return fail(1) ? NULL : native();
}
SSL_CTX *SSL_CTX_new(const SSL_METHOD *method) {
    SSL_CTX *(*native)(const SSL_METHOD *) = resolve("SSL_CTX_new");
    if (fail(2)) { return NULL; }
    SSL_CTX *result = native(method);
    if (result) { record(contexts, result); context_owners++; }
    return result;
}
void SSL_CTX_free(SSL_CTX *context) {
    void (*native)(SSL_CTX *) = resolve("SSL_CTX_free");
    if (context && !inside_session) {
        assert(SSL_CTX_get_default_passwd_cb_userdata(context) == NULL);
        if (!release(contexts, context)) { return; }
        context_owners--;
    }
    native(context);
}
long SSL_CTX_ctrl(SSL_CTX *context, int command, long argument, void *pointer) {
    long (*native)(SSL_CTX *, int, long, void *) = resolve("SSL_CTX_ctrl");
    if (command == SSL_CTRL_SET_MIN_PROTO_VERSION && fail(3)) { return 0; }
    return native(context, command, argument, pointer);
}
int SSL_CTX_use_certificate_chain_file(SSL_CTX *context, const char *path) {
    int (*native)(SSL_CTX *, const char *) = resolve("SSL_CTX_use_certificate_chain_file");
    assert(SSL_CTX_get_default_passwd_cb(context) == NULL);
    assert(SSL_CTX_get_default_passwd_cb_userdata(context) != NULL);
    return fail(4) ? 0 : native(context, path);
}
int SSL_CTX_use_PrivateKey_file(SSL_CTX *context, const char *path, int type) {
    int (*native)(SSL_CTX *, const char *, int) = resolve("SSL_CTX_use_PrivateKey_file");
    assert(SSL_CTX_get_default_passwd_cb(context) == NULL);
    assert(SSL_CTX_get_default_passwd_cb_userdata(context) != NULL);
    return fail(5) ? 0 : native(context, path, type);
}
int SSL_CTX_check_private_key(const SSL_CTX *context) {
    int (*native)(const SSL_CTX *) = resolve("SSL_CTX_check_private_key");
    return fail(6) ? 0 : native(context);
}
SSL *SSL_new(SSL_CTX *context) {
    SSL *(*native)(SSL_CTX *) = resolve("SSL_new");
    assert(SSL_CTX_get_default_passwd_cb_userdata(context) == NULL);
    if (fail(7)) { return NULL; }
    inside_session++;
    SSL *result = native(context);
    inside_session--;
    if (result) { record(sessions, result); session_owners++; }
    return result;
}
void SSL_free(SSL *session) {
    void (*native)(SSL *) = resolve("SSL_free");
    if (session) {
        if (!release(sessions, session)) { return; }
        session_owners--;
    }
    inside_session++;
    native(session);
    inside_session--;
}
int SSL_set_fd(SSL *session, int fd) {
    int (*native)(SSL *, int) = resolve("SSL_set_fd");
    return fail(8) ? 0 : native(session, fd);
}
int SSL_do_handshake(SSL *session) {
    int (*native)(SSL *) = resolve("SSL_do_handshake");
    io_calls++;
    if (fail(9)) { forced_io = 1; return -1; }
    return native(session);
}
int SSL_read_ex(SSL *session, void *buffer, size_t length, size_t *count) {
    int (*native)(SSL *, void *, size_t, size_t *) = resolve("SSL_read_ex");
    io_calls++;
    if (fail(10)) { forced_io = 1; return 0; }
    return native(session, buffer, length, count);
}
int SSL_write_ex(SSL *session, const void *buffer, size_t length, size_t *count) {
    int (*native)(SSL *, const void *, size_t, size_t *) = resolve("SSL_write_ex");
    io_calls++;
    if (fail(11)) { forced_io = 1; return 0; }
    return native(session, buffer, length, count);
}
int SSL_shutdown(SSL *session) {
    int (*native)(SSL *) = resolve("SSL_shutdown");
    io_calls++;
    if (fail(12)) { forced_io = 1; return -1; }
    return native(session);
}
int SSL_get_error(const SSL *session, int result) {
    int (*native)(const SSL *, int) = resolve("SSL_get_error");
    if (forced_io) { forced_io = 0; return SSL_ERROR_SSL; }
    return native(session, result);
}

void tls_server_test_start(int mode) {
    assert(mode >= 0 && mode <= 12);
    fault_mode = mode;
    assert(clock_gettime(CLOCK_MONOTONIC, &deadline) == 0);
    deadline.tv_sec += 5;
}
int tls_server_test_wait(int fd, int writing) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    long remaining = (deadline.tv_sec - now.tv_sec) * 1000 + (deadline.tv_nsec - now.tv_nsec) / 1000000;
    if (remaining <= 0) { return 0; }
    struct pollfd item = { fd, writing ? POLLOUT : POLLIN, 0 };
    int result;
    do { result = poll(&item, 1, (int)remaining); } while (result < 0 && errno == EINTR);
    return result > 0 && !(item.revents & POLLNVAL);
}
int tls_server_test_fd_open(int fd) { return fcntl(fd, F_GETFD) >= 0; }
int tls_server_test_fd_nonblocking(int fd) { int flags = fcntl(fd, F_GETFL); return flags >= 0 && (flags & O_NONBLOCK) != 0; }
int tls_server_test_close_fd(int fd) { return close(fd); }
void tls_server_test_dirty_queue(void) { ERR_raise(ERR_LIB_USER, 42); }
int tls_server_test_context_owners(void) { return context_owners; }
int tls_server_test_session_owners(void) { return session_owners; }
int tls_server_test_invalid_frees(void) { return invalid_frees; }
int tls_server_test_calls(void) { return calls; }
int tls_server_test_io_calls(void) { return io_calls; }
int tls_server_test_fault_hits(void) { return fault_hits; }

#ifdef TLS_SERVER_OBSERVER_SELF_TEST
int main(void) {
    tls_server_test_start(0);
    SSL_CTX *context = SSL_CTX_new(TLS_server_method());
    assert(context && tls_server_test_context_owners() == 1);
    SSL *session = SSL_new(context);
    assert(session && tls_server_test_session_owners() == 1);
    SSL_CTX_free(context);
    assert(tls_server_test_context_owners() == 0 && tls_server_test_session_owners() == 1);
    SSL_free(session);
    assert(!tls_server_test_context_owners() && !tls_server_test_session_owners());
    assert(!tls_server_test_invalid_frees());
    tls_server_test_start(2);
    assert(!SSL_CTX_new(TLS_server_method()) && tls_server_test_fault_hits() == 1);
    assert(ERR_get_error());
    puts("openssl-tls-server observer: retained references, cleanup and acquisition fault passed");
    return 0;
}
#endif
