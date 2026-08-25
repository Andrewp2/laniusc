// Canonical lookup over physically ordered sparse SSA block-entry demands.

import codegen.optimization_ir;

StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;

static const uint INVALID = 0xffffffffu;

bool canonical_ssa_demand_less(
    OptIrSsaDemand left,
    OptIrSsaDemand right)
{
    return left.declaration < right.declaration ||
        (left.declaration == right.declaration && left.block < right.block);
}

public uint opt_ir_active_ssa_demand_total(uint capacity)
{
    return min(opt_ir_ssa_demand_total[0u], capacity);
}

public OptIrSsaDemand opt_ir_canonical_ssa_demand(
    uint dense_row,
    uint total)
{
    OptIrSsaDemand invalid;
    invalid.declaration = INVALID;
    invalid.block = INVALID;
    return dense_row < total ? opt_ir_ssa_demands[dense_row] : invalid;
}

public uint opt_ir_lower_bound_ssa_demand(
    uint declaration,
    uint block,
    uint total)
{
    OptIrSsaDemand needle;
    needle.declaration = declaration;
    needle.block = block;
    uint lo = 0u;
    uint hi = total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (canonical_ssa_demand_less(
                opt_ir_canonical_ssa_demand(mid, total), needle))
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

public uint opt_ir_find_ssa_demand(
    uint declaration,
    uint block,
    uint total)
{
    uint row = opt_ir_lower_bound_ssa_demand(declaration, block, total);
    OptIrSsaDemand found = opt_ir_canonical_ssa_demand(row, total);
    return found.declaration == declaration && found.block == block
        ? row : INVALID;
}
