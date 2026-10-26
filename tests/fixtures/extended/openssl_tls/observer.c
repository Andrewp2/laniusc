/* Test-only native observers. Every operation delegates to real OpenSSL. */
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <stdlib.h>

struct owner { const void *pointer; int live; };
static struct owner contexts[64], sessions[64];
static int context_owners, session_owners, invalid_frees, io_calls, inside_session;

static void *resolve(const char *name) {
    void *function = dlsym(RTLD_NEXT, name);
    if (!function) { fprintf(stderr, "TLS observer cannot resolve %s\n", name); _Exit(98); }
    return function;
}

static void record(struct owner *owners, const void *pointer) {
    for (int index = 0; index < 64; index++) {
        if (!owners[index].live) {
            owners[index] = (struct owner) { pointer, 1 };
            return;
        }
    }
    _Exit(97);
}

static int release(struct owner *owners, const void *pointer) {
    for (int index = 0; index < 64; index++) {
        if (owners[index].live && owners[index].pointer == pointer) {
            owners[index].live = 0;
            return 1;
        }
    }
    invalid_frees++;
    return 0;
}

SSL_CTX *SSL_CTX_new(const SSL_METHOD *method) {
    SSL_CTX *(*native)(const SSL_METHOD *) = resolve("SSL_CTX_new");
    SSL_CTX *result = native(method);
    if (result) { record(contexts, result); context_owners++; }
    return result;
}

void SSL_CTX_free(SSL_CTX *context) {
    void (*native)(SSL_CTX *) = resolve("SSL_CTX_free");
    if (context && !inside_session) {
        if (!release(contexts, context)) { return; }
        context_owners--;
    }
    native(context);
}

SSL *SSL_new(SSL_CTX *context) {
    SSL *(*native)(SSL_CTX *) = resolve("SSL_new");
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

int SSL_do_handshake(SSL *session) {
    int (*native)(SSL *) = resolve("SSL_do_handshake");
    io_calls++;
    return native(session);
}

int SSL_read_ex(SSL *session, void *buffer, size_t length, size_t *readbytes) {
    int (*native)(SSL *, void *, size_t, size_t *) = resolve("SSL_read_ex");
    io_calls++;
    return native(session, buffer, length, readbytes);
}

int SSL_write_ex(SSL *session, const void *buffer, size_t length, size_t *written) {
    int (*native)(SSL *, const void *, size_t, size_t *) = resolve("SSL_write_ex");
    io_calls++;
    return native(session, buffer, length, written);
}

int SSL_shutdown(SSL *session) {
    int (*native)(SSL *) = resolve("SSL_shutdown");
    io_calls++;
    return native(session);
}

void tls_test_dirty_error_queue(void) { ERR_raise(ERR_LIB_USER, 42); }
int tls_test_context_owners(void) { return context_owners; }
int tls_test_session_owners(void) { return session_owners; }
int tls_test_invalid_frees(void) { return invalid_frees; }
int tls_test_io_calls(void) { return io_calls; }

#ifdef TLS_OBSERVER_SELF_TEST
int main(void) {
    SSL_CTX *context = SSL_CTX_new(TLS_client_method());
    assert(context && tls_test_context_owners() == 1);
    SSL *session = SSL_new(context);
    assert(session && tls_test_session_owners() == 1);
    SSL_CTX_free(context);
    assert(tls_test_context_owners() == 0 && tls_test_session_owners() == 1);
    SSL_free(session);
    assert(tls_test_context_owners() == 0 && tls_test_session_owners() == 0);
    assert(tls_test_invalid_frees() == 0);
    tls_test_dirty_error_queue();
    assert(ERR_get_error() != 0);
    puts("openssl-tls native observers: context/session owners, retained context reference and dirty queue passed");
    return 0;
}
#endif
