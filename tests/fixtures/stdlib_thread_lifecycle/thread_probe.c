/* Test-only observation/fault interposition around real glibc pthreads.
 * Link this object into the emitted test executable; never ship it in stdlib.
 * Configuration/getters are called by the main test thread. Worker gates use
 * futex conditions, not scheduler sleeps. A failed join never calls real join.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

_Static_assert(sizeof(pthread_t) == sizeof(uint64_t), "Linux x86_64 pthread identity");
enum { INIT=1, SETSTACK=2, CREATE=3, DESTROY=4, JOIN=5, KINDS=6, MAX_THREADS=256, MAX_EVENTS=2048 };
struct slot {
    void *(*entry)(void *);
    void *argument;
    pthread_t id;
    _Atomic int gate, ready, entered, exited;
    int started, joined;
};
struct event { int kind, ordinal, result; uint64_t id; };
static struct slot slots[MAX_THREADS];
static int successful_slots[MAX_THREADS], successful_count, joined_count;
static int counts[KINDS], fault_at[KINDS], fault_code[KINDS];
static uint64_t attempted_joins[MAX_EVENTS];
static struct event events[MAX_EVENTS];
static int event_count;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static const char *names[KINDS] = { "invalid", "init", "setstack", "create", "destroy", "join" };

/* Application fixtures configure the same named faults without adding test
 * calls to production Lanius programs. The form is ORDINAL:POSITIVE_ERRNO. */
__attribute__((constructor)) static void environment_faults(void) {
    static const char *variables[KINDS] = { NULL, "LANIUS_THREAD_PROBE_FAIL_INIT", "LANIUS_THREAD_PROBE_FAIL_SETSTACK", "LANIUS_THREAD_PROBE_FAIL_CREATE", "LANIUS_THREAD_PROBE_FAIL_DESTROY", "LANIUS_THREAD_PROBE_FAIL_JOIN" };
    for (int kind = 1; kind < KINDS; ++kind) {
        const char *value = getenv(variables[kind]);
        if (!value) continue;
        char *end;
        errno = 0;
        long ordinal = strtol(value, &end, 10);
        if (errno || end == value || *end != ':' || ordinal <= 0 || ordinal > MAX_EVENTS) _exit(198);
        const char *error_text = end+1;
        errno = 0;
        long error = strtol(error_text, &end, 10);
        if (errno || end == error_text || *end || error <= 0 || error > 4095) _exit(198);
        fault_at[kind] = (int)ordinal; fault_code[kind] = (int)error;
    }
}

static void *symbol(const char *name) {
    void *answer = dlsym(RTLD_NEXT, name);
    if (!answer) _exit(191);
    return answer;
}
static int begin(int kind, int *ordinal) {
    pthread_mutex_lock(&lock);
    *ordinal = ++counts[kind];
    int result = *ordinal == fault_at[kind] ? fault_code[kind] : 0;
    pthread_mutex_unlock(&lock);
    return result;
}
static void record(int kind, int ordinal, int result, uint64_t id) {
    pthread_mutex_lock(&lock);
    if (event_count == MAX_EVENTS) _exit(192);
    events[event_count++] = (struct event){ kind, ordinal, result, id };
    pthread_mutex_unlock(&lock);
    const char *trace = getenv("LANIUS_THREAD_PROBE_TRACE");
    if (trace && !strcmp(trace, "1")) {
        char line[160];
        int length = snprintf(line, sizeof(line), "thread-probe %s %d %d %llu\n", names[kind], ordinal, result, (unsigned long long)id);
        if (length <= 0 || length >= (int)sizeof(line) || syscall(SYS_write, 2, line, (size_t)length) != length) _exit(193);
    }
}
int thread_probe_reset(void) {
    pthread_mutex_lock(&lock);
    if (successful_count != joined_count) { pthread_mutex_unlock(&lock); return EBUSY; }
    memset(slots, 0, sizeof(slots));
    memset(successful_slots, 0, sizeof(successful_slots));
    memset(counts, 0, sizeof(counts));
    memset(fault_at, 0, sizeof(fault_at));
    memset(fault_code, 0, sizeof(fault_code));
    memset(attempted_joins, 0, sizeof(attempted_joins));
    memset(events, 0, sizeof(events));
    successful_count = joined_count = event_count = 0;
    pthread_mutex_unlock(&lock);
    return 0;
}
int thread_probe_fail(int kind, int ordinal, int error) {
    if (kind <= 0 || kind >= KINDS || ordinal < 0 || error < 0 || ((ordinal == 0) != (error == 0))) return EINVAL;
    pthread_mutex_lock(&lock);
    if (ordinal && ordinal <= counts[kind]) { pthread_mutex_unlock(&lock); return EINVAL; }
    fault_at[kind] = ordinal; fault_code[kind] = error;
    pthread_mutex_unlock(&lock);
    return 0;
}
int thread_probe_calls(int kind) { return kind > 0 && kind < KINDS ? counts[kind] : -1; }
int thread_probe_created(void) { return successful_count; }
int thread_probe_joined(void) { return joined_count; }
int thread_probe_live(void) { return successful_count - joined_count; }
uint64_t thread_probe_created_id(int index) {
    return index >= 0 && index < successful_count ? (uint64_t)slots[successful_slots[index]].id : 0;
}
uint64_t thread_probe_join_attempt(int index) {
    return index >= 0 && index < counts[JOIN] && index < MAX_EVENTS ? attempted_joins[index] : 0;
}
int thread_probe_event_count(void) { return event_count; }
int thread_probe_phase(int phase) {
    const char *trace = getenv("LANIUS_THREAD_PROBE_TRACE");
    if (trace && !strcmp(trace, "1")) {
        char line[192];
        int length = snprintf(line, sizeof(line), "thread-phase %d calls=%d,%d,%d,%d,%d owners=%d,%d events=%d\n", phase,
                              counts[INIT], counts[SETSTACK], counts[CREATE], counts[DESTROY], counts[JOIN], successful_count, joined_count, event_count);
        if (length <= 0 || length >= (int)sizeof(line) || syscall(SYS_write, 2, line, (size_t)length) != length) _exit(199);
    }
    return 0;
}
int thread_probe_event_kind(int index) { return index >= 0 && index < event_count ? events[index].kind : -1; }
int thread_probe_event_ordinal(int index) { return index >= 0 && index < event_count ? events[index].ordinal : -1; }
int thread_probe_event_result(int index) { return index >= 0 && index < event_count ? events[index].result : -1; }
uint64_t thread_probe_event_id(int index) { return index >= 0 && index < event_count ? events[index].id : 0; }
int thread_probe_hold_create(int ordinal) {
    if (ordinal <= 0 || ordinal > MAX_THREADS || ordinal <= counts[CREATE]) return EINVAL;
    atomic_store_explicit(&slots[ordinal-1].gate, 1, memory_order_release);
    return 0;
}
int thread_probe_release(int ordinal) {
    if (ordinal <= 0 || ordinal > MAX_THREADS || !slots[ordinal-1].started) return EINVAL;
    atomic_store_explicit(&slots[ordinal-1].gate, 0, memory_order_release);
    syscall(SYS_futex, &slots[ordinal-1].gate, FUTEX_WAKE_PRIVATE, INT_MAX, NULL, NULL, 0);
    return 0;
}
int thread_probe_entered(int ordinal) {
    return ordinal > 0 && ordinal <= MAX_THREADS ? atomic_load_explicit(&slots[ordinal-1].entered, memory_order_acquire) : -1;
}
int thread_probe_exited(int ordinal) {
    return ordinal > 0 && ordinal <= MAX_THREADS ? atomic_load_explicit(&slots[ordinal-1].exited, memory_order_acquire) : -1;
}
uint64_t thread_probe_stack_size(void) {
    pthread_attr_t attribute;
    int (*get)(pthread_t, pthread_attr_t *) = symbol("pthread_getattr_np");
    int (*size)(const pthread_attr_t *, size_t *) = symbol("pthread_attr_getstacksize");
    int (*destroy)(pthread_attr_t *) = symbol("pthread_attr_destroy");
    size_t bytes = 0;
    if (get(pthread_self(), &attribute)) return 0;
    int result = size(&attribute, &bytes);
    if (destroy(&attribute) || result) return 0;
    return (uint64_t)bytes;
}
int thread_probe_wait_ready(int ordinal) {
    if (ordinal <= 0 || ordinal > MAX_THREADS || !slots[ordinal-1].started) return EINVAL;
    struct slot *slot = &slots[ordinal-1];
    struct timespec deadline;
    if (clock_gettime(CLOCK_MONOTONIC, &deadline)) return errno;
    deadline.tv_sec += 3;
    while (!atomic_load_explicit(&slot->ready, memory_order_acquire)) {
        long result = syscall(SYS_futex, &slot->ready, FUTEX_WAIT_BITSET_PRIVATE, 0, &deadline, NULL, FUTEX_BITSET_MATCH_ANY);
        if (result < 0 && errno != EAGAIN && errno != EINTR) return errno;
    }
    return 0;
}
static void *trampoline(void *argument) {
    struct slot *slot = argument;
    atomic_store_explicit(&slot->ready, 1, memory_order_release);
    syscall(SYS_futex, &slot->ready, FUTEX_WAKE_PRIVATE, INT_MAX, NULL, NULL, 0);
    while (atomic_load_explicit(&slot->gate, memory_order_acquire)) {
        long result = syscall(SYS_futex, &slot->gate, FUTEX_WAIT_PRIVATE, 1, NULL, NULL, 0);
        if (result < 0 && errno != EAGAIN && errno != EINTR) _exit(194);
    }
    atomic_store_explicit(&slot->entered, 1, memory_order_release);
    void *answer = slot->entry(slot->argument);
    atomic_store_explicit(&slot->exited, 1, memory_order_release);
    return answer;
}
int pthread_attr_init(pthread_attr_t *attribute) {
    int ordinal, result = begin(INIT, &ordinal);
    if (!result) { int (*real)(pthread_attr_t *) = symbol("pthread_attr_init"); result = real(attribute); }
    record(INIT, ordinal, result, 0); return result;
}
int pthread_attr_setstacksize(pthread_attr_t *attribute, size_t bytes) {
    int ordinal, result = begin(SETSTACK, &ordinal);
    if (!result) { int (*real)(pthread_attr_t *, size_t) = symbol("pthread_attr_setstacksize"); result = real(attribute, bytes); }
    record(SETSTACK, ordinal, result, 0); return result;
}
int pthread_attr_destroy(pthread_attr_t *attribute) {
    int ordinal, injected = begin(DESTROY, &ordinal);
    int (*real)(pthread_attr_t *) = symbol("pthread_attr_destroy");
    int result = real(attribute);
    if (!result && injected) result = injected;
    record(DESTROY, ordinal, result, 0); return result;
}
int pthread_create(pthread_t *id, const pthread_attr_t *attribute, void *(*entry)(void *), void *argument) {
    int ordinal, result = begin(CREATE, &ordinal);
    if (ordinal > MAX_THREADS) _exit(195);
    struct slot *slot = &slots[ordinal-1];
    if (!result) {
        slot->entry = entry; slot->argument = argument;
        int (*real)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *) = symbol("pthread_create");
        result = real(id, attribute, trampoline, slot);
        if (!result) {
            slot->id = *id; slot->started = 1;
            successful_slots[successful_count++] = ordinal-1;
        }
    }
    record(CREATE, ordinal, result, result ? 0 : (uint64_t)*id); return result;
}
int pthread_join(pthread_t id, void **answer) {
    int ordinal, result = begin(JOIN, &ordinal);
    if (ordinal > MAX_EVENTS) _exit(196);
    attempted_joins[ordinal-1] = (uint64_t)id;
    if (!result) {
        int (*real)(pthread_t, void **) = symbol("pthread_join");
        result = real(id, answer);
        if (!result) {
            int found = 0;
            for (int index = 0; index < successful_count; ++index) {
                struct slot *slot = &slots[successful_slots[index]];
                if (slot->id == id && !slot->joined) { slot->joined = 1; ++joined_count; found = 1; break; }
            }
            if (!found) _exit(197);
        }
    }
    record(JOIN, ordinal, result, (uint64_t)id); return result;
}
