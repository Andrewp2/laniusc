/* Test-only assertions against the installed Linux x86_64/glibc headers. */
#ifndef LANIUS_RESOLVE_TEST_ABI_H
#define LANIUS_RESOLVE_TEST_ABI_H
#include <stddef.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
_Static_assert(CHAR_BIT == 8 && sizeof(void *) == 8 && sizeof(int) == 4 && sizeof(socklen_t) == 4, "scalar ABI");
_Static_assert(sizeof(struct addrinfo) == 48 && _Alignof(struct addrinfo) == 8, "addrinfo size/alignment");
_Static_assert(offsetof(struct addrinfo, ai_flags) == 0 && offsetof(struct addrinfo, ai_family) == 4 && offsetof(struct addrinfo, ai_socktype) == 8 && offsetof(struct addrinfo, ai_protocol) == 12 && offsetof(struct addrinfo, ai_addrlen) == 16 && offsetof(struct addrinfo, ai_addr) == 24 && offsetof(struct addrinfo, ai_canonname) == 32 && offsetof(struct addrinfo, ai_next) == 40, "addrinfo offsets");
_Static_assert(sizeof(struct sockaddr_in) == 16 && offsetof(struct sockaddr_in, sin_family) == 0 && offsetof(struct sockaddr_in, sin_port) == 2 && offsetof(struct sockaddr_in, sin_addr) == 4, "IPv4 layout");
_Static_assert(sizeof(struct sockaddr_in6) == 28 && offsetof(struct sockaddr_in6, sin6_family) == 0 && offsetof(struct sockaddr_in6, sin6_port) == 2 && offsetof(struct sockaddr_in6, sin6_flowinfo) == 4 && offsetof(struct sockaddr_in6, sin6_addr) == 8 && offsetof(struct sockaddr_in6, sin6_scope_id) == 24, "IPv6 layout");
_Static_assert(AF_UNSPEC == 0 && AF_INET == 2 && AF_INET6 == 10 && SOCK_STREAM == 1 && SOCK_DGRAM == 2 && IPPROTO_TCP == 6 && IPPROTO_UDP == 17, "protocol constants");
_Static_assert(AI_PASSIVE == 1 && AI_NUMERICHOST == 4 && AI_V4MAPPED == 8 && AI_ALL == 16 && AI_ADDRCONFIG == 32 && AI_NUMERICSERV == 1024 && EAI_SYSTEM == -11, "resolver constants");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "little endian profile");
#endif
