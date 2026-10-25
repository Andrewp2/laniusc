// Fault injection only: every successful digest call uses the real libcrypto.
// Trace: F fetch, S size, C ctx-new, I init, U update, D final, c/m releases.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static EVP_MD *tracked_method;
static EVP_MD_CTX *tracked_context;
static unsigned update_calls;
static unsigned native_depth;

static int fault(const char *name) {
    const char *mode = getenv("LANIUS_OPENSSL_FAULT");
    size_t length = strlen(name);
    return mode && (strcmp(mode, name) == 0 ||
                    (strncmp(mode, name, length) == 0 && strcmp(mode + length, "-empty") == 0));
}
static void trace(char event) {
    const char *path = getenv("LANIUS_OPENSSL_TRACE");
    if (!path) _exit(90);
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0 || write(fd, &event, 1) != 1) _exit(91);
    close(fd);
}
static void *symbol(const char *name) {
    void *result = dlsym(RTLD_NEXT, name);
    if (!result) _exit(92);
    return result;
}
static int fail(void) {
    const char *mode = getenv("LANIUS_OPENSSL_FAULT");
    if (mode && strstr(mode, "-empty")) return 0;
    // Earliest code must survive draining the queue and cleanup poisoning.
    ERR_raise(ERR_LIB_USER, 0x123);
    ERR_raise(ERR_LIB_USER, 0x124);
    return 0;
}
EVP_MD *EVP_MD_fetch(OSSL_LIB_CTX *context, const char *name, const char *properties) {
    EVP_MD *(*real)(OSSL_LIB_CTX *, const char *, const char *) = symbol("EVP_MD_fetch");
    if (native_depth) return real(context, name, properties);
    trace('F');
    if (fault("fetch")) { fail(); return NULL; }
    ++native_depth;
    tracked_method = real(context, name, properties);
    --native_depth;
    // The next native call must clear this stale diagnostic first.
    ERR_raise(ERR_LIB_USER, 0x666);
    return tracked_method;
}
int EVP_MD_get_size(const EVP_MD *method) {
    int (*real)(const EVP_MD *) = symbol("EVP_MD_get_size");
    if (native_depth || method != tracked_method) return real(method);
    trace('S');
    if (fault("size-native")) { fail(); return -1; }
    if (fault("size-unexpected")) return 0;
    ++native_depth; int result = real(method); --native_depth;
    return result;
}
EVP_MD_CTX *EVP_MD_CTX_new(void) {
    EVP_MD_CTX *(*real)(void) = symbol("EVP_MD_CTX_new");
    if (native_depth) return real();
    trace('C');
    if (fault("context")) { fail(); return NULL; }
    ++native_depth; tracked_context = real(); --native_depth;
    return tracked_context;
}
int EVP_DigestInit_ex2(EVP_MD_CTX *context, const EVP_MD *method, const OSSL_PARAM parameters[]) {
    int (*real)(EVP_MD_CTX *, const EVP_MD *, const OSSL_PARAM *) = symbol("EVP_DigestInit_ex2");
    if (native_depth || context != tracked_context) return real(context, method, parameters);
    trace('I');
    if (fault("init")) return fail();
    ++native_depth; int result = real(context, method, parameters); --native_depth;
    return result;
}
int EVP_DigestUpdate(EVP_MD_CTX *context, const void *bytes, size_t count) {
    int (*real)(EVP_MD_CTX *, const void *, size_t) = symbol("EVP_DigestUpdate");
    if (native_depth || context != tracked_context) return real(context, bytes, count);
    if (count == 13) {
        trace('P');
        ++native_depth; int result = real(context, bytes, count); --native_depth;
        return result;
    }
    trace('U'); ++update_calls;
    if ((fault("update-first") && update_calls == 1) ||
        (fault("update-second") && update_calls == 2) ||
        (fault("update-third") && update_calls == 3)) return fail();
    ++native_depth; int result = real(context, bytes, count); --native_depth;
    return result;
}
int EVP_DigestFinal_ex(EVP_MD_CTX *context, unsigned char *output, unsigned int *length) {
    int (*real)(EVP_MD_CTX *, unsigned char *, unsigned int *) = symbol("EVP_DigestFinal_ex");
    if (native_depth || context != tracked_context) return real(context, output, length);
    trace('D');
    if (fault("final")) {
        // The wrapper must keep this scribble inside its staging buffer.
        memset(output, 0xA7, 32);
        return fail();
    }
    ++native_depth; int result = real(context, output, length); --native_depth;
    return result;
}
void EVP_MD_CTX_free(EVP_MD_CTX *context) {
    void (*real)(EVP_MD_CTX *) = symbol("EVP_MD_CTX_free");
    if (!native_depth && context == tracked_context && context) {
        trace('c'); tracked_context = NULL;
        ERR_raise(ERR_LIB_USER, 0x567);
    }
    ++native_depth; real(context); --native_depth;
}
void EVP_MD_free(EVP_MD *method) {
    void (*real)(EVP_MD *) = symbol("EVP_MD_free");
    if (!native_depth && method == tracked_method && method) {
        trace('m'); tracked_method = NULL;
        ERR_raise(ERR_LIB_USER, 0x568);
    }
    ++native_depth; real(method); --native_depth;
}
