// C++ side of the CPU kernel replay (see docs/cpu-kernel-replay.md).
//
// Included before the Slang-generated kernel source. It provides the functions
// lanius_cpu_shim.slang emits calls to (atomics, barriers) and replaces the
// Slang prelude's bounds checks, which assert or read wild memory, with ones
// that report the access and behave like Vulkan robust buffer access: an
// out-of-bounds read returns zero and an out-of-bounds write is dropped.
//
// Invocations run one at a time on one OS thread (barrier kernels as fibers),
// so the atomics are plain read-modify-writes.
#ifndef LANIUS_CPU_RUNTIME_H
#define LANIUS_CPU_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

extern "C" {
// Yields the current invocation until every live invocation of its group
// reached a barrier (lanius_cpu_main.cpp).
void lanius_group_barrier();
// Records an out-of-bounds access of element `index` of the `count`-element
// array at `data` and returns zeroed scratch memory of `elem_size` bytes.
void* lanius_oob(const void* data, size_t index, size_t count, size_t elem_size, int kind);
}

inline void lanius_memory_barrier() {}

template<typename T>
struct lanius_same
{
    typedef T type;
};

#define LANIUS_ATOMIC_RMW(NAME, EXPR)                                                    \
    template<typename T>                                                                 \
    inline void NAME(T* dest, typename lanius_same<T>::type value, T* original)          \
    {                                                                                    \
        T old = *dest;                                                                   \
        *dest = (EXPR);                                                                  \
        if (original)                                                                    \
            *original = old;                                                             \
    }                                                                                    \
    template<typename T>                                                                 \
    inline void NAME(T* dest, typename lanius_same<T>::type value, decltype(nullptr))    \
    {                                                                                    \
        T* none = nullptr;                                                               \
        NAME(dest, value, none);                                                         \
    }

LANIUS_ATOMIC_RMW(lanius_atomic_add, T(old + value))
LANIUS_ATOMIC_RMW(lanius_atomic_and, T(old & value))
LANIUS_ATOMIC_RMW(lanius_atomic_or, T(old | value))
LANIUS_ATOMIC_RMW(lanius_atomic_xor, T(old ^ value))
LANIUS_ATOMIC_RMW(lanius_atomic_min, (value < old ? value : old))
LANIUS_ATOMIC_RMW(lanius_atomic_max, (value > old ? value : old))
LANIUS_ATOMIC_RMW(lanius_atomic_exchange, value)

template<typename T>
inline void lanius_atomic_compare_exchange(
    T* dest,
    typename lanius_same<T>::type compare,
    typename lanius_same<T>::type value,
    T* original)
{
    T old = *dest;
    if (old == compare)
        *dest = value;
    if (original)
        *original = old;
}

template<typename T>
inline void lanius_atomic_compare_exchange(
    T* dest,
    typename lanius_same<T>::type compare,
    typename lanius_same<T>::type value,
    decltype(nullptr))
{
    T* none = nullptr;
    lanius_atomic_compare_exchange(dest, compare, value, none);
}

// Bounds checks used by the prelude's buffer and array types. Every user has
// members `data`/`m_data` and element type `T`.
#define SLANG_BOUND_CHECK(index, count)                                                    \
    if (!((index) < (count)))                                                              \
        return *(T*)lanius_oob((const void*)data, (size_t)(index), (size_t)(count), sizeof(T), 0);

#define SLANG_BOUND_CHECK_FIXED_ARRAY(index, count)                                        \
    if (!((index) < (count)))                                                              \
        return *(T*)lanius_oob((const void*)m_data, (size_t)(index), (size_t)(count), sizeof(T), 1);

// Byte-address loads and stores return by value, so redirect the access to the
// zeroed scratch instead (`data + index` then points at it).
#define SLANG_BOUND_CHECK_BYTE_ADDRESS(index, elemSize, sizeInBytes)                       \
    if (!((sizeInBytes) >= (elemSize) && (index) <= (sizeInBytes) - (elemSize)))           \
        index = (size_t)((const char*)lanius_oob((const void*)data, (size_t)(index), (size_t)(sizeInBytes), (elemSize), 2) - (const char*)data);

#endif
