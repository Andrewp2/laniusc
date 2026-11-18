// Indirect dispatch arguments for a scan total, written by workgroup 0 of a
// scan apply. Same arithmetic as type_checker/count/dispatch_args: the
// total, clamped to the capacity and multiplied, in 256-lane workgroups,
// split over y beyond 65535 groups.

import uint_math;

public struct ScanTotalDispatchParams
{
    public uint capacity;
    public uint multiplier;
    public uint reserved0;
    public uint reserved1;
};

public void write_scan_total_dispatch(
    uint total, ScanTotalDispatchParams params, RWStructuredBuffer<uint> dispatch_args)
{
    uint count = saturating_mul_u32(min(total, params.capacity), max(params.multiplier, 1u));
    uint groups = max(1u, ceil_div_u32(count, 256u));
    dispatch_args[0u] = min(groups, 65535u);
    dispatch_args[1u] = max(1u, ceil_div_u32(groups, 65535u));
    dispatch_args[2u] = 1u;
}
