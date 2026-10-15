// Binds captured buffers to the Slang-generated GlobalParams struct. Included
// after the generated kernel source (it needs the prelude's buffer types);
// tools/cpu_kernel_replay.py appends one lanius_bind_slot call per parameter.
#ifndef LANIUS_CPU_BINDER_H
#define LANIUS_CPU_BINDER_H

#include <stdio.h>

#include "lanius_cpu_abi.h"

static_assert(sizeof(ComputeThreadVaryingInput) == sizeof(LaniusThreadInput), "thread input ABI");

inline void lanius_check_stride(const LaniusSlot& slot, size_t stride)
{
    if (stride != 0 && slot.bytes % stride != 0)
        fprintf(stderr, "cpu-replay: %s: %zu bytes is not a multiple of the %zu-byte element\n",
            slot.name, slot.bytes, stride);
}

// ConstantBuffer<T> is a T*.
template<typename T>
inline void lanius_bind_slot(T*& value, const LaniusSlot& slot)
{
    if (slot.bytes < sizeof(T))
        fprintf(stderr, "cpu-replay: %s: %zu captured bytes for a %zu-byte constant buffer (rest reads zero)\n",
            slot.name, slot.bytes, sizeof(T));
    value = (T*)slot.data;
}

#define LANIUS_BIND_ELEMENTS(TYPE)                                       \
    template<typename T>                                                 \
    inline void lanius_bind_slot(TYPE<T>& value, const LaniusSlot& slot) \
    {                                                                    \
        lanius_check_stride(slot, sizeof(T));                            \
        value.data = (T*)slot.data;                                      \
        value.count = slot.bytes / sizeof(T);                            \
    }
LANIUS_BIND_ELEMENTS(StructuredBuffer)
LANIUS_BIND_ELEMENTS(RWStructuredBuffer)
LANIUS_BIND_ELEMENTS(Buffer)
LANIUS_BIND_ELEMENTS(RWBuffer)

inline void lanius_bind_slot(ByteAddressBuffer& value, const LaniusSlot& slot)
{
    value.data = (const uint32_t*)slot.data;
    value.sizeInBytes = slot.bytes & ~size_t(3);
}

inline void lanius_bind_slot(RWByteAddressBuffer& value, const LaniusSlot& slot)
{
    value.data = (uint32_t*)slot.data;
    value.sizeInBytes = slot.bytes & ~size_t(3);
}

#endif
