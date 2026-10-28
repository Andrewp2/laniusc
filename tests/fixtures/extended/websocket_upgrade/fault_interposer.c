// Fault injection only. Positive digest computations use the real OpenSSL.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int EVP_Q_digest(OSSL_LIB_CTX *context, const char *name, const char *properties,
                 const void *data, size_t count, unsigned char *output,
                 size_t *length) {
    const char *mode = getenv("LANIUS_WEBSOCKET_FAULT");
    if (mode && strcmp(mode, "provider") == 0) {
        memset(output, 0xa7, 20);
        *length = 20;
        ERR_raise(ERR_LIB_USER, 0x123);
        return 0;
    }
    if (mode && strcmp(mode, "size") == 0) {
        memset(output, 0xa7, 20);
        *length = 19;
        return 1;
    }
    if (mode && strcmp(mode, "wide-size") == 0) {
        memset(output, 0xa7, 20);
        *length = ((size_t)1 << 32) | (size_t)20;
        return 1;
    }
    int (*real)(OSSL_LIB_CTX *, const char *, const char *, const void *, size_t,
                unsigned char *, size_t *) = dlsym(RTLD_NEXT, "EVP_Q_digest");
    if (!real) _exit(92);
    return real(context, name, properties, data, count, output, length);
}
