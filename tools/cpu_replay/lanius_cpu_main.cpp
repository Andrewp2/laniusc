// Runs one captured compute dispatch of a Slang kernel on the CPU.
//
// usage: replay PLAN
//
// PLAN is written by tools/cpu_kernel_replay.py, one directive per line:
//   groups X Y Z
//   out DIR
//   break X Y Z            (optional: call lanius_cpu_break() before that
//                           dispatch thread id runs; set a gdb breakpoint on it)
//   slot NAME RW BYTES OUTFILE PATH
// with one `slot` line per kernel parameter in lanius_kernel_slot_names order.
// PATH `-` zero-fills BYTES; OUTFILE `-` skips writing the buffer back.
//
// Workgroups run in order, one at a time. Within a group the invocations run
// in order on one OS thread: directly when the kernel has no group barrier,
// otherwise as fibers (one stack each) that each run up to their next barrier
// before the next one starts, so groupshared memory and barriers behave as on
// the GPU.
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#include <string>
#include <vector>

#include "lanius_cpu_abi.h"

#if !defined(__x86_64__) || !defined(__linux__)
#error "the CPU replay's fiber switch is written for x86-64 Linux"
#endif

// Saves the callee-saved registers, MXCSR and the x87 control word on the
// current stack, stores the stack pointer to *from and resumes the stack `to`
// (a plain function call for the compiler, so everything else is caller-saved).
// ucontext's swapcontext would also make a signal-mask syscall per switch.
extern "C" void lanius_switch(void** from, void* to);
asm(R"(
    .text
    .globl lanius_switch
    .type lanius_switch, @function
lanius_switch:
    .cfi_startproc
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $8, %rsp
    stmxcsr (%rsp)
    fnstcw 4(%rsp)
    movq %rsp, (%rdi)
    movq %rsi, %rsp
    ldmxcsr (%rsp)
    fldcw 4(%rsp)
    addq $8, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    ret
    .cfi_endproc
    .size lanius_switch, .-lanius_switch
)");

// The invocation being run (also after a fiber resumes at a barrier), for
// diagnostics and gdb conditions such as
// `break foo.slang:120 if lanius_cpu_dtid[0] == 4711`.
extern "C" {
uint32_t lanius_cpu_group[3];
uint32_t lanius_cpu_thread[3];
uint32_t lanius_cpu_dtid[3];
uint64_t lanius_cpu_invocation; // linear index in the dispatch

// Called right before the plan's `break` dispatch thread runs.
__attribute__((noinline)) void lanius_cpu_break()
{
    asm volatile("" ::: "memory");
}
}

namespace {

struct Slot
{
    std::string name;
    bool writable = false;
    size_t bytes = 0;
    std::string out_file;
    std::string path;
    char* host = nullptr;
};

[[noreturn]] void die(const char* format, ...)
{
    va_list args;
    va_start(args, format);
    fputs("cpu-replay: ", stderr);
    vfprintf(stderr, format, args);
    fputc('\n', stderr);
    va_end(args);
    exit(2);
}

std::vector<Slot> g_slots;
void* g_globals = nullptr;
uint32_t g_groups[3] = {1, 1, 1};
std::string g_out_dir;
bool g_has_break = false;
uint32_t g_break[3] = {0, 0, 0};

uint64_t g_oob_count = 0;
uint64_t g_divergent_barriers = 0;
uint64_t g_barrier_phases = 0;

// Zeroed memory handed out for out-of-bounds accesses.
alignas(64) char g_oob_scratch[1 << 16];

enum FiberState
{
    FIBER_READY,
    FIBER_WAITING,
    FIBER_DONE,
};

struct Fiber
{
    void* sp = nullptr; // saved stack pointer while switched out
    char* stack = nullptr;
    size_t stack_bytes = 0;
    LaniusThreadInput input;
    FiberState state = FIBER_DONE;
};

void* g_scheduler_sp = nullptr;
Fiber* g_current_fiber = nullptr;

char* allocate_buffer(size_t bytes)
{
    // Round up and pad so element reads near the end stay inside the host copy.
    size_t padded = ((bytes + 63) & ~size_t(63)) + 64;
    void* memory = nullptr;
    if (posix_memalign(&memory, 64, padded) != 0)
        die("out of memory allocating %zu bytes", padded);
    memset(memory, 0, padded);
    return (char*)memory;
}

void read_file(const Slot& slot)
{
    if (slot.path == "-")
        return;
    FILE* file = fopen(slot.path.c_str(), "rb");
    if (!file)
        die("open %s: %s", slot.path.c_str(), strerror(errno));
    size_t got = fread(slot.host, 1, slot.bytes, file);
    fclose(file);
    if (got != slot.bytes)
        die("%s: read %zu of %zu bytes", slot.path.c_str(), got, slot.bytes);
}

void write_file(const Slot& slot)
{
    std::string path = g_out_dir + "/" + slot.out_file;
    FILE* file = fopen(path.c_str(), "wb");
    if (!file)
        die("create %s: %s", path.c_str(), strerror(errno));
    if (fwrite(slot.host, 1, slot.bytes, file) != slot.bytes)
        die("write %s failed", path.c_str());
    fclose(file);
}

void parse_plan(const char* path)
{
    FILE* file = fopen(path, "r");
    if (!file)
        die("open plan %s: %s", path, strerror(errno));
    char line[8192];
    while (fgets(line, sizeof line, file))
    {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r'))
            line[--length] = 0;
        if (!length || line[0] == '#')
            continue;
        char keyword[32];
        int consumed = 0;
        if (sscanf(line, "%31s %n", keyword, &consumed) != 1)
            continue;
        const char* rest = line + consumed;
        if (!strcmp(keyword, "groups"))
        {
            if (sscanf(rest, "%u %u %u", &g_groups[0], &g_groups[1], &g_groups[2]) != 3)
                die("bad plan line: %s", line);
        }
        else if (!strcmp(keyword, "out"))
            g_out_dir = rest;
        else if (!strcmp(keyword, "break"))
        {
            if (sscanf(rest, "%u %u %u", &g_break[0], &g_break[1], &g_break[2]) != 3)
                die("bad plan line: %s", line);
            g_has_break = true;
        }
        else if (!strcmp(keyword, "slot"))
        {
            char name[512], out_file[1024];
            int writable = 0, offset = 0;
            size_t bytes = 0;
            if (sscanf(rest, "%511s %d %zu %1023s %n", name, &writable, &bytes, out_file, &offset) != 4)
                die("bad plan line: %s", line);
            Slot slot;
            slot.name = name;
            slot.writable = writable != 0;
            slot.bytes = bytes;
            slot.out_file = out_file;
            slot.path = rest + offset;
            g_slots.push_back(slot);
        }
        else
            die("unknown plan directive: %s", keyword);
    }
    fclose(file);
}

const char* describe_array(const void* data)
{
    for (const Slot& slot : g_slots)
        if (slot.host == data)
            return slot.name.c_str();
    return nullptr;
}

uint64_t g_invocations = 0;

// Points the lanius_cpu_* globals at the invocation about to run or resume.
void set_current(const LaniusThreadInput& input)
{
    const uint32_t* size = lanius_kernel_numthreads;
    for (int axis = 0; axis < 3; ++axis)
    {
        lanius_cpu_group[axis] = input.group[axis];
        lanius_cpu_thread[axis] = input.thread[axis];
        lanius_cpu_dtid[axis] = input.group[axis] * size[axis] + input.thread[axis];
    }
    uint64_t group = (uint64_t(input.group[2]) * g_groups[1] + input.group[1]) * g_groups[0] + input.group[0];
    uint64_t thread = (uint64_t(input.thread[2]) * size[1] + input.thread[1]) * size[0] + input.thread[0];
    lanius_cpu_invocation = group * (uint64_t(size[0]) * size[1] * size[2]) + thread;
}

void run_invocation(const LaniusThreadInput& input)
{
    set_current(input);
    if (g_has_break && lanius_cpu_dtid[0] == g_break[0] && lanius_cpu_dtid[1] == g_break[1] &&
        lanius_cpu_dtid[2] == g_break[2])
        lanius_cpu_break();
    lanius_kernel_thread(&input, g_globals);
    ++g_invocations;
}

void fiber_entry()
{
    Fiber* fiber = g_current_fiber;
    run_invocation(fiber->input);
    fiber->state = FIBER_DONE;
    lanius_switch(&fiber->sp, g_scheduler_sp);
    die("finished fiber resumed");
}

std::vector<Fiber> g_fibers;

void allocate_fibers(size_t count)
{
    size_t stack_bytes = size_t(8) << 20;
    if (const char* value = getenv("LANIUS_CPU_STACK_MB"))
        stack_bytes = size_t(strtoull(value, nullptr, 10)) << 20;
    long page = 4096;
    g_fibers.resize(count);
    for (Fiber& fiber : g_fibers)
    {
        void* memory = mmap(nullptr, stack_bytes + page, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_STACK, -1, 0);
        if (memory == MAP_FAILED)
            die("mmap fiber stack: %s", strerror(errno));
        // Guard page: a fiber stack overflow faults instead of corrupting memory.
        mprotect(memory, page, PROT_NONE);
        fiber.stack = (char*)memory + page;
        fiber.stack_bytes = stack_bytes;
    }
}

// Lays out a fresh stack the way lanius_switch leaves a switched-out one, so
// the first switch "returns" into fiber_entry.
void prepare_fiber(Fiber& fiber, const LaniusThreadInput& input)
{
    fiber.input = input;
    uintptr_t top = ((uintptr_t)fiber.stack + fiber.stack_bytes) & ~uintptr_t(15);
    uint64_t* slot = (uint64_t*)top;
    *--slot = 0;                        // fake return address of fiber_entry
    *--slot = (uint64_t)&fiber_entry;   // popped by `ret`
    for (int saved = 0; saved < 6; ++saved)
        *--slot = 0;                    // rbp rbx r12 r13 r14 r15
    *--slot = 0x037F00001F80ull;        // default MXCSR, x87 control word
    fiber.sp = slot;
    fiber.state = FIBER_READY;
}

void run_group_fibers(const uint32_t group[3])
{
    const uint32_t* size = lanius_kernel_numthreads;
    size_t index = 0;
    for (uint32_t z = 0; z < size[2]; ++z)
        for (uint32_t y = 0; y < size[1]; ++y)
            for (uint32_t x = 0; x < size[0]; ++x)
                prepare_fiber(g_fibers[index++], {{group[0], group[1], group[2]}, {x, y, z}});
    for (;;)
    {
        // One phase: every live invocation runs to its next barrier or its end.
        for (Fiber& fiber : g_fibers)
        {
            if (fiber.state != FIBER_READY)
                continue;
            g_current_fiber = &fiber;
            set_current(fiber.input);
            lanius_switch(&g_scheduler_sp, fiber.sp);
            g_current_fiber = nullptr;
        }
        size_t waiting = 0, done = 0;
        for (Fiber& fiber : g_fibers)
        {
            waiting += fiber.state == FIBER_WAITING;
            done += fiber.state == FIBER_DONE;
        }
        if (!waiting)
            break;
        ++g_barrier_phases;
        if (done && !g_divergent_barriers++)
            fprintf(stderr,
                "cpu-replay: group (%u,%u,%u): %zu invocations wait at a barrier that %zu finished invocations never reached\n",
                group[0], group[1], group[2], waiting, done);
        for (Fiber& fiber : g_fibers)
            if (fiber.state == FIBER_WAITING)
                fiber.state = FIBER_READY;
    }
}

void run_group_direct(const uint32_t group[3])
{
    const uint32_t* size = lanius_kernel_numthreads;
    for (uint32_t z = 0; z < size[2]; ++z)
        for (uint32_t y = 0; y < size[1]; ++y)
            for (uint32_t x = 0; x < size[0]; ++x)
                run_invocation({{group[0], group[1], group[2]}, {x, y, z}});
}

double now_ms()
{
    timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec * 1e3 + time.tv_nsec / 1e6;
}

} // namespace

extern "C" void lanius_group_barrier()
{
    Fiber* fiber = g_current_fiber;
    if (!fiber)
        die("group barrier outside a fiber (kernel built without barrier support)");
    fiber->state = FIBER_WAITING;
    lanius_switch(&fiber->sp, g_scheduler_sp);
}

extern "C" void* lanius_oob(const void* data, size_t index, size_t count, size_t elem_size, int kind)
{
    static const char* const kinds[] = {"buffer", "local or groupshared array", "byte-address buffer"};
    uint64_t limit = 10;
    if (const char* value = getenv("LANIUS_CPU_OOB_REPORTS"))
        limit = strtoull(value, nullptr, 10);
    if (g_oob_count++ < limit)
    {
        const char* name = describe_array(data);
        fprintf(stderr,
            "cpu-replay: out-of-bounds %s access %s[%zu] (%s %zu) by dispatch thread (%u,%u,%u), group (%u,%u,%u) thread (%u,%u,%u)\n",
            kinds[kind], name ? name : "?", index, kind == 2 ? "size" : "count", count,
            lanius_cpu_dtid[0], lanius_cpu_dtid[1], lanius_cpu_dtid[2], lanius_cpu_group[0],
            lanius_cpu_group[1], lanius_cpu_group[2], lanius_cpu_thread[0], lanius_cpu_thread[1],
            lanius_cpu_thread[2]);
    }
    if (elem_size > sizeof g_oob_scratch)
        die("out-of-bounds element of %zu bytes is larger than the scratch", elem_size);
    memset(g_oob_scratch, 0, elem_size);
    return g_oob_scratch;
}

int main(int argc, char** argv)
{
    if (argc != 2)
        die("usage: %s PLAN", argv[0]);
    parse_plan(argv[1]);
    if (g_slots.size() != lanius_kernel_slot_count)
        die("plan has %zu slots, kernel wants %u", g_slots.size(), lanius_kernel_slot_count);
    std::vector<LaniusSlot> slots;
    for (size_t index = 0; index < g_slots.size(); ++index)
    {
        Slot& slot = g_slots[index];
        if (slot.name != lanius_kernel_slot_names[index])
            die("plan slot %zu is %s, kernel wants %s", index, slot.name.c_str(), lanius_kernel_slot_names[index]);
        slot.host = allocate_buffer(slot.bytes);
        read_file(slot);
        slots.push_back({slot.host, slot.bytes, slot.name.c_str()});
    }
    g_globals = lanius_kernel_bind(slots.data());

    size_t group_size = size_t(lanius_kernel_numthreads[0]) * lanius_kernel_numthreads[1] * lanius_kernel_numthreads[2];
    if (lanius_kernel_uses_barriers)
        allocate_fibers(group_size);
    double started = now_ms();
    uint32_t group[3];
    for (group[2] = 0; group[2] < g_groups[2]; ++group[2])
        for (group[1] = 0; group[1] < g_groups[1]; ++group[1])
            for (group[0] = 0; group[0] < g_groups[0]; ++group[0])
            {
                if (lanius_kernel_uses_barriers)
                    run_group_fibers(group);
                else
                    run_group_direct(group);
            }
    double elapsed = now_ms() - started;

    if (!g_out_dir.empty())
        for (const Slot& slot : g_slots)
            if (slot.out_file != "-")
                write_file(slot);
    printf("{\"invocations\": %llu, \"groups\": [%u, %u, %u], \"numthreads\": [%u, %u, %u], "
           "\"fibers\": %s, \"barrier_phases\": %llu, \"divergent_barriers\": %llu, "
           "\"out_of_bounds\": %llu, \"elapsed_ms\": %.3f}\n",
        (unsigned long long)g_invocations, g_groups[0], g_groups[1], g_groups[2],
        lanius_kernel_numthreads[0], lanius_kernel_numthreads[1], lanius_kernel_numthreads[2],
        lanius_kernel_uses_barriers ? "true" : "false", (unsigned long long)g_barrier_phases,
        (unsigned long long)g_divergent_barriers, (unsigned long long)g_oob_count, elapsed);
    return 0;
}
