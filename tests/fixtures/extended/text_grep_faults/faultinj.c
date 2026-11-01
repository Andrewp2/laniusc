// Syscall fault injector built on seccomp user notification (no ptrace).
//
//   faultinj REPORT SYSCALL WHEN ACTION -- PROGRAM ARGS...
//
// SYSCALL is mmap, read, write or none. On the WHEN-th call (1-based, counted
// over every call of that syscall, like strace's inject=...:when=N) the call is
// not executed: ACTION "eN" returns -N (an errno), "rK" returns K. Every other
// trapped call continues unchanged. REPORT receives the counts of mmap, munmap,
// read and write calls, the requested length of each write to fd 1, whether
// the fault was injected, and the /proc/PID/maps lines that differ between the
// first trapped call and exit. A mapping that was created and never released
// shows up there. The exit status is the program's (128+signal if killed).
#define _GNU_SOURCE
#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAPS 65536

static int read_maps(int pid, char *out) {
    char path[64];
    snprintf(path, sizeof path, "/proc/%d/maps", pid);
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    size_t n = fread(out, 1, MAPS - 1, f);
    out[n] = 0;
    fclose(f);
    return 0;
}

// Lines of a that are absent from b, ignoring the stack (it grows).
static int missing(FILE *r, const char *tag, const char *a, const char *b) {
    int count = 0;
    const char *p = a;
    while (*p) {
        const char *e = strchr(p, '\n');
        size_t len = e ? (size_t)(e - p) : strlen(p);
        if (!memmem(p, len, "[stack]", 7)) {
            int found = 0;
            const char *q = b;
            while (*q) {
                const char *f = strchr(q, '\n');
                size_t l = f ? (size_t)(f - q) : strlen(q);
                if (l == len && memcmp(p, q, len) == 0) { found = 1; break; }
                q = f ? f + 1 : q + l;
            }
            if (!found) { fprintf(r, "%s %.*s\n", tag, (int)len, p); count++; }
        }
        p = e ? e + 1 : p + len;
    }
    return count;
}

int main(int argc, char **argv) {
    if (argc < 7 || strcmp(argv[5], "--") != 0) {
        fprintf(stderr, "usage: faultinj REPORT SYSCALL WHEN ACTION -- PROGRAM ARGS...\n");
        return 125;
    }
    long target = -1;
    if (!strcmp(argv[2], "mmap")) target = SYS_mmap;
    else if (!strcmp(argv[2], "read")) target = SYS_read;
    else if (!strcmp(argv[2], "write")) target = SYS_write;
    else if (strcmp(argv[2], "none")) { fprintf(stderr, "faultinj: bad syscall\n"); return 125; }
    long when = atol(argv[3]);
    int is_error = argv[4][0] == 'e';
    long value = atol(argv[4] + 1);

    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv)) { perror("socketpair"); return 125; }
    pid_t child = fork();
    if (child == 0) {
        close(sv[0]);
        struct sock_filter code[] = {
            BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
            BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_mmap, 6, 0),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_munmap, 5, 0),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_read, 4, 0),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_write, 3, 0),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_exit, 2, 0),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_exit_group, 1, 0),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_USER_NOTIF),
        };
        struct sock_fprog prog = {sizeof code / sizeof code[0], code};
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) _exit(125);
        int fd = syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_NEW_LISTENER, &prog);
        if (fd < 0) _exit(125);
        char byte = 0;
        struct iovec iov = {&byte, 1};
        char control[CMSG_SPACE(sizeof(int))];
        struct msghdr msg = {0};
        msg.msg_iov = &iov;
        msg.msg_iovlen = 1;
        msg.msg_control = control;
        msg.msg_controllen = sizeof control;
        struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
        c->cmsg_level = SOL_SOCKET;
        c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &fd, sizeof fd);
        if (sendmsg(sv[1], &msg, 0) != 1) _exit(125);
        close(fd);
        close(sv[1]);
        execvp(argv[6], argv + 6);
        _exit(127);
    }
    close(sv[1]);
    char byte;
    struct iovec iov = {&byte, 1};
    char control[CMSG_SPACE(sizeof(int))];
    struct msghdr msg = {0};
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control;
    msg.msg_controllen = sizeof control;
    if (recvmsg(sv[0], &msg, 0) != 1) { fprintf(stderr, "faultinj: no listener\n"); return 125; }
    int fd;
    memcpy(&fd, CMSG_DATA(CMSG_FIRSTHDR(&msg)), sizeof fd);

    struct seccomp_notif_sizes sizes;
    syscall(SYS_seccomp, SECCOMP_GET_NOTIF_SIZES, 0, &sizes);
    struct seccomp_notif *req = calloc(1, sizes.seccomp_notif > sizeof *req ? sizes.seccomp_notif : sizeof *req);
    struct seccomp_notif_resp *resp = calloc(1, sizes.seccomp_notif_resp > sizeof *resp ? sizes.seccomp_notif_resp : sizeof *resp);
    static char before[MAPS], after[MAPS];
    int have_before = 0, have_after = 0, injected = 0;
    long counts[4] = {0, 0, 0, 0}, target_count = 0;
    FILE *r = fopen(argv[1], "w");
    if (!r) { perror("report"); return 125; }
    char writes[65536];
    size_t writes_len = 0;
    writes[0] = 0;
    for (;;) {
        struct pollfd p = {fd, POLLIN, 0};
        if (poll(&p, 1, -1) < 0) { if (errno == EINTR) continue; break; }
        if (p.revents & POLLHUP) break;
        if (!(p.revents & POLLIN)) continue;
        memset(req, 0, sizes.seccomp_notif);
        if (ioctl(fd, SECCOMP_IOCTL_NOTIF_RECV, req)) { if (errno == EINTR || errno == ENOENT) continue; break; }
        long nr = req->data.nr;
        if (!have_before) have_before = read_maps(req->pid, before) == 0;
        memset(resp, 0, sizes.seccomp_notif_resp);
        resp->id = req->id;
        resp->flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE;
        if (nr == SYS_mmap) counts[0]++;
        else if (nr == SYS_munmap) counts[1]++;
        else if (nr == SYS_read) counts[2]++;
        else if (nr == SYS_write) {
            counts[3]++;
            if (req->data.args[0] == 1 && writes_len < sizeof writes - 32)
                writes_len += snprintf(writes + writes_len, sizeof writes - writes_len, " %llu",
                                       (unsigned long long)req->data.args[2]);
        } else if (nr == SYS_exit || nr == SYS_exit_group) {
            have_after = read_maps(req->pid, after) == 0;
        }
        if (nr == target && ++target_count == when) {
            resp->flags = 0;
            resp->error = is_error ? -value : 0;
            resp->val = is_error ? 0 : value;
            injected = 1;
        }
        ioctl(fd, SECCOMP_IOCTL_NOTIF_SEND, resp);
    }
    int status = 0;
    waitpid(child, &status, 0);
    fprintf(r, "mmap %ld\nmunmap %ld\nread %ld\nwrite %ld\nstdout_writes%s\ninjected %d\n",
            counts[0], counts[1], counts[2], counts[3], writes, injected);
    int leaks = -1;
    if (have_before && have_after) leaks = missing(r, "added", after, before) + missing(r, "removed", before, after);
    fprintf(r, "maps_changed %d\n", leaks);
    fclose(r);
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return 128 + WTERMSIG(status);
}
