/* Test-only ownership/fault/transport observer. TLS always delegates to libssl. */
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <string.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

struct owner { const void *pointer; int live; };
static struct owner contexts[64], sessions[64];
static int context_owners, session_owners, invalid_frees, calls, io_calls;
static int inside_session, fault_mode, fault_hits, forced_io, endpoint_role;
static const void *pending_write, *pending_read;
static size_t pending_write_length, pending_read_length;
static unsigned char *pending_write_copy;
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

const SSL_METHOD *TLS_client_method(void) {
    const SSL_METHOD *(*native)(void) = resolve("TLS_client_method");
    return fail(1) ? NULL : native();
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
    if (command == SSL_CTRL_GET_SESS_CACHE_MODE && fail(17)) { return 1; }
    return native(context, command, argument, pointer);
}
void SSL_CTX_set_verify(SSL_CTX *context, int mode, SSL_verify_cb callback) {
    void (*native)(SSL_CTX *, int, SSL_verify_cb) = resolve("SSL_CTX_set_verify");
    assert(callback == NULL && mode == (endpoint_role ? SSL_VERIFY_PEER : (SSL_VERIFY_PEER|SSL_VERIFY_FAIL_IF_NO_PEER_CERT)));
    native(context, mode, callback);
}
int SSL_CTX_set_purpose(SSL_CTX *context, int purpose) {
    int (*native)(SSL_CTX *,int) = resolve("SSL_CTX_set_purpose");
    assert(!endpoint_role && purpose == X509_PURPOSE_SSL_CLIENT);
    return fail(15) ? 0 : native(context,purpose);
}
int SSL_CTX_set_num_tickets(SSL_CTX *context, size_t count) {
    int (*native)(SSL_CTX *,size_t) = resolve("SSL_CTX_set_num_tickets");
    assert(!endpoint_role && count == 0);
    return fail(16) ? 0 : native(context,count);
}
uint64_t SSL_CTX_set_options(SSL_CTX *context, uint64_t options) {
    uint64_t (*native)(SSL_CTX *,uint64_t) = resolve("SSL_CTX_set_options");
    uint64_t result = native(context,options);
    if (options == SSL_OP_NO_TICKET && fail(18)) return result & ~SSL_OP_NO_TICKET;
    return result;
}
int SSL_CTX_load_verify_locations(SSL_CTX *context,const char *file,const char *path) {
    int (*native)(SSL_CTX *,const char *,const char *) = resolve("SSL_CTX_load_verify_locations");
    assert(file && !path); return fail(13) ? 0 : native(context,file,path);
}
int SSL_CTX_set_default_verify_paths(SSL_CTX *context) {
    int (*native)(SSL_CTX *) = resolve("SSL_CTX_set_default_verify_paths");
    return fail(14) ? 0 : native(context);
}
long SSL_get_verify_result(const SSL *session) {
    long (*native)(const SSL *) = resolve("SSL_get_verify_result");
    return fail(19) ? X509_V_ERR_INVALID_PURPOSE : native(session);
}
X509 *SSL_get0_peer_certificate(const SSL *session) {
    X509 *(*native)(const SSL *) = resolve("SSL_get0_peer_certificate");
    if (fault_mode == 20 && !fault_hits) { calls++; fault_hits++; return NULL; }
    return native(session);
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
    assert(SSL_CTX_get_verify_mode(context) == (endpoint_role ? 1 : 3));
    if (!endpoint_role) {
        assert(SSL_CTX_get_session_cache_mode(context) == SSL_SESS_CACHE_OFF);
        assert((SSL_CTX_get_options(context)&SSL_OP_NO_TICKET) != 0);
        assert(SSL_CTX_get_num_tickets(context) == 0);
    }
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
    if (fail(9)) { forced_io = SSL_ERROR_SSL; return -1; }
    return native(session);
}
int SSL_read_ex(SSL *session, void *buffer, size_t length, size_t *count) {
    int (*native)(SSL *, void *, size_t, size_t *) = resolve("SSL_read_ex");
    io_calls++;
    if (fail(10)) { forced_io = SSL_ERROR_SSL; return 0; }
    if (fault_mode == 22 && !fault_hits) { calls++; fault_hits++; pending_read=buffer; pending_read_length=length; forced_io=SSL_ERROR_WANT_READ; return 0; }
    if (pending_read) { assert(buffer==pending_read && length==pending_read_length); }
    int result=native(session,buffer,length,count); if (result==1) pending_read=NULL; return result;
}
int SSL_write_ex(SSL *session, const void *buffer, size_t length, size_t *count) {
    int (*native)(SSL *, const void *, size_t, size_t *) = resolve("SSL_write_ex");
    io_calls++;
    if (fail(11)) { forced_io = SSL_ERROR_SSL; return 0; }
    if (fault_mode == 21 && !fault_hits) {
        calls++; fault_hits++; pending_write=buffer; pending_write_length=length;
        pending_write_copy=malloc(length); assert(pending_write_copy); memcpy(pending_write_copy,buffer,length);
        forced_io=SSL_ERROR_WANT_WRITE; return 0;
    }
    if (pending_write) { assert(buffer==pending_write && length==pending_write_length && memcmp(buffer,pending_write_copy,length)==0); }
    int result=native(session,buffer,length,count);
    if (result==1) { pending_write=NULL; free(pending_write_copy); pending_write_copy=NULL; }
    return result;
}
int SSL_shutdown(SSL *session) {
    int (*native)(SSL *) = resolve("SSL_shutdown");
    io_calls++;
    if (fail(12)) { forced_io = SSL_ERROR_SSL; return -1; }
    return native(session);
}
int SSL_get_error(const SSL *session, int result) {
    int (*native)(const SSL *, int) = resolve("SSL_get_error");
    if (forced_io) { int result = forced_io; forced_io = 0; return result; }
    return native(session, result);
}

void mtls_test_start(int mode,int role) {
    assert(mode >= 0 && mode <= 22 && (role==0 || role==1));
    fault_mode = mode; endpoint_role=role;
    assert(clock_gettime(CLOCK_MONOTONIC, &deadline) == 0);
    deadline.tv_sec += 5;
}
int mtls_test_wait(int fd, int writing) {
    struct timespec now;
    assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    long remaining = (deadline.tv_sec - now.tv_sec) * 1000 + (deadline.tv_nsec - now.tv_nsec) / 1000000;
    if (remaining <= 0) { return 0; }
    struct pollfd item = { fd, writing ? POLLOUT : POLLIN, 0 };
    int result;
    do { result = poll(&item, 1, (int)remaining); } while (result < 0 && errno == EINTR);
    return result > 0 && !(item.revents & POLLNVAL);
}
int mtls_test_fd_open(int fd) { return fcntl(fd, F_GETFD) >= 0; }
int mtls_test_fd_nonblocking(int fd) { int flags = fcntl(fd, F_GETFL); return flags >= 0 && (flags & O_NONBLOCK) != 0; }
int mtls_test_close_fd(int fd) { return close(fd); }
void mtls_test_dirty_queue(void) { ERR_raise(ERR_LIB_USER, 42); }
int mtls_test_context_owners(void) { return context_owners; }
int mtls_test_session_owners(void) { return session_owners; }
int mtls_test_invalid_frees(void) { return invalid_frees; }
int mtls_test_calls(void) { return calls; }
int mtls_test_io_calls(void) { return io_calls; }
int mtls_test_fault_hits(void) { return fault_hits; }
