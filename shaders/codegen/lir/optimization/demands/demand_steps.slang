import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.argument_tables;
import codegen.lir.optimization.demands.ssa_sparse_sets;

// Shared exact lookup over the canonical declaration/block access relation.
// Keys are stored with the access range. Outgoing definitions use the last
// access of that range.

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

// Lower bound inside the half-open row window `[lo, hi)`. A lane that stays on
// one declaration narrows the window to that declaration's rows once and then
// pays only for the blocks of that declaration.
public uint opt_ir_lower_bound_declaration_block_in(
    uint declaration,
    uint block,
    uint lo,
    uint hi)
{
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        OptIrDeclarationBlock key = opt_ir_declaration_blocks[mid];
        bool less = key.declaration < declaration ||
            (key.declaration == declaration && key.block < block);
        if (less) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
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
        declaration, block, lo, hi);
    if (row >= declaration_block_total) return SSA_DEMAND_INVALID;
    OptIrDeclarationBlock key = opt_ir_declaration_blocks[row];
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

// Canonical lookup over physically ordered sparse SSA block-entry demands.

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

// Shared accessors over compact pruned block arguments.

public uint opt_ir_active_ssa_block_argument_total(uint capacity)
{
    return min(opt_ir_ssa_block_argument_total[0u], capacity);
}

public OptIrBlockArgument opt_ir_ssa_block_argument(uint row)
{
    return opt_ir_ssa_block_arguments[row];
}

// Incoming rows are compacted in block-argument order, but each argument owns
// its complete range. Consumers therefore do not depend on a neighboring row
// or on the construction-time global total to recover the range end.
public uint opt_ir_ssa_block_argument_incoming_end(
    uint row,
    uint argument_total,
    uint incoming_total)
{
    if (row >= argument_total) return incoming_total;
    OptIrBlockArgument argument = opt_ir_ssa_block_arguments[row];
    uint end = argument.incoming_start + argument.incoming_count;
    return end < argument.incoming_start ? 0xffffffffu : end;
}

// Marks declaration/block rows whose first read needs a value from the CFG.
// These rows seed backward, demand-driven SSA construction; they are not a
// completed live-in relation.

void mark_value_demand_seeds_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void mark_value_demand_seeds(uint row, uint row_total)
{
    if (row >= row_total) return;

    uint state = opt_ir_reaching_definition_states[row].incoming_definition;
    bool upward_use = state == OPT_IR_REACHING_DEFINITION_UNRESOLVED;
    bool valid = upward_use || state == OPT_IR_REACHING_DEFINITION_UNUSED;
    opt_ir_ssa_demand_seed_flag[row] = upward_use ? 1u : 0u;
    if (!valid) mark_value_demand_seeds_structure_failure(row);
}

// Materializes the canonical `(declaration, block)` relation that seeds
// demand-driven SSA construction. Later fixed-point rounds use the same record
// type for transparent blocks that have no declaration-access row.

void scatter_value_demand_seeds_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = demand_params.access_capacity;
}

void scatter_value_demand_seeds_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void scatter_value_demand_seeds(uint canonical_row, uint total, uint access_total)
{
    if (canonical_row >= total ||
        opt_ir_ssa_demand_seed_flag[canonical_row] == 0u)
        return;

    uint access_start = opt_ir_declaration_blocks[canonical_row].access_start;
    uint access_id = access_start < access_total
        ? opt_ir_access_order[access_start] : demand_params.access_capacity;
    uint dense_row = opt_ir_ssa_demand_seed_prefix[canonical_row];
    if (dense_row >= demand_params.access_capacity)
        scatter_value_demand_seeds_capacity(dense_row + 1u);
    else if (access_id >= access_total)
        scatter_value_demand_seeds_structure_failure(canonical_row);
    else
    {
        OptIrAccessCore access = opt_ir_accesses[access_id];
        OptIrSsaDemand demand;
        demand.declaration = access.subject;
        demand.block = access.block_id;
        opt_ir_ssa_demands[dense_row] = demand;
    }
}

// Independently validates the sparse seeds for demand-driven SSA: each
// canonical row has the expected mark and prefix mapping, and the resulting
// `(declaration, block)` relation is strictly ordered.

void validate_value_demand_seeds_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool demand_less(OptIrSsaDemand left, OptIrSsaDemand right)
{
    return left.declaration < right.declaration ||
        (left.declaration == right.declaration && left.block < right.block);
}

public void validate_value_demand_seeds(uint row, uint row_total, uint demand_total)
{
    if (row >= row_total) return;

    bool expected =
        opt_ir_reaching_definition_states[row].incoming_definition ==
            OPT_IR_REACHING_DEFINITION_UNRESOLVED;
    bool valid = opt_ir_ssa_demand_seed_flag[row] == (expected ? 1u : 0u);
    if (expected)
    {
        uint access_total = min(opt_ir_access_total[0u],
            demand_params.access_capacity);
        uint access_start = opt_ir_declaration_blocks[row].access_start;
        uint access_id = access_start < access_total
            ? opt_ir_access_order[access_start] : demand_params.access_capacity;
        uint dense_row = opt_ir_ssa_demand_seed_prefix[row];
        valid = valid && access_id < access_total && dense_row < demand_total;
        if (valid)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrSsaDemand demand = opt_ir_ssa_demands[dense_row];
            valid = demand.declaration == access.subject &&
                demand.block == access.block_id;
        }
    }

    if (row < demand_total)
    {
        OptIrSsaDemand demand = opt_ir_ssa_demands[row];
        valid = valid && demand.declaration < demand_params.declaration_capacity &&
            demand.block < demand_params.block_capacity &&
            (row == 0u || demand_less(opt_ir_ssa_demands[row - 1u], demand));
    }

    if (!valid) validate_value_demand_seeds_structure_failure(row);
}

// Publishes the canonical seed prefix into the exact sparse set. Each seed row
// is the root of one lane of the following closure dispatch.

void publish_value_demand_seeds_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void publish_value_demand_seeds_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 101u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void publish_value_demand_seeds(uint row, uint seed_total)
{
    if (row >= seed_total) return;

    OptIrSsaDemand demand = opt_ir_ssa_demands[row];
    uint hash_capacity = demand_params.demand_capacity * 2u + 1u;
    uint hash_slot = 0xffffffffu;
    uint result = ssa_sparse_insert_key(
        demand.declaration,
        demand.block,
        hash_capacity,
        opt_ir_ssa_sparse_declaration,
        opt_ir_ssa_sparse_block,
        hash_slot);
    if (result == SSA_SPARSE_INSERT_FULL)
        publish_value_demand_seeds_capacity(hash_capacity + 1u, hash_capacity);
    else if (result != SSA_SPARSE_INSERTED)
        publish_value_demand_seeds_structure_failure(row);
}

// Computes the sparse backward block-entry-demand closure without host
// iteration, one lane per seed demand. A lane walks backward from its seed
// through the reachable predecessors that do not define the declaration.
// Exact atomic admission materializes each `(declaration, block)` row once,
// and the lane that admits a row owns it and walks on from it, so no lane
// waits on another.
//
// A lane records a resume point only when it descends before its current
// predecessor range is exhausted. A resume point stores the next predecessor
// and the previous resume row.

void close_value_demands_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void close_value_demands_structure_failure(uint row, uint reason)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, reason, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void close_value_demands(
    uint root_row,
    uint seed_total,
    uint block_total,
    uint edge_total,
    uint access_total,
    uint declaration_block_total)
{
    if (root_row >= seed_total) return;

    uint hash_capacity = demand_params.demand_capacity * 2u + 1u;

    // Seed rows are final; closure rows are appended after them.
    OptIrSsaDemand root = opt_ir_ssa_demands[root_row];
    uint declaration = root.declaration;
    // The lane never leaves its declaration, so it narrows the definition
    // lookup to that declaration's rows once.
    uint window_start = 0u;
    uint window_end = declaration_block_total;
    for (uint side = 0u; side < 2u; ++side)
    {
        uint bound = opt_ir_lower_bound_declaration_block_in(
            declaration,
            side == 0u ? 0u : INVALID,
            window_start,
            declaration_block_total);
        if (side == 0u) window_start = bound;
        else window_end = bound;
    }
    uint row = root_row;
    uint resume_row = INVALID;
    uint block = root.block;
    uint cursor = block < block_total
        ? opt_ir_predecessor_prefix[block] : INVALID;
    // A lane enters each row it owns once and resumes it at most once per
    // child it admits.
    uint budget = 2u * demand_params.demand_capacity + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        uint predecessor_end = block + 1u < block_total
            ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
        if (block >= block_total || cursor > predecessor_end ||
            predecessor_end > edge_total)
        {
            close_value_demands_structure_failure(row, 1022u);
            cursor = predecessor_end;
        }
        bool admitted = false;
        while (cursor < predecessor_end && !admitted)
        {
            uint predecessor_row = cursor;
            cursor += 1u;
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_row];
            if (edge_id >= edge_total)
            {
                close_value_demands_structure_failure(row, 1023u);
                continue;
            }
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint predecessor = edge.from_block;
            if (opt_ir_edge_to_block(edge.packed_target) != block ||
                predecessor >= block_total)
            {
                close_value_demands_structure_failure(row, 1024u);
                continue;
            }
            if (opt_ir_reachable[predecessor] == 0u) continue;
            if (opt_ir_outgoing_local_definition_in(
                    declaration,
                    predecessor,
                    window_start,
                    window_end,
                    declaration_block_total,
                    access_total) != INVALID)
                continue;

            uint hash_slot = INVALID;
            uint result = ssa_sparse_insert_key(
                declaration,
                predecessor,
                hash_capacity,
                opt_ir_ssa_sparse_declaration,
                opt_ir_ssa_sparse_block,
                hash_slot);
            if (result == SSA_SPARSE_INSERT_EXISTING) continue;
            if (result == SSA_SPARSE_INSERT_FULL)
            {
                close_value_demands_capacity(hash_capacity + 1u, hash_capacity);
                continue;
            }
            uint admitted_row;
            InterlockedAdd(opt_ir_ssa_demand_total[0u], 1u, admitted_row);
            if (admitted_row >= demand_params.demand_capacity)
            {
                close_value_demands_capacity(admitted_row + 1u, demand_params.demand_capacity);
                continue;
            }
            OptIrSsaDemand demand;
            demand.declaration = declaration;
            demand.block = predecessor;
            opt_ir_ssa_demands[admitted_row] = demand;
            if (cursor < predecessor_end)
            {
                opt_ir_ssa_walk[2u * row] = cursor;
                opt_ir_ssa_walk[2u * row + 1u] = resume_row;
                resume_row = row;
            }
            row = admitted_row;
            block = predecessor;
            cursor = opt_ir_predecessor_prefix[predecessor];
            admitted = true;
        }
        if (admitted) continue;
        if (resume_row == INVALID) return;
        row = resume_row;
        resume_row = opt_ir_ssa_walk[2u * row + 1u];
        block = opt_ir_ssa_demands[row].block;
        cursor = opt_ir_ssa_walk[2u * row];
    }
}

// Independently validates the completed sparse demand closure and its
// capacity-derived canonical ordering.

void validate_value_demands_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

OptIrSsaDemand ordered_demand(uint dense_row, uint total)
{
    OptIrSsaDemand invalid;
    invalid.declaration = INVALID;
    invalid.block = INVALID;
    return dense_row < total ? opt_ir_ssa_canonical_demands_tmp[dense_row] : invalid;
}

uint lower_bound_demand(uint declaration, uint block, uint total)
{
    OptIrSsaDemand needle;
    needle.declaration = declaration;
    needle.block = block;
    uint lo = 0u;
    uint hi = total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (opt_ir_ssa_demand_less(ordered_demand(mid, total), needle))
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

bool contains_demand(uint declaration, uint block, uint total)
{
    uint row = lower_bound_demand(declaration, block, total);
    OptIrSsaDemand found = ordered_demand(row, total);
    return found.declaration == declaration && found.block == block;
}

public void validate_value_demands(
    uint row,
    uint total,
    uint seed_total,
    uint block_total,
    uint edge_total,
    uint access_total,
    uint declaration_block_total)
{
    bool valid = true;

    if (row < total)
    {
        OptIrSsaDemand demand = ordered_demand(row, total);
        valid = demand.declaration < demand_params.declaration_capacity &&
            demand.block < block_total &&
            (row == 0u || opt_ir_ssa_demand_less(
                ordered_demand(row - 1u, total), demand));
        if (valid)
        {
            uint predecessor_start = opt_ir_predecessor_prefix[demand.block];
            uint predecessor_end = demand.block + 1u < block_total
                ? opt_ir_predecessor_prefix[demand.block + 1u]
                : edge_total;
            valid = predecessor_start <= predecessor_end &&
                predecessor_end <= edge_total;
            for (uint predecessor_i = predecessor_start;
                 valid && predecessor_i < predecessor_end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                valid = opt_ir_edge_to_block(edge.packed_target) ==
                    demand.block &&
                    edge.from_block < block_total;
                if (valid &&
                    opt_ir_reachable[edge.from_block] == 0u)
                    continue;
                if (valid && opt_ir_outgoing_local_definition(
                        demand.declaration,
                        edge.from_block,
                        declaration_block_total,
                        access_total) == INVALID)
                    valid = contains_demand(
                        demand.declaration, edge.from_block, total);
            }
        }
    }

    // Initial upward-exposed reads must remain members after closure and sort.
    if (valid && row < seed_total)
    {
        OptIrSsaDemand seed = opt_ir_ssa_demands[row];
        valid = contains_demand(seed.declaration, seed.block, total);
    }

    if (!valid) validate_value_demands_structure_failure(row);
}

// Materializes the radix permutation into one physically canonical sparse
// demand relation. Later SSA passes can then use dense rows directly instead
// of carrying the order indirection through the rest of the optimizer.

public void materialize_value_demands(uint row, uint total)
{
    if (row >= total) return;

    uint source_row = opt_ir_ssa_demand_order[row];
    OptIrSsaDemand demand;
    demand.declaration = INVALID;
    demand.block = INVALID;
    if (source_row >= total)
    {
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
        InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    }
    else
    {
        demand = opt_ir_ssa_demands[source_row];
    }
    opt_ir_ssa_canonical_demands_tmp[row] = demand;
}

// Commits physically ordered demand rows to the canonical relation after its
// publication-order contents have been validated and are no longer needed.

public void commit_value_demands(uint row, uint total)
{
    if (row < total)
        opt_ir_ssa_demands[row] = opt_ir_ssa_canonical_demands_tmp[row];
}

// Counts pruned block arguments and their predecessor inputs from the
// canonical sparse block-entry demand relation.

void mark_block_arguments_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void mark_block_arguments(uint row, uint total, uint block_total, uint edge_total)
{
    if (row >= total) return;

    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    bool valid = demand.declaration < demand_params.declaration_capacity &&
        demand.block < block_total;
    uint predecessor_count = 0u;
    if (valid)
    {
        uint begin = opt_ir_predecessor_prefix[demand.block];
        uint end = demand.block + 1u < block_total
            ? opt_ir_predecessor_prefix[demand.block + 1u]
            : edge_total;
        valid = begin <= end && end <= edge_total;
        if (valid)
        {
            for (uint predecessor_i = begin;
                 predecessor_i < end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                valid = opt_ir_edge_to_block(edge.packed_target) ==
                    demand.block && edge.from_block < block_total;
                if (!valid) break;
                if (opt_ir_reachable[edge.from_block] != 0u)
                    predecessor_count += 1u;
            }
        }
    }

    bool is_join = valid && predecessor_count > 1u;
    opt_ir_ssa_block_argument_flag[row] = is_join ? 1u : 0u;
    opt_ir_ssa_block_argument_incoming_count[row] =
        is_join ? predecessor_count : 0u;
    if (!valid) mark_block_arguments_structure_failure(row);
}

// Materializes one pruned block argument per demanded join and one symbolic
// source per predecessor. Non-join demands resolve directly to their sole
// predecessor source (or remain explicitly invalid at a CFG entry).

void scatter_block_arguments_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void scatter_block_arguments_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

OptIrSsaValueRef predecessor_source(
    uint declaration,
    uint predecessor,
    uint demand_total,
    uint declaration_block_total,
    uint access_total)
{
    OptIrSsaValueRef source;
    uint definition = opt_ir_outgoing_local_definition(
        declaration,
        predecessor,
        declaration_block_total,
        access_total);
    if (definition != INVALID)
    {
        source.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        source.payload = definition;
        return source;
    }
    source.kind = OPT_IR_SSA_SOURCE_DEMAND;
    source.payload = opt_ir_find_ssa_demand(
        declaration, predecessor, demand_total);
    if (source.payload == INVALID) source.kind = OPT_IR_SSA_SOURCE_INVALID;
    return source;
}

public void scatter_block_arguments(
    uint row,
    uint total,
    uint raw_argument_total,
    uint raw_incoming_total,
    uint block_total,
    uint edge_total,
    uint access_total,
    uint declaration_block_total)
{
    if (row >= total) return;

    if (row == 0u)
    {
        if (raw_argument_total > demand_params.demand_capacity)
            scatter_block_arguments_capacity(raw_argument_total, demand_params.demand_capacity);
        if (raw_incoming_total > demand_params.incoming_capacity)
            scatter_block_arguments_capacity(raw_incoming_total, demand_params.incoming_capacity);
    }
    uint argument_total = min(raw_argument_total, demand_params.demand_capacity);
    uint incoming_total = min(raw_incoming_total, demand_params.incoming_capacity);
    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    if (demand.block >= block_total)
    {
        scatter_block_arguments_structure_failure(row);
        return;
    }
    uint predecessor_start = opt_ir_predecessor_prefix[demand.block];
    uint predecessor_end = demand.block + 1u < block_total
        ? opt_ir_predecessor_prefix[demand.block + 1u]
        : edge_total;
    if (predecessor_start > predecessor_end || predecessor_end > edge_total)
    {
        scatter_block_arguments_structure_failure(row);
        return;
    }

    uint predecessor_count = 0u;
    for (uint predecessor_i = predecessor_start;
         predecessor_i < predecessor_end;
         ++predecessor_i)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
        if (edge_id >= edge_total)
        {
            scatter_block_arguments_structure_failure(row);
            return;
        }
        OptIrEdge edge = opt_ir_edges[edge_id];
        if (opt_ir_edge_to_block(edge.packed_target) != demand.block ||
            edge.from_block >= block_total)
        {
            scatter_block_arguments_structure_failure(row);
            return;
        }
        if (opt_ir_reachable[edge.from_block] != 0u)
            predecessor_count += 1u;
    }
    uint argument = opt_ir_ssa_block_argument_flag[row];
    uint argument_end = row + 1u < total
        ? opt_ir_ssa_block_argument_flag[row + 1u]
        : argument_total;
    uint incoming_start = opt_ir_ssa_block_argument_incoming_count[row];
    if (argument > argument_end || argument_end > argument_total ||
        argument_end - argument > 1u || incoming_start > incoming_total)
    {
        scatter_block_arguments_structure_failure(row);
        return;
    }
    bool is_join = argument_end != argument;
    OptIrSsaValueRef resolution;
    resolution.kind = OPT_IR_SSA_SOURCE_INVALID;
    resolution.payload = INVALID;

    if (is_join)
    {
        uint incoming_count = predecessor_count;
        if (argument >= argument_total || incoming_start > incoming_total ||
            incoming_count > incoming_total - incoming_start)
        {
            scatter_block_arguments_structure_failure(row);
            opt_ir_ssa_block_argument_incoming_count[row] =
                opt_ir_pack_ssa_source(resolution);
            return;
        }

        OptIrBlockArgument block_argument;
        block_argument.block_id = demand.block;
        block_argument.declaration = demand.declaration;
        block_argument.incoming_start = incoming_start;
        block_argument.incoming_count = incoming_count;
        opt_ir_ssa_block_arguments[argument] = block_argument;
        resolution.kind = OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        resolution.payload = argument;

        uint reachable_ordinal = 0u;
        for (uint predecessor_i = predecessor_start;
             predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            if (edge_id >= edge_total)
            {
                scatter_block_arguments_structure_failure(row);
                continue;
            }
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (opt_ir_edge_to_block(edge.packed_target) != demand.block ||
                edge.from_block >= block_total)
            {
                scatter_block_arguments_structure_failure(row);
                continue;
            }
            if (opt_ir_reachable[edge.from_block] == 0u)
                continue;
            OptIrSsaValueRef source = predecessor_source(
                demand.declaration,
                edge.from_block,
                total,
                declaration_block_total,
                access_total);
            if (source.kind == OPT_IR_SSA_SOURCE_INVALID)
                scatter_block_arguments_structure_failure(row);
            OptIrBlockArgumentIncoming incoming;
            incoming.predecessor = edge.from_block;
            incoming.source = opt_ir_pack_ssa_source(source);
            opt_ir_ssa_block_argument_incoming[
                incoming_start + reachable_ordinal] = incoming;
            reachable_ordinal += 1u;
        }
        if (reachable_ordinal != predecessor_count)
            scatter_block_arguments_structure_failure(row);
    }
    else if (predecessor_count == 1u)
    {
        for (uint predecessor_i = predecessor_start;
             predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            if (edge_id >= edge_total) continue;
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (edge.from_block >= block_total ||
                opt_ir_reachable[edge.from_block] == 0u)
                continue;
            if (opt_ir_edge_to_block(edge.packed_target) == demand.block &&
                edge.from_block < block_total)
                resolution = predecessor_source(
                    demand.declaration,
                    edge.from_block,
                    total,
                    declaration_block_total,
                    access_total);
        }
        if (resolution.kind == OPT_IR_SSA_SOURCE_INVALID)
            scatter_block_arguments_structure_failure(row);
    }

    opt_ir_ssa_block_argument_incoming_count[row] = opt_ir_pack_ssa_source(resolution);
}

// Independently validates pruned block arguments, their predecessor coverage,
// and every symbolic demand resolution.

void validate_block_arguments_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool valid_source(
    OptIrSsaValueRef source,
    uint demand_total,
    uint argument_total,
    uint access_total)
{
    return (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            source.payload < access_total) ||
        (source.kind == OPT_IR_SSA_SOURCE_DEMAND &&
            source.payload < demand_total) ||
        (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            source.payload < argument_total);
}

bool source_matches_predecessor(
    OptIrSsaValueRef source,
    uint declaration,
    uint predecessor,
    uint demand_total,
    uint declaration_block_total,
    uint access_total)
{
    uint definition = opt_ir_outgoing_local_definition(
        declaration,
        predecessor,
        declaration_block_total,
        access_total);
    if (definition != INVALID)
        return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            source.payload == definition;
    uint demand = opt_ir_find_ssa_demand(
        declaration, predecessor, demand_total);
    return demand != INVALID &&
        source.kind == OPT_IR_SSA_SOURCE_DEMAND &&
        source.payload == demand;
}

public void validate_block_arguments(
    uint row,
    uint total,
    uint block_total,
    uint edge_total,
    uint access_total,
    uint declaration_block_total,
    uint argument_total,
    uint incoming_total)
{
    if (row >= total) return;

    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    bool valid = demand.block < block_total;
    uint predecessor_start = valid
        ? opt_ir_predecessor_prefix[demand.block] : 0u;
    uint predecessor_end = valid
        ? (demand.block + 1u < block_total
            ? opt_ir_predecessor_prefix[demand.block + 1u]
            : edge_total)
        : 0u;
    valid = valid && predecessor_start <= predecessor_end &&
        predecessor_end <= edge_total;
    uint predecessor_count = 0u;
    for (uint predecessor_i = predecessor_start;
         valid && predecessor_i < predecessor_end;
         ++predecessor_i)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
        valid = edge_id < edge_total;
        if (!valid) break;
        OptIrEdge edge = opt_ir_edges[edge_id];
        valid = edge.from_block < block_total &&
            opt_ir_edge_to_block(edge.packed_target) == demand.block;
        if (valid &&
            opt_ir_reachable[edge.from_block] != 0u)
            predecessor_count += 1u;
    }
    uint argument = opt_ir_ssa_block_argument_flag[row];
    uint argument_end = row + 1u < total
        ? opt_ir_ssa_block_argument_flag[row + 1u]
        : argument_total;
    valid = valid && argument <= argument_end &&
        argument_end <= argument_total && argument_end - argument <= 1u;
    bool is_join = valid && argument_end != argument;
    valid = valid && is_join == (predecessor_count > 1u);

    OptIrSsaValueRef resolution =
        opt_ir_unpack_ssa_source(opt_ir_ssa_block_argument_incoming_count[row]);
    if (is_join)
    {
        valid = valid && argument < argument_total &&
            resolution.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            resolution.payload == argument;
        uint incoming_start = 0u;
        uint incoming_end = 0u;
        if (valid)
        {
            OptIrBlockArgument block_argument =
                opt_ir_ssa_block_argument(argument);
            incoming_start = block_argument.incoming_start;
            incoming_end = opt_ir_ssa_block_argument_incoming_end(
                argument, argument_total, incoming_total);
            valid = block_argument.block_id == demand.block &&
                block_argument.declaration == demand.declaration &&
                incoming_start <= incoming_end &&
                incoming_end <= incoming_total &&
                block_argument.incoming_count == predecessor_count &&
                incoming_end - incoming_start == predecessor_count;
        }
        uint reachable_ordinal = 0u;
        for (uint predecessor_i = predecessor_start;
             valid && predecessor_i < predecessor_end;
             ++predecessor_i)
        {
            uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
            valid = edge_id < edge_total;
            if (!valid) break;
            OptIrEdge edge = opt_ir_edges[edge_id];
            if (edge.from_block < block_total &&
                opt_ir_reachable[edge.from_block] == 0u)
                continue;
            OptIrBlockArgumentIncoming incoming =
                opt_ir_ssa_block_argument_incoming[
                    incoming_start + reachable_ordinal];
            OptIrSsaValueRef source =
                opt_ir_unpack_ssa_source(incoming.source);
            valid = incoming.predecessor == edge.from_block &&
                opt_ir_edge_to_block(edge.packed_target) ==
                demand.block &&
                valid_source(source, total, argument_total, access_total) &&
                source_matches_predecessor(
                    source,
                    demand.declaration,
                    edge.from_block,
                    total,
                    declaration_block_total,
                    access_total);
            reachable_ordinal += 1u;
        }
        valid = valid && reachable_ordinal == predecessor_count;
    }
    else if (predecessor_count == 1u)
    {
        valid = valid && valid_source(
            resolution, total, argument_total, access_total) &&
            resolution.kind != OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        if (valid)
        {
            bool found = false;
            for (uint predecessor_i = predecessor_start;
                 valid && predecessor_i < predecessor_end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                if (edge.from_block < block_total &&
                    opt_ir_reachable[edge.from_block] == 0u)
                    continue;
                found = true;
                valid = source_matches_predecessor(
                    resolution, demand.declaration, edge.from_block,
                    total, declaration_block_total, access_total);
            }
            valid = valid && found;
        }
    }
    else
    {
        // A demanded function-entry value has no reaching definition. Keep it
        // explicit for the SSA rewrite to diagnose against source provenance.
        valid = valid && resolution.kind == OPT_IR_SSA_SOURCE_INVALID &&
            resolution.payload == INVALID;
    }

    if (!valid) validate_block_arguments_structure_failure(row);
}

// Collapses single-predecessor demand chains to local definitions or block
// arguments. Every demand row has its own lane, which follows its chain for a
// bounded number of hops from the input table and publishes where it stopped.
// The host records two rounds between the two resolution tables; the second
// round hops over the first round's jumps, so a bound of sqrt(capacity) hops
// covers every chain the demand table can hold.

void resolve_value_demand_aliases_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void resolve_value_demand_aliases(
    uint row,
    uint total,
    RWStructuredBuffer<uint> source_resolution,
    RWStructuredBuffer<uint> destination_resolution,
    bool final_round)
{
    if (row >= total) return;

    OptIrSsaValueRef current =
        opt_ir_unpack_ssa_source(source_resolution[row]);
    if (current.kind == OPT_IR_SSA_SOURCE_DEMAND)
    {
        // A chain stays inside its declaration's contiguous demand rows.
        uint declaration = opt_ir_canonical_ssa_demand(row, total).declaration;
        for (uint hop = 0u;
             hop < demand_params.alias_hops &&
                 current.kind == OPT_IR_SSA_SOURCE_DEMAND;
             ++hop)
        {
            if (opt_ir_canonical_ssa_demand(current.payload, total).declaration
                    != declaration || current.payload >= total)
            {
                current.kind = OPT_IR_SSA_SOURCE_INVALID;
                current.payload = INVALID;
                break;
            }
            current = opt_ir_unpack_ssa_source(
                source_resolution[current.payload]);
        }
    }
    destination_resolution[row] = opt_ir_pack_ssa_source(current);
    if (final_round &&
        current.kind == OPT_IR_SSA_SOURCE_DEMAND)
        resolve_value_demand_aliases_structure_failure(row);
}

// Validates that every single-predecessor alias has collapsed to a source of
// the same declaration and that entry demands remain explicitly unresolved.

void validate_value_demand_aliases_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void validate_value_demand_aliases(
    uint row,
    uint total,
    uint block_total,
    uint edge_total,
    uint access_total,
    uint argument_total)
{
    if (row >= total) return;

    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    OptIrSsaValueRef resolution =
        opt_ir_unpack_ssa_source(opt_ir_ssa_block_argument_incoming_count[row]);
    bool valid = demand.block < block_total &&
        resolution.kind != OPT_IR_SSA_SOURCE_DEMAND;
    uint predecessor_start = valid
        ? opt_ir_predecessor_prefix[demand.block] : 0u;
    uint predecessor_end = valid
        ? (demand.block + 1u < block_total
            ? opt_ir_predecessor_prefix[demand.block + 1u]
            : edge_total)
        : 0u;
    valid = valid && predecessor_start <= predecessor_end &&
        predecessor_end <= edge_total;
    uint predecessor_count = 0u;
    for (uint predecessor_i = predecessor_start;
         valid && predecessor_i < predecessor_end;
         ++predecessor_i)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
        valid = edge_id < edge_total;
        if (!valid) break;
        OptIrEdge edge = opt_ir_edges[edge_id];
        valid = edge.from_block < block_total &&
            opt_ir_edge_to_block(edge.packed_target) == demand.block;
        if (valid &&
            opt_ir_reachable[edge.from_block] != 0u)
            predecessor_count += 1u;
    }

    if (valid && resolution.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
    {
        valid = resolution.payload < access_total &&
            opt_ir_accesses[resolution.payload].subject == demand.declaration;
        uint kind = valid
            ? opt_ir_access_kinds[resolution.payload]
            : OPT_IR_ACCESS_INVALID;
        valid = valid && (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
            kind == OPT_IR_ACCESS_DECLARATION_WRITE);
    }
    else if (valid && resolution.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        valid = resolution.payload < argument_total;
        if (valid)
        {
            OptIrBlockArgument argument =
                opt_ir_ssa_block_arguments[resolution.payload];
            valid = argument.declaration == demand.declaration;
        }
    }
    else if (valid)
    {
        valid = resolution.kind == OPT_IR_SSA_SOURCE_INVALID &&
            resolution.payload == INVALID && predecessor_count == 0u;
    }

    if (!valid) validate_value_demand_aliases_structure_failure(row);
}

// Canonicalizes predecessor sources through resolved demand aliases and counts
// reverse block-argument dependency rows. Self inputs remain in the incoming
// relation but do not create work-list edges.

void count_block_argument_users_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void count_block_argument_users(
    uint argument,
    uint argument_total,
    uint incoming_total,
    uint access_total,
    uint demand_total)
{
    if (argument >= argument_total) return;

    OptIrBlockArgument block_argument =
        opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = block_argument.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    for (uint ordinal = 0u;
         valid && block_argument.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        uint row = block_argument.incoming_start + ordinal;
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        if (source.kind == OPT_IR_SSA_SOURCE_DEMAND)
        {
            valid = source.payload < demand_total;
            if (valid)
            {
                OptIrSsaValueRef resolved = opt_ir_unpack_ssa_source(
                    opt_ir_ssa_block_argument_incoming_count[source.payload]);
                source = resolved;
                incoming.source = opt_ir_pack_ssa_source(source);
                opt_ir_ssa_block_argument_incoming[row] = incoming;
            }
        }

        valid = valid && (
            (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
                source.payload < access_total) ||
            (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
                source.payload < argument_total) ||
            (source.kind == OPT_IR_SSA_SOURCE_INVALID &&
                source.payload == INVALID));
        if (!valid)
        {
            count_block_argument_users_structure_failure(row);
            return;
        }

        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            source.payload != argument)
            InterlockedAdd(
                opt_ir_ssa_block_argument_user_count[
                    source.payload],
                1u);
    }
}

// Scatters consuming block-argument IDs into source adjacency ranges.

void scatter_block_argument_users_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

void scatter_block_argument_users_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

public void scatter_block_argument_users(
    uint argument,
    uint argument_total,
    uint incoming_total,
    uint raw_user_total)
{
    if (argument >= argument_total) return;

    uint user_capacity = demand_params.demand_capacity * 2u;
    if (argument == 0u && raw_user_total > user_capacity)
        scatter_block_argument_users_capacity(raw_user_total, user_capacity);
    uint user_total = min(raw_user_total, user_capacity);
    OptIrBlockArgument block_argument =
        opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    if (block_argument.incoming_start > incoming_end ||
        incoming_end > incoming_total)
    {
        scatter_block_argument_users_structure_failure(argument);
        return;
    }

    for (uint ordinal = 0u;
         block_argument.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        uint row = block_argument.incoming_start + ordinal;
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        if (source.kind != OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT ||
            source.payload == argument)
            continue;
        if (source.payload >= argument_total)
        {
            scatter_block_argument_users_structure_failure(row);
            continue;
        }

        uint user_ordinal;
        InterlockedAdd(
            opt_ir_ssa_block_argument_user_count[source.payload],
            1u,
            user_ordinal);
        uint target = opt_ir_ssa_block_argument_user_prefix[
            source.payload] + user_ordinal;
        if (target < user_total)
            opt_ir_ssa_block_argument_user_arguments[target] = argument;
        else
            scatter_block_argument_users_structure_failure(row);
    }
}

// Initializes the least-summary lattice and marks the arguments whose direct
// sources already give them a summary: each is the root of one propagation
// lane.

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;
// The first walk word of each of an argument's two transitions (to one
// source, to conflict): whether the transition is this argument's own start.
static const uint WALK_ROOT = 0xffffffffu;
static const uint WALK_UNCLAIMED = 0xfffffffeu;

uint combine_summary(uint current, uint contribution)
{
    if (contribution == SUMMARY_NONE) return current;
    if (current == SUMMARY_NONE || current == contribution)
        return contribution;
    return SUMMARY_CONFLICT;
}

uint direct_summary(OptIrBlockArgumentIncoming incoming)
{
    OptIrSsaValueRef source = opt_ir_unpack_ssa_source(incoming.source);
    if (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        return source.payload + 1u;
    if (source.kind == OPT_IR_SSA_SOURCE_INVALID)
        return SUMMARY_CONFLICT;
    return SUMMARY_NONE;
}

void seed_trivial_block_arguments_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 103u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void seed_trivial_block_arguments(uint argument, uint argument_total, uint incoming_total)
{
    if (argument >= argument_total) return;

    OptIrBlockArgument row = opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = row.declaration < demand_params.declaration_capacity &&
        row.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    uint summary = valid ? SUMMARY_NONE : SUMMARY_CONFLICT;
    for (uint ordinal = 0u;
         valid && row.incoming_start + ordinal < incoming_end;
         ++ordinal)
        summary = combine_summary(
            summary,
            direct_summary(opt_ir_ssa_block_argument_incoming[
                row.incoming_start + ordinal]));
    opt_ir_ssa_block_argument_summary[argument] = summary;
    if (!valid) seed_trivial_block_arguments_structure_failure(argument);

    uint transition = 2u * argument;
    opt_ir_ssa_walk[2u * transition] =
        summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT
            ? WALK_ROOT : WALK_UNCLAIMED;
    opt_ir_ssa_walk[2u * (transition + 1u)] =
        summary == SUMMARY_CONFLICT ? WALK_ROOT : WALK_UNCLAIMED;
}

// Propagates least summaries through reverse block-argument users, one lane
// per argument whose direct sources give it a summary. An argument changes at
// most twice (none, one source, conflict). The lane whose compare-exchange
// makes a change owns that transition and carries it on to the argument's own
// users, so every change reaches every user and no lane waits on another.
//
// The walk keeps no stack: a transition records the transition that caused it
// and that one's next user row, and the lane returns along that record.

// Two words per transition `2 * argument + level`: the transition that caused
// it, then that transition's next user row.

void propagate_trivial_block_arguments_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 104u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void propagate_trivial_block_arguments(uint argument, uint argument_total, uint user_total)
{
    if (argument >= argument_total) return;
    // A transition that is a root is never claimed, so its mark is stable; any
    // other first word is either unclaimed or another lane's record.
    uint root = INVALID;
    if (opt_ir_ssa_walk[4u * argument] == WALK_ROOT)
        root = 2u * argument;
    else if (opt_ir_ssa_walk[4u * argument + 2u] == WALK_ROOT)
        root = 2u * argument + 1u;
    if (root == INVALID) return;

    uint transition = root;
    uint cursor = opt_ir_ssa_block_argument_user_prefix[argument];
    // A lane enters each transition it owns once and returns from it once.
    uint budget = 4u * argument_total + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        uint source = transition >> 1u;
        // Summary updates happen in other workgroups. Read through the same
        // atomic coherence domain as the compare-exchange writers; a later
        // value than this transition's own is still a sound contribution.
        uint contribution = ssa_atomic_load(
            opt_ir_ssa_block_argument_summary, source);
        uint user_end = source + 1u < argument_total
            ? opt_ir_ssa_block_argument_user_prefix[source + 1u]
            : user_total;
        if (cursor > user_end || user_end > user_total)
        {
            propagate_trivial_block_arguments_structure_failure(source);
            cursor = user_end;
        }
        uint claimed = INVALID;
        while (cursor < user_end && claimed == INVALID)
        {
            uint user = opt_ir_ssa_block_argument_user_arguments[cursor];
            cursor += 1u;
            if (user >= argument_total ||
                opt_ir_ssa_block_argument(user).declaration !=
                    opt_ir_ssa_block_argument(source).declaration)
            {
                propagate_trivial_block_arguments_structure_failure(user);
                continue;
            }
            uint observed = ssa_atomic_load(
                opt_ir_ssa_block_argument_summary, user);
            // The user changes at most twice, so the exchange settles.
            for (uint attempt = 0u; attempt < 4u; ++attempt)
            {
                uint combined = combine_summary(observed, contribution);
                if (combined == observed) break;
                uint prior;
                InterlockedCompareExchange(
                    opt_ir_ssa_block_argument_summary[user],
                    observed,
                    combined,
                    prior);
                if (prior == observed)
                {
                    claimed = 2u * user +
                        (combined == SUMMARY_CONFLICT ? 1u : 0u);
                    break;
                }
                observed = prior;
            }
        }
        if (claimed != INVALID)
        {
            opt_ir_ssa_walk[2u * claimed] = transition;
            opt_ir_ssa_walk[2u * claimed + 1u] = cursor;
            transition = claimed;
            cursor = opt_ir_ssa_block_argument_user_prefix[claimed >> 1u];
            continue;
        }
        if (transition == root) return;
        cursor = opt_ir_ssa_walk[2u * transition + 1u];
        transition = opt_ir_ssa_walk[2u * transition];
    }
}

// Converts the least-summary fixed point into canonical replacement values.

public void finalize_trivial_block_arguments(uint argument, uint argument_total)
{
    if (argument >= argument_total) return;

    uint summary = opt_ir_ssa_block_argument_summary[argument];
    OptIrSsaValueRef replacement;
    if (summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT)
    {
        replacement.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        replacement.payload = summary - 1u;
    }
    else
    {
        replacement.kind = OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        replacement.payload = argument;
    }
    opt_ir_ssa_block_argument_replacement[argument] =
        opt_ir_pack_ssa_source(replacement);
}

// Validates the least-summary fixed-point equation, replacement decisions,
// declaration preservation, and the reverse-user adjacency relation.

void validate_trivial_block_arguments_structure_failure(uint row)
{
    {
        uint diagnostic_ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_SSA_TRIVIAL_BLOCK_ARGUMENT_VALIDATE,
            diagnostic_ignored);
    }
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void validate_trivial_block_arguments(
    uint argument,
    uint argument_total,
    uint access_total,
    uint incoming_total,
    uint user_total)
{
    if (argument >= argument_total) return;

    OptIrBlockArgument row = opt_ir_ssa_block_argument(argument);
    uint incoming_end = opt_ir_ssa_block_argument_incoming_end(
        argument, argument_total, incoming_total);
    bool valid = row.declaration < demand_params.declaration_capacity &&
        row.incoming_start <= incoming_end &&
        incoming_end <= incoming_total;
    uint expected = SUMMARY_NONE;
    for (uint ordinal = 0u;
         valid && row.incoming_start + ordinal < incoming_end;
         ++ordinal)
    {
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[
                row.incoming_start + ordinal];
        OptIrSsaValueRef source =
            opt_ir_unpack_ssa_source(incoming.source);
        uint contribution = SUMMARY_NONE;
        if (valid && source.kind ==
                OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        {
            valid = source.payload < access_total &&
                opt_ir_accesses[source.payload].subject ==
                    row.declaration;
            contribution = valid
                ? source.payload + 1u : SUMMARY_CONFLICT;
        }
        else if (valid && source.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
        {
            valid = source.payload < argument_total &&
                opt_ir_ssa_block_argument(
                    source.payload).declaration == row.declaration;
            if (valid && source.payload != argument)
                contribution =
                    opt_ir_ssa_block_argument_summary[
                        source.payload];
        }
        else if (valid && source.kind == OPT_IR_SSA_SOURCE_INVALID)
            contribution = SUMMARY_CONFLICT;
        else
            valid = false;
        expected = combine_summary(expected, contribution);
    }
    uint summary = opt_ir_ssa_block_argument_summary[argument];
    valid = valid && summary == expected;

    OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
        opt_ir_ssa_block_argument_replacement[argument]);
    if (summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT)
        valid = valid &&
            replacement.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION &&
            replacement.payload == summary - 1u;
    else
        valid = valid &&
            replacement.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == argument;

    uint user_begin = opt_ir_ssa_block_argument_user_prefix[argument];
    uint user_end = argument + 1u < argument_total
        ? opt_ir_ssa_block_argument_user_prefix[argument + 1u]
        : user_total;
    valid = valid && user_begin <= user_end && user_end <= user_total &&
        opt_ir_ssa_block_argument_user_count[argument] ==
            user_end - user_begin;
    for (uint user_i = user_begin; valid && user_i < user_end; ++user_i)
    {
        uint user_argument =
            opt_ir_ssa_block_argument_user_arguments[user_i];
        valid = user_argument < argument_total &&
            user_argument != argument;
        if (valid)
        {
            OptIrBlockArgument user =
                opt_ir_ssa_block_argument(user_argument);
            uint user_incoming_end =
                opt_ir_ssa_block_argument_incoming_end(
                    user_argument, argument_total, incoming_total);
            valid = user.incoming_start <= user_incoming_end &&
                user_incoming_end <= incoming_total;
            bool found = false;
            for (uint ordinal = 0u;
                 valid && user.incoming_start + ordinal < user_incoming_end;
                 ++ordinal)
            {
                OptIrBlockArgumentIncoming incoming =
                    opt_ir_ssa_block_argument_incoming[
                        user.incoming_start + ordinal];
                OptIrSsaValueRef source =
                    opt_ir_unpack_ssa_source(incoming.source);
                found = found ||
                    (source.kind ==
                        OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
                     source.payload == argument);
            }
            valid = valid && found;
        }
    }

    if (!valid) validate_trivial_block_arguments_structure_failure(argument);
}
