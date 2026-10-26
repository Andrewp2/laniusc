/* Test-only observer ABI. All session state is keyed by the real SSL*. */
#ifndef LANIUS_TLS_DUPLEX_OBSERVER_H
#define LANIUS_TLS_DUPLEX_OBSERVER_H
#include <stdint.h>
/* One-shot controls: 1 write/WANT_READ, 2 read/WANT_WRITE, 3 read/fatal,
 * 4 write/fatal, 5 shutdown/WANT_READ, 6 shutdown/WANT_WRITE,
 * 7 shutdown/fatal, 8 handshake/fatal, 9 read/WANT_READ. No positive result
 * or byte count is manufactured. Real retry calls always reach OpenSSL. */
void duplex_test_arm(int session_ordinal, int fault);
/* One future SSL_new only; the fault becomes owned by that SSL immediately. */
void duplex_test_arm_next(int fault);
void duplex_test_fail_up_ref(void);
void duplex_test_forget_read(int session_ordinal);
/* Optional raw-fixture assertion: callers notify confirmed quiesce via the
 * forget hook. Leave disabled when an adapter quiesces internally. */
void duplex_test_strict_reads(int session_ordinal, int enabled);
int duplex_test_pending(int session_ordinal);
int duplex_test_fd_open(int fd);
/* Global index -1: external context refs, live SSL owners, invalid frees,
 * I/O leaves, external up_ref calls, failed up_refs, shutdown leaves.
 * Session fields: reads,writes,shutdowns,handshakes,get_error,forced hits,
 * checked stable write retries,checked stable read retries,distinct count
 * cells observed,live,real write/WANT_WRITE results. */
int64_t duplex_test_stat(int session_ordinal, int field);
#endif
