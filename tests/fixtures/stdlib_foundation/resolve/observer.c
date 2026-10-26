/* Test-only native boundary/list faults. Real mode delegates to glibc. */
#define _GNU_SOURCE
#include "abi.h"
#include <arpa/inet.h>
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct item { struct addrinfo info; struct sockaddr_storage address; };
static struct item *items;
static struct addrinfo *owned;
static int synthetic, mode, parameter, configured, inside_native;
static long stats[15];
static void trace(const char *event) {
    const char *path = getenv("LANIUS_RESOLVE_TRACE"); if (!path) return;
    int saved = errno; int file = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (file < 0 || write(file, event, strlen(event)) != (ssize_t)strlen(event)) _Exit(96);
    close(file); errno = saved;
}
static void configure(void) {
    if (configured) return;
    const char *value = getenv("LANIUS_RESOLVE_MODE"); mode = value ? atoi(value) : 0;
    value = getenv("LANIUS_RESOLVE_COUNT"); parameter = value ? atoi(value) : 0;
    configured = 1;
}
void test_resolve_begin(int selected, int count) {
    assert(!owned && !items); memset(stats, 0, sizeof(stats)); mode = selected; parameter = count; configured = 1;
}
long test_resolve_stat(int index) { assert(index >= 0 && index < 15); return stats[index]; }
void test_resolve_clobber_errno(void) { errno = ERANGE; }
static uint32_t hash(const char *text) {
    if (!text) return 0;
    uint32_t value = 2166136261u; while (*text) { value = (value ^ (unsigned char)*text++) * 16777619u; } return value;
}
static void *symbol(const char *name) { void *value = dlsym(RTLD_NEXT, name); if (!value) _Exit(95); return value; }
static void fill(struct item *item, int family, int type, int protocol, unsigned port, size_t ordinal) {
    item->info.ai_flags = (int)0xa5a5a5a5u; /* Output flags are unspecified. */
    item->info.ai_family = family; item->info.ai_socktype = type; item->info.ai_protocol = protocol;
    item->info.ai_addr = (struct sockaddr *)&item->address;
    if (family == AF_INET) {
        struct sockaddr_in *address = (struct sockaddr_in *)&item->address;
        address->sin_family = AF_INET; address->sin_port = htons((uint16_t)port);
        assert(inet_pton(AF_INET, "198.51.100.227", &address->sin_addr) == 1);
        item->info.ai_addrlen = sizeof(*address);
    } else {
        struct sockaddr_in6 *address = (struct sockaddr_in6 *)&item->address;
        address->sin6_family = AF_INET6; address->sin6_port = htons((uint16_t)port);
        assert(inet_pton(AF_INET6, ordinal % 4 == 3 ? "::ffff:192.0.2.123" : "2001:db8:1234:ffff:0:abcd:dead:beef", &address->sin6_addr) == 1);
        address->sin6_scope_id = ordinal % 4 == 3 ? UINT32_MAX : 0x89abcdefu;
        item->info.ai_addrlen = sizeof(*address);
    }
}
int getaddrinfo(const char *host, const char *service, const struct addrinfo *hints, struct addrinfo **output) {
    int incoming_errno = errno; configure(); assert(incoming_errno == 0);
    assert(!owned && hints && output && (uintptr_t)hints % 8 == 0 && (uintptr_t)output % 8 == 0);
    assert((const char *)output == (const char *)hints + 48 && !*output);
    assert(hints->ai_family == AF_UNSPEC || hints->ai_family == AF_INET || hints->ai_family == AF_INET6);
    assert((hints->ai_socktype == SOCK_STREAM && hints->ai_protocol == IPPROTO_TCP) || (hints->ai_socktype == SOCK_DGRAM && hints->ai_protocol == IPPROTO_UDP));
    assert(!(hints->ai_flags & ~(AI_PASSIVE | AI_NUMERICHOST | AI_V4MAPPED | AI_ALL | AI_ADDRCONFIG | AI_NUMERICSERV)));
    for (size_t i = 16; i < 48; i++) assert(((const unsigned char *)hints)[i] == 0);
    size_t host_length = host ? strnlen(host, 65537) : 0, service_length = service ? strnlen(service, 4097) : 0;
    assert(host_length <= 65536 && service_length <= 4096);
    stats[0]++; stats[4] = hints->ai_flags; stats[5] = hints->ai_family; stats[6] = hints->ai_socktype; stats[7] = hints->ai_protocol;
    stats[8] = (long)host_length; stats[9] = (long)service_length; stats[10] = !host; stats[11] = !service; stats[12] = incoming_errno; stats[13] = hash(host); stats[14] = hash(service);
    char event[256]; snprintf(event, sizeof(event), "G %d %d %d %d %d %d %zu %zu %d\n", hints->ai_flags, hints->ai_family, hints->ai_socktype, hints->ai_protocol, !host, !service, host_length, service_length, mode); trace(event);
    if (mode == 0) {
        int (*native)(const char *, const char *, const struct addrinfo *, struct addrinfo **) = symbol("getaddrinfo");
        errno = 0; inside_native++; int result = native(host, service, hints, output); int saved = errno; inside_native--;
        if (!result && *output) { owned = *output; stats[2] = 1; synthetic = 0; }
        errno = saved; return result;
    }
    if (mode == 2) { *output = NULL; errno = EIO; return 0; }
    if (mode >= 3 && mode <= 7) {
        *output = NULL; errno = mode == 3 ? EACCES : E2BIG;
        if (mode == 3) return EAI_SYSTEM;
        if (mode == 4) return EAI_NONAME;
        if (mode == 5) return EAI_MEMORY;
        if (mode == 6) return EAI_AGAIN;
        return -1234;
    }
    if (mode == 21) { *output = NULL; errno = E2BIG; return EAI_SERVICE; }
    if (mode == 22) { static struct addrinfo error_slot; *output = &error_slot; errno = ENOENT; return EAI_FAIL; }
    size_t count = (mode == 16 || mode == 17) ? (size_t)parameter : 4;
    assert(count > 0 && count <= 4097);
    items = calloc(count, sizeof(*items)); assert(items); synthetic = 1;
    unsigned port = service && (hints->ai_flags & AI_NUMERICSERV) ? (unsigned)strtoul(service, NULL, 10) : service ? 43210 : 0;
    for (size_t i = 0; i < count; i++) {
        int family = hints->ai_family ? hints->ai_family : i % 2 ? AF_INET6 : AF_INET;
        fill(&items[i], family, hints->ai_socktype, hints->ai_protocol, port, i);
        items[i].info.ai_next = i + 1 < count ? &items[i + 1].info : NULL;
    }
    size_t bad = parameter >= 0 && (size_t)parameter < count ? (size_t)parameter : 0;
    struct addrinfo *entry = &items[bad].info;
    if (mode == 8) entry->ai_family = AF_UNIX;
    if (mode == 9) entry->ai_socktype = SOCK_RAW;
    if (mode == 10) entry->ai_protocol = IPPROTO_ICMP;
    if (mode == 11) entry->ai_addrlen--;
    if (mode == 12) entry->ai_addrlen++;
    if (mode == 13) entry->ai_addr = NULL;
    if (mode == 14) ((struct sockaddr *)entry->ai_addr)->sa_family = entry->ai_family == AF_INET ? AF_INET6 : AF_INET;
    if (mode == 15) { assert(entry->ai_family == AF_INET6); ((struct sockaddr_in6 *)entry->ai_addr)->sin6_flowinfo = htonl(1); }
    if (mode == 17) items[count - 1].info.ai_next = &items[0].info;
    if (mode == 18) { if (entry->ai_family == AF_INET) ((struct sockaddr_in *)entry->ai_addr)->sin_port = htons(1); else ((struct sockaddr_in6 *)entry->ai_addr)->sin6_port = htons(1); }
    if (mode == 19) entry->ai_canonname = (char *)(uintptr_t)1; /* Not requested; never dereference. */
    if (mode == 20) entry->ai_family = entry->ai_family == AF_INET ? AF_INET6 : AF_INET;
    owned = &items[0].info; stats[2] = 1; *output = owned; errno = EDOM; return 0;
}
void freeaddrinfo(struct addrinfo *head) {
    if (inside_native) { void (*native)(struct addrinfo *) = symbol("freeaddrinfo"); native(head); return; }
    if (!head || head != owned) { stats[3]++; _Exit(94); }
    stats[1]++; stats[2] = 0; trace("F\n"); owned = NULL;
    if (synthetic) { memset(items, 0xdd, ((mode == 16 || mode == 17) ? (size_t)parameter : 4) * sizeof(*items)); free(items); items = NULL; }
    else { void (*native)(struct addrinfo *) = symbol("freeaddrinfo"); native(head); }
    errno = EDOM;
}
