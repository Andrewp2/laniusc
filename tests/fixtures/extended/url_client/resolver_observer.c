/* Test-only loopback list; reuse the existing resolver ABI/list observer.
 * No production resolver or historical observer behavior is modified. */
#define getaddrinfo retained_observer_getaddrinfo
#define freeaddrinfo retained_observer_freeaddrinfo
#include "../../stdlib_foundation/resolve/observer.c"
#undef getaddrinfo
#undef freeaddrinfo

int getaddrinfo(const char *host, const char *service,
                const struct addrinfo *hints, struct addrinfo **output) {
    const char *script = getenv("LANIUS_URL_RESOLVE_SCRIPT");
    if (!script || strcmp(script, "ordered"))
        return retained_observer_getaddrinfo(host, service, hints, output);
    assert(!configured && host && (!strcmp(host, "url.example.test") || !strcmp(host, "fixture.test")));
    assert(service && hints && hints->ai_family == AF_UNSPEC);
    assert(hints->ai_flags == AI_NUMERICSERV && hints->ai_socktype == SOCK_STREAM &&
           hints->ai_protocol == IPPROTO_TCP);
    assert(setenv("LANIUS_RESOLVE_MODE", "1", 1) == 0);
    errno = 0;
    int result = retained_observer_getaddrinfo(host, service, hints, output);
    assert(result == 0 && synthetic && items && owned == *output);
    static const char *const addresses[] = {"127.0.0.2", "127.0.0.1", "127.0.0.3", "127.0.0.1"};
    unsigned port = (unsigned)strtoul(service, NULL, 10);
    for (size_t i = 0; i < 4; ++i) {
        fill(&items[i], AF_INET, SOCK_STREAM, IPPROTO_TCP, port, i);
        struct sockaddr_in *address = (struct sockaddr_in *)&items[i].address;
        assert(inet_pton(AF_INET, addresses[i], &address->sin_addr) == 1);
    }
    char event[96];
    int length = snprintf(event, sizeof(event), "U %s ordered4 loopback\n", host);
    assert(length > 0 && (size_t)length < sizeof(event));
    trace(event);
    errno = EDOM;
    return result;
}
void freeaddrinfo(struct addrinfo *head) {
    retained_observer_freeaddrinfo(head);
}
