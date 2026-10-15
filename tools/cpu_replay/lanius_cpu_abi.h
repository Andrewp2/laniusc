// Interface between lanius_cpu_main.cpp and one generated kernel translation
// unit (see tools/cpu_kernel_replay.py).
#ifndef LANIUS_CPU_ABI_H
#define LANIUS_CPU_ABI_H

#include <stddef.h>
#include <stdint.h>

// One captured buffer: host copy of the bound range.
struct LaniusSlot
{
    void* data;
    size_t bytes;
    const char* name;
};

// Layout of the prelude's ComputeThreadVaryingInput.
struct LaniusThreadInput
{
    uint32_t group[3];
    uint32_t thread[3];
};

extern "C" {
// Defined by the generated kernel unit.
extern const uint32_t lanius_kernel_numthreads[3];
extern const int lanius_kernel_uses_barriers;
extern const uint32_t lanius_kernel_slot_count;
extern const char* const lanius_kernel_slot_names[];
// Fills the kernel's GlobalParams from `slots` (in lanius_kernel_slot_names
// order) and returns it.
void* lanius_kernel_bind(const LaniusSlot* slots);
// Runs one invocation.
void lanius_kernel_thread(const LaniusThreadInput* input, void* globals);
}

#endif
