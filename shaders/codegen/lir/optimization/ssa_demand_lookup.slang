// Shared exact lookup over the canonical declaration/block access relation.
// The table remains compact: keys and outgoing definitions are projected from
// stable access rows rather than duplicated in retained SSA storage.

import codegen.optimization_ir;

StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<uint> opt_ir_local_definition_by_access;
StructuredBuffer<uint> opt_ir_declaration_block_total;
StructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;

static const uint SSA_DEMAND_INVALID = 0xffffffffu;

public uint opt_ir_active_access_total(uint capacity)
{
    return min(opt_ir_access_total[0u], capacity);
}

public uint opt_ir_active_declaration_block_total(uint capacity)
{
    return min(opt_ir_declaration_block_total[0u], capacity);
}

public uint opt_ir_access_subject(uint row, uint access_total)
{
    return row < access_total ? opt_ir_accesses[row].subject
        : SSA_DEMAND_INVALID;
}

public bool opt_ir_ssa_demand_less(
    OptIrSsaDemand left,
    OptIrSsaDemand right)
{
    return left.declaration < right.declaration ||
        (left.declaration == right.declaration && left.block < right.block);
}

public OptIrSsaDemand opt_ir_declaration_block_key(
    uint row,
    uint access_total)
{
    OptIrSsaDemand key;
    key.declaration = SSA_DEMAND_INVALID;
    key.block = SSA_DEMAND_INVALID;
    uint order_i = opt_ir_declaration_blocks[row].access_start;
    if (order_i >= access_total) return key;
    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= access_total) return key;
    OptIrAccessCore access = opt_ir_accesses[access_id];
    key.declaration = access.subject;
    key.block = access.block_id;
    return key;
}

// Lower bound inside the half-open row window `[lo, hi)`. A lane that stays on
// one declaration narrows the window to that declaration's rows once and then
// pays only for the blocks of that declaration.
public uint opt_ir_lower_bound_declaration_block_in(
    uint declaration,
    uint block,
    uint lo,
    uint hi,
    uint access_total)
{
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        OptIrSsaDemand key = opt_ir_declaration_block_key(mid, access_total);
        bool less = key.declaration < declaration ||
            (key.declaration == declaration && key.block < block);
        if (less) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

public uint opt_ir_lower_bound_declaration_block(
    uint declaration,
    uint block,
    uint row_total,
    uint access_total)
{
    return opt_ir_lower_bound_declaration_block_in(
        declaration, block, 0u, row_total, access_total);
}

// `[lo, hi)` must contain every row of `declaration`; the full table always
// qualifies.
public uint opt_ir_outgoing_local_definition_in(
    uint declaration,
    uint block,
    uint lo,
    uint hi,
    uint declaration_block_total,
    uint access_total)
{
    uint row = opt_ir_lower_bound_declaration_block_in(
        declaration, block, lo, hi, access_total);
    if (row >= declaration_block_total) return SSA_DEMAND_INVALID;
    OptIrSsaDemand key = opt_ir_declaration_block_key(row, access_total);
    if (key.declaration != declaration || key.block != block)
        return SSA_DEMAND_INVALID;

    uint order_end = row + 1u < declaration_block_total
        ? opt_ir_declaration_blocks[row + 1u].access_start
        : access_total;
    if (order_end == 0u || order_end > access_total)
        return SSA_DEMAND_INVALID;
    uint access_id = opt_ir_access_order[order_end - 1u];
    return access_id < access_total
        ? opt_ir_local_definition_by_access[access_id]
        : SSA_DEMAND_INVALID;
}

public uint opt_ir_outgoing_local_definition(
    uint declaration,
    uint block,
    uint declaration_block_total,
    uint access_total)
{
    return opt_ir_outgoing_local_definition_in(
        declaration,
        block,
        0u,
        declaration_block_total,
        declaration_block_total,
        access_total);
}
