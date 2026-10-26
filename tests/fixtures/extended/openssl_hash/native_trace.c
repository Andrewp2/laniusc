#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Test observation/fault injection only. Every normal call reaches libcrypto. */
static _Thread_local unsigned depth;
static void *watched_method;
static void *watched_context;
static int fail(const char *stage) {
    const char *selected = getenv("LANIUS_OPENSSL_HASH_FAIL");
    return selected && strcmp(selected, stage) == 0;
}
static void event(const char *text) {
    const char *path = getenv("LANIUS_OPENSSL_HASH_TRACE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) _exit(90);
    size_t length = strlen(text);
    if (write(fd, text, length) != (ssize_t)length) _exit(91);
    if (close(fd) != 0) _exit(92);
}
void *EVP_MD_fetch(void *context, const char *name, const char *properties) {
    if (depth == 0 && fail("fetch")) return NULL;
    void *(*real)(void *, const char *, const char *) = dlsym(RTLD_NEXT, "EVP_MD_fetch");
    depth++;
    void *result = real(context, name, properties);
    depth--;
    if (depth == 0 && result) { watched_method = result; event("method+\n"); }
    return result;
}
int EVP_MD_get_size(const void *method) {
    if (depth == 0 && fail("size")) return -1;
    int (*real)(const void *) = dlsym(RTLD_NEXT, "EVP_MD_get_size");
    depth++;
    int result = real(method);
    depth--;
    return result;
}
void *EVP_MD_CTX_new(void) {
    if (depth == 0 && fail("context")) return NULL;
    void *(*real)(void) = dlsym(RTLD_NEXT, "EVP_MD_CTX_new");
    depth++;
    void *result = real();
    depth--;
    if (depth == 0 && result) { watched_context = result; event("context+\n"); }
    return result;
}
int EVP_DigestInit_ex2(void *context, const void *method, const void *parameters) {
    if (depth == 0 && fail("init")) return 0;
    int (*real)(void *, const void *, const void *) = dlsym(RTLD_NEXT, "EVP_DigestInit_ex2");
    depth++;
    int result = real(context, method, parameters);
    depth--;
    return result;
}
int EVP_DigestUpdate(void *context, const void *bytes, size_t length) {
    if (depth == 0 && fail("update")) return 0;
    int (*real)(void *, const void *, size_t) = dlsym(RTLD_NEXT, "EVP_DigestUpdate");
    depth++;
    int result = real(context, bytes, length);
    depth--;
    return result;
}
int EVP_DigestFinal_ex(void *context, unsigned char *bytes, unsigned int *length) {
    if (depth == 0 && fail("final")) return 0;
    int (*real)(void *, unsigned char *, unsigned int *) = dlsym(RTLD_NEXT, "EVP_DigestFinal_ex");
    depth++;
    int result = real(context, bytes, length);
    depth--;
    return result;
}
void EVP_MD_CTX_free(void *context) {
    void (*real)(void *) = dlsym(RTLD_NEXT, "EVP_MD_CTX_free");
    if (depth == 0 && context && context == watched_context) {
        watched_context = NULL;
        event("context-\n");
    }
    depth++;
    real(context);
    depth--;
}
void EVP_MD_free(void *method) {
    void (*real)(void *) = dlsym(RTLD_NEXT, "EVP_MD_free");
    if (depth == 0 && method && method == watched_method) {
        watched_method = NULL;
        event("method-\n");
    }
    depth++;
    real(method);
    depth--;
}
