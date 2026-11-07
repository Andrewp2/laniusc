/* Test-only exact-address failure of the par crew's committed wake syscall. */
#include <errno.h>
#include <linux/filter.h>
#include <linux/futex.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

static _Atomic(uintptr_t) observed_argument;
void par_probe_record_arg(void *argument) { atomic_store(&observed_argument, (uintptr_t)argument); }
void *par_probe_argument(void) { return (void *)atomic_load(&observed_argument); }

static int deny(void *address, unsigned operation) {
    uintptr_t value = (uintptr_t)address;
    struct sock_filter code[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_futex, 0, 7),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[0])),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (uint32_t)value, 0, 5),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[0]) + 4),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (uint32_t)(value >> 32), 0, 3),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[1])),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, operation, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EIO),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = { .len = sizeof(code) / sizeof(code[0]), .filter = code };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) return errno;
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program)) return errno;
    return 0;
}
int par_probe_deny_wake(void *address) { return deny(address, FUTEX_WAKE); }
int par_probe_deny_wait(void *address) { return deny(address, FUTEX_WAIT); }
