// CPU replay stand-ins for the HLSL intrinsics Slang's C++ backend cannot emit
// (atomics other than add, group barriers). tools/cpu_kernel_replay.py imports
// this module into every shader of its mirror tree and renames the intrinsics
// to these functions with -D, so the shader sources stay unchanged. The C++
// side lives in lanius_cpu_runtime.h. CPU replay only; never in a GPU build.
//
// `__ref` and `out` parameters arrive in the C++ as pointers.

// ---- uint ----
public void lanius_cpu_InterlockedAdd(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_add($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedAdd(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_add($0, $1, $2)";
}
public void lanius_cpu_InterlockedAnd(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_and($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedAnd(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_and($0, $1, $2)";
}
public void lanius_cpu_InterlockedOr(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_or($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedOr(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_or($0, $1, $2)";
}
public void lanius_cpu_InterlockedXor(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_xor($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedXor(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_xor($0, $1, $2)";
}
public void lanius_cpu_InterlockedMin(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_min($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedMin(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_min($0, $1, $2)";
}
public void lanius_cpu_InterlockedMax(__ref uint dest, uint value)
{
    __intrinsic_asm "lanius_atomic_max($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedMax(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_max($0, $1, $2)";
}
public void lanius_cpu_InterlockedExchange(__ref uint dest, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_exchange($0, $1, $2)";
}
public void lanius_cpu_InterlockedCompareExchange(__ref uint dest, uint compare, uint value, out uint original)
{
    __intrinsic_asm "lanius_atomic_compare_exchange($0, $1, $2, $3)";
}
public void lanius_cpu_InterlockedCompareStore(__ref uint dest, uint compare, uint value)
{
    __intrinsic_asm "lanius_atomic_compare_exchange($0, $1, $2, nullptr)";
}
// ---- int ----
public void lanius_cpu_InterlockedAdd(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_add($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedAdd(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_add($0, $1, $2)";
}
public void lanius_cpu_InterlockedAnd(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_and($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedAnd(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_and($0, $1, $2)";
}
public void lanius_cpu_InterlockedOr(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_or($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedOr(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_or($0, $1, $2)";
}
public void lanius_cpu_InterlockedXor(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_xor($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedXor(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_xor($0, $1, $2)";
}
public void lanius_cpu_InterlockedMin(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_min($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedMin(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_min($0, $1, $2)";
}
public void lanius_cpu_InterlockedMax(__ref int dest, int value)
{
    __intrinsic_asm "lanius_atomic_max($0, $1, nullptr)";
}
public void lanius_cpu_InterlockedMax(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_max($0, $1, $2)";
}
public void lanius_cpu_InterlockedExchange(__ref int dest, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_exchange($0, $1, $2)";
}
public void lanius_cpu_InterlockedCompareExchange(__ref int dest, int compare, int value, out int original)
{
    __intrinsic_asm "lanius_atomic_compare_exchange($0, $1, $2, $3)";
}
public void lanius_cpu_InterlockedCompareStore(__ref int dest, int compare, int value)
{
    __intrinsic_asm "lanius_atomic_compare_exchange($0, $1, $2, nullptr)";
}
// ---- barriers ----
public void lanius_cpu_GroupMemoryBarrierWithGroupSync()
{
    __intrinsic_asm "lanius_group_barrier()";
}
public void lanius_cpu_DeviceMemoryBarrierWithGroupSync()
{
    __intrinsic_asm "lanius_group_barrier()";
}
public void lanius_cpu_AllMemoryBarrierWithGroupSync()
{
    __intrinsic_asm "lanius_group_barrier()";
}
public void lanius_cpu_GroupMemoryBarrier()
{
    __intrinsic_asm "lanius_memory_barrier()";
}
public void lanius_cpu_DeviceMemoryBarrier()
{
    __intrinsic_asm "lanius_memory_barrier()";
}
public void lanius_cpu_AllMemoryBarrier()
{
    __intrinsic_asm "lanius_memory_barrier()";
}
