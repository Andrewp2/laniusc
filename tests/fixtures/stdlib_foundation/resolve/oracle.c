/* Independent CPU reference. Resolution is always the real installed libc. */
#define _GNU_SOURCE
#include "abi.h"
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void hex(const unsigned char *bytes, size_t count) { for (size_t i = 0; i < count; i++) printf("%02x", bytes[i]); }
int main(int argc, char **argv) {
    if (argc != 6) return 90;
    const char *host = strcmp(argv[1], "-") ? argv[1] : NULL;
    const char *service = strcmp(argv[2], "-") ? argv[2] : NULL;
    struct addrinfo hints = {0}, *head = NULL;
    hints.ai_family = atoi(argv[3]); hints.ai_socktype = atoi(argv[4]);
    hints.ai_protocol = hints.ai_socktype == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP;
    hints.ai_flags = atoi(argv[5]);
    errno = 0; int code = getaddrinfo(host, service, &hints, &head); int saved = errno;
    if (code) { printf("N%d:%d\n", code, code == EAI_SYSTEM ? saved : 0); return 0; }
    if (!head) return 91;
    putchar('O'); size_t count = 0;
    for (struct addrinfo *entry = head; entry; entry = entry->ai_next) {
        if (++count > 4096) return 92;
        if (entry->ai_family == AF_INET) {
            const struct sockaddr_in *address = (const struct sockaddr_in *)entry->ai_addr;
            printf("4:%u:0:", ntohs(address->sin_port)); hex((const unsigned char *)&address->sin_addr, 4);
        } else if (entry->ai_family == AF_INET6) {
            const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)entry->ai_addr;
            printf("6:%u:%u:", ntohs(address->sin6_port), address->sin6_scope_id); hex((const unsigned char *)&address->sin6_addr, 16);
        } else return 93;
        putchar('/');
    }
    freeaddrinfo(head); putchar('\n'); return ferror(stdout) ? 94 : 0;
}
