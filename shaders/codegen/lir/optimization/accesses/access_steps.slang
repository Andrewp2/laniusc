import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import radix.radix_digits;
import shared.collectives.prefix_scan;

public struct AccessParams
{
    public uint semantic_capacity;
    public uint hir_capacity;
    public uint block_capacity;
    public uint access_capacity;
    public uint declaration_capacity;
    public uint parameter_capacity;
    public uint local_capacity;
    public uint reserved;
};

public ConstantBuffer<AccessParams> gParams;
public StructuredBuffer<uint> opt_ir_block_total;
public StructuredBuffer<OptIrNodeControl> opt_ir_control;
public StructuredBuffer<uint> opt_ir_reachable;
public StructuredBuffer<uint> opt_ir_total;
public StructuredBuffer<OptIrNodeCore> opt_ir_core;
public StructuredBuffer<uint> semantic_schedule_order;
public RWStructuredBuffer<uint> opt_ir_access_flag;
public StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
public RWStructuredBuffer<uint> opt_ir_access_prefix;
public RWStructuredBuffer<uint> opt_ir_instruction_access_total;
public RWStructuredBuffer<uint> opt_ir_metadata_access_total;
public RWStructuredBuffer<OptIrAccessCore> opt_ir_accesses;
public RWStructuredBuffer<uint> opt_ir_access_source_rows;
public RWStructuredBuffer<uint> opt_ir_access_positions;
public RWStructuredBuffer<uint> opt_ir_access_kinds;
public RWStructuredBuffer<LoweringStatus> lowering_status;
public StructuredBuffer<uint> semantic_function_total;
public StructuredBuffer<uint> semantic_param_total;
public StructuredBuffer<SemanticLirParam> semantic_params;
public StructuredBuffer<uint> semantic_local_total;
public StructuredBuffer<SemanticLirLocal> semantic_locals;
public StructuredBuffer<OptIrFunction> opt_ir_functions;
public RWStructuredBuffer<uint> opt_ir_access_total;
public RWStructuredBuffer<uint> opt_ir_declaration_access_total;
public RWStructuredBuffer<uint> opt_ir_access_radix_dispatch_args;
public StructuredBuffer<uint> opt_ir_position_by_node;
public StructuredBuffer<OptIrBlock> opt_ir_blocks;
public RWStructuredBuffer<uint> opt_ir_access_order;
public RWStructuredBuffer<uint> opt_ir_access_group_start_flag;
public RWStructuredBuffer<uint> opt_ir_local_definition_by_access;
public RWStructuredBuffer<uint> opt_ir_access_group_prefix;
public RWStructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
public RWStructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
public RWStructuredBuffer<uint> opt_ir_access_group_total;
public RWStructuredBuffer<uint> opt_ir_declaration_block_total;
public RWStructuredBuffer<OptIrReachingDefinitionState> opt_ir_reaching_definition_states;
public RWStructuredBuffer<uint> access_order_temporary;
public RWStructuredBuffer<uint> access_histogram;
public RWStructuredBuffer<uint> access_bucket_total;

bool opt_ir_node_has_cfg_owner(uint node, uint node_total)
{
    return node < node_total &&
        opt_ir_control[node].block_id < opt_ir_block_total[0u];
}

bool opt_ir_node_is_executable(uint node, uint node_total)
{
    return opt_ir_node_has_cfg_owner(node, node_total) &&
        opt_ir_reachable[opt_ir_control[node].block_id] != 0u;
}

static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

public void mark_local_accesses(uint position, uint total)
{
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    opt_ir_access_flag[position] = opt_ir_node_is_executable(node, total) &&
        opt_ir_access_kind(opt_ir_core[node]) != OPT_IR_ACCESS_INVALID ? 1u : 0u;
}

public void scatter_local_accesses(uint position, uint total, uint metadata_total)
{
    if (position == 0u &&
        opt_ir_instruction_access_total[0u] > gParams.access_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
            opt_ir_instruction_access_total[0u]);
        lowering_status[0u].available_capacity = gParams.access_capacity;
    }
    if (position >= total || opt_ir_access_flag[position] == 0u) return;

    uint node = semantic_schedule_order[position];
    uint access_id = metadata_total + opt_ir_access_prefix[position];
    if (node >= total || access_id >= gParams.access_capacity) return;

    OptIrAccessCore access;
    access.subject = opt_ir_access_subject(
        opt_ir_core[node], opt_ir_operands[node], node);
    access.block_id = opt_ir_control[node].block_id;
    opt_ir_accesses[access_id] = access;
    opt_ir_access_source_rows[access_id] = node;
    opt_ir_access_positions[access_id] = position;
    opt_ir_access_kinds[access_id] = opt_ir_access_kind(opt_ir_core[node]);
}

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

void local_access_layout_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.access_capacity;
}

void write_metadata_access(uint access_id, uint subject, uint source_row,
    uint function_id, uint kind, uint function_total)
{
    if (access_id >= gParams.access_capacity) return;
    OptIrAccessCore access;
    access.subject = subject;
    if (function_id < function_total)
    {
        OptIrFunction function = opt_ir_functions[function_id];
        access.block_id = function.entry_block;
        opt_ir_access_positions[access_id] = function.node_start;
    }
    else
    {
        access.block_id = INVALID;
        opt_ir_access_positions[access_id] = 0u;
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    }
    opt_ir_accesses[access_id] = access;
    opt_ir_access_source_rows[access_id] = source_row;
    opt_ir_access_kinds[access_id] = kind;
}

public void local_access_layout(
    uint row,
    uint instruction_total,
    uint param_total,
    uint local_total,
    uint function_total)
{
    uint metadata_total = saturating_add(param_total, local_total);
    uint final_total = saturating_add(metadata_total, instruction_total);
    if (row == 0u)
    {
        uint active_total = min(final_total, gParams.access_capacity);
        opt_ir_metadata_access_total[0u] = min(metadata_total, active_total);
        opt_ir_access_total[0u] = active_total;
        // The group-mark pass lowers this to the first memory-domain row with
        // an atomic min after the stable radix ordering.
        opt_ir_declaration_access_total[0u] = active_total;
        uint blocks = max(radix_active_block_count(
            active_total, gParams.reserved, WG_SIZE), 1u);
        opt_ir_access_radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
        opt_ir_access_radix_dispatch_args[1u] =
            (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
        opt_ir_access_radix_dispatch_args[2u] = 1u;
        if (final_total > gParams.access_capacity)
            local_access_layout_capacity(final_total);
    }

    if (row < param_total)
    {
        SemanticLirParam param = semantic_params[row];
        write_metadata_access(row, param.declaration_id,
            row, param.function_id, OPT_IR_ACCESS_PARAMETER_DEFINITION,
            function_total);
    }
    if (row < local_total)
    {
        SemanticLirLocal local = semantic_locals[row];
        write_metadata_access(param_total + row,
            local.declaration_id, row, local.function_id,
            OPT_IR_ACCESS_LOCAL_DECLARATION, function_total);
    }
}

void validate_local_accesses_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

bool valid_function_position(uint function_id, uint block_id, uint position,
    uint function_total, uint block_total)
{
    if (function_id >= function_total) return false;
    OptIrFunction function = opt_ir_functions[function_id];
    if (function.entry_block == INVALID)
        return block_id == INVALID && position == 0u;
    return block_id >= function.block_start &&
        block_id < function.block_start + function.block_count &&
        block_id < block_total && position >= function.node_start &&
        position < function.node_start + function.node_count;
}

public void validate_local_accesses(
    uint access_id,
    uint access_total,
    uint node_total,
    uint block_total,
    uint function_total,
    uint param_total,
    uint local_total)
{
    if (access_id >= access_total) return;

    OptIrAccessCore access = opt_ir_accesses[access_id];
    uint source_row = opt_ir_access_source_rows[access_id];
    uint position = opt_ir_access_positions[access_id];
    uint kind = opt_ir_access_kinds[access_id];
    bool valid = kind > OPT_IR_ACCESS_INVALID &&
        kind < OPT_IR_ACCESS_KIND_COUNT;
    uint diagnostic_node = 0u;

    if (kind >= OPT_IR_ACCESS_DECLARATION_READ &&
        kind <= OPT_IR_ACCESS_MEMORY_WRITE)
    {
        diagnostic_node = source_row;
        valid = valid && opt_ir_node_is_executable(source_row, node_total) &&
            access.block_id < block_total &&
            opt_ir_control[source_row].block_id == access.block_id &&
            opt_ir_position_by_node[source_row] == position;
        if (valid)
        {
            OptIrBlock block = opt_ir_blocks[access.block_id];
            valid = valid_function_position(block.function_id,
                access.block_id, position, function_total, block_total);
        }
        if (kind == OPT_IR_ACCESS_DECLARATION_READ ||
            kind == OPT_IR_ACCESS_DECLARATION_WRITE)
            valid = valid && access.subject < gParams.declaration_capacity;
        else
            valid = valid && access.subject < node_total;
    }
    else if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
    {
        valid = valid && source_row < param_total;
        if (valid)
        {
            SemanticLirParam param = semantic_params[source_row];
            valid = access.subject == param.declaration_id &&
                access.subject < gParams.declaration_capacity &&
                valid_function_position(param.function_id, access.block_id,
                    position, function_total, block_total);
        }
    }
    else if (kind == OPT_IR_ACCESS_LOCAL_DECLARATION)
    {
        valid = valid && source_row < local_total;
        if (valid)
        {
            SemanticLirLocal local = semantic_locals[source_row];
            valid = access.subject == local.declaration_id &&
                access.subject < gParams.declaration_capacity &&
                valid_function_position(local.function_id, access.block_id,
                    position, function_total, block_total);
        }
    }
    if (!valid) validate_local_accesses_structure_failure(diagnostic_node);
}

// Boundary validation for the stable OptIR access ordering.

void validate_sorted_accesses_order_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

bool key_before_or_equal(uint left_id, uint right_id)
{
    uint left_kind = opt_ir_access_kinds[left_id];
    uint right_kind = opt_ir_access_kinds[right_id];
    uint left_domain = opt_ir_access_domain(left_kind);
    uint right_domain = opt_ir_access_domain(right_kind);
    if (left_domain != right_domain)
        return left_domain < right_domain;
    uint left_subject = opt_ir_accesses[left_id].subject;
    uint right_subject = opt_ir_accesses[right_id].subject;
    if (left_subject != right_subject)
        return left_subject < right_subject;
    // Original access IDs encode metadata-before-schedule order. Strict order
    // inside equal keys proves stability and also rejects duplicate rows.
    return left_id < right_id;
}

public void validate_sorted_accesses(uint order_i, uint total)
{
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        validate_sorted_accesses_order_failure(access_id);
        return;
    }
    if (order_i == 0u) return;

    uint previous_id = opt_ir_access_order[order_i - 1u];
    if (previous_id >= total || !key_before_or_equal(previous_id, access_id))
        validate_sorted_accesses_order_failure(access_id);
}

// Marks the first row of each declaration in the stable access ordering.
// Memory accesses occupy the following radix domain and are intentionally
// excluded from declaration SSA. Their source schedule remains authoritative;
// no memory-version graph or cross-effect load reuse is implemented here.

public void mark_access_groups(uint order_i, uint total)
{
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        opt_ir_access_group_start_flag[order_i] = 0u;
        return;
    }

    opt_ir_local_definition_by_access[access_id] = INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    if (opt_ir_access_domain(kind) != 0u)
    {
        opt_ir_access_group_start_flag[order_i] = 0u;
        InterlockedMin(opt_ir_declaration_access_total[0u], order_i);
        return;
    }

    bool starts_group = order_i == 0u;
    if (!starts_group)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        starts_group = previous_id >= total ||
            opt_ir_access_domain(opt_ir_access_kinds[previous_id]) != 0u ||
            opt_ir_accesses[previous_id].subject !=
                opt_ir_accesses[access_id].subject;
    }
    opt_ir_access_group_start_flag[order_i] = starts_group ? 1u : 0u;
}

// Reuses the declaration-group flag storage after group construction to mark
// the first ordered access in each populated `(declaration, basic block)`.

public void mark_access_declaration_blocks(uint order_i, uint total)
{
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    bool starts = order_i == 0u || access_id >= gParams.access_capacity;
    if (!starts)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        starts = previous_id >= gParams.access_capacity ||
            opt_ir_accesses[previous_id].subject !=
                opt_ir_accesses[access_id].subject ||
            opt_ir_accesses[previous_id].block_id !=
                opt_ir_accesses[access_id].block_id;
    }
    opt_ir_access_group_start_flag[order_i] = starts ? 1u : 0u;
}

// Compacts declaration group starts from the stable access ordering.

void scatter_access_groups_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.declaration_capacity;
}

public void scatter_access_groups(uint order_i, uint total)
{
    if (order_i >= total || opt_ir_access_group_start_flag[order_i] == 0u)
        return;

    uint access_id = opt_ir_access_order[order_i];
    uint group_id = opt_ir_access_group_prefix[order_i];
    if (access_id >= total || group_id >= gParams.declaration_capacity)
    {
        scatter_access_groups_capacity(group_id + 1u);
        return;
    }

    OptIrAccessGroup group;
    group.subject = opt_ir_accesses[access_id].subject;
    group.start = order_i;
    group.count = 0u;
    group.flags = 0u;
    opt_ir_access_groups[group_id] = group;
}

// Compacts one row per `(declaration, basic block)` present in the stable
// declaration-access ordering. This relation is sparse by construction: a
// declaration allocates no persistent state for blocks that do not access it.

void scatter_access_declaration_blocks_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.access_capacity;
}

public void scatter_access_declaration_blocks(uint order_i, uint total, uint access_total)
{
    if (order_i >= total ||
        opt_ir_access_group_start_flag[order_i] == 0u)
        return;

    uint access_id = opt_ir_access_order[order_i];
    uint row = opt_ir_access_group_prefix[order_i];
    if (access_id >= access_total || row >= gParams.access_capacity)
    {
        scatter_access_declaration_blocks_capacity(row + 1u);
        return;
    }

    OptIrDeclarationBlock declaration_block;
    declaration_block.access_start = order_i;
    opt_ir_declaration_blocks[row] = declaration_block;
}

// Finalizes compact declaration group ranges and produces one indirect
// workgroup per group for block-local definition resolution.

void finalize_access_groups_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

public void finalize_access_groups(
    uint group_id,
    uint group_total,
    uint access_total,
    uint declaration_total)
{
    if (group_id >= group_total) return;

    OptIrAccessGroup group = opt_ir_access_groups[group_id];
    uint end = group_id + 1u < group_total
        ? opt_ir_access_groups[group_id + 1u].start
        : declaration_total;
    bool valid = group.start < end && end <= declaration_total;
    if (valid)
    {
        uint first_id = opt_ir_access_order[group.start];
        uint last_id = opt_ir_access_order[end - 1u];
        valid = first_id < access_total && last_id < access_total &&
            opt_ir_access_domain(opt_ir_access_kinds[first_id]) == 0u &&
            opt_ir_access_domain(opt_ir_access_kinds[last_id]) == 0u &&
            opt_ir_accesses[first_id].subject == group.subject &&
            opt_ir_accesses[last_id].subject == group.subject;
        if (group_id > 0u)
            valid = valid && opt_ir_access_groups[group_id - 1u].subject <
                group.subject;
    }
    if (!valid)
    {
        finalize_access_groups_structure_failure(group.start);
        return;
    }

    group.count = end - group.start;
    opt_ir_access_groups[group_id] = group;
}

// Resolves the nearest preceding definition for declaration reads within one
// basic block. Each workgroup owns one declaration; its lanes own contiguous
// slices so the carry between slices is a small associative scan rather than a
// serial function walk. Reads unresolved at a block entry remain INVALID for
// the cross-CFG propagation stage.

public struct DefinitionSummary
{
    uint first_block;
    uint last_block;
    uint last_definition;
    uint valid;
};

public struct DefinitionSummaryScan : IPrefixScanOp<DefinitionSummary>
{
    public static DefinitionSummary identity()
    {
        DefinitionSummary result;
        result.first_block = INVALID;
        result.last_block = INVALID;
        result.last_definition = INVALID;
        result.valid = 0u;
        return result;
    }

    public static DefinitionSummary combine(
        DefinitionSummary left,
        DefinitionSummary right)
    {
        if (left.valid == 0u) return right;
        if (right.valid == 0u) return left;

        DefinitionSummary result;
        result.first_block = left.first_block;
        result.last_block = right.last_block;
        result.last_definition = right.last_definition;
        if (result.last_definition == INVALID &&
            right.first_block == right.last_block &&
            left.last_block == right.first_block)
            result.last_definition = left.last_definition;
        result.valid = 1u;
        return result;
    }
};

groupshared DefinitionSummary lane_summaries[256];

bool find_access_local_definitions_is_definition(uint kind)
{
    return kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
        kind == OPT_IR_ACCESS_DECLARATION_WRITE;
}

public void find_access_local_definitions(uint group_id, uint lane, uint group_total, uint access_total)
{
    if (group_id >= group_total) return;

    OptIrAccessGroup group = opt_ir_access_groups[group_id];
    uint rows_per_lane = group.count / WG_SIZE;
    if (group.count % WG_SIZE != 0u) rows_per_lane += 1u;
    uint begin = min(group.start + lane * rows_per_lane,
        group.start + group.count);
    uint end = min(begin + rows_per_lane, group.start + group.count);

    DefinitionSummary summary = DefinitionSummaryScan.identity();
    uint block = INVALID;
    uint definition = INVALID;
    for (uint order_i = begin; order_i < end; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        if (access_id >= access_total) continue;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        uint kind = opt_ir_access_kinds[access_id];
        if (summary.valid == 0u)
        {
            summary.first_block = access.block_id;
            summary.valid = 1u;
        }
        if (access.block_id != block)
        {
            block = access.block_id;
            definition = INVALID;
        }
        if (find_access_local_definitions_is_definition(kind)) definition = access_id;
        opt_ir_local_definition_by_access[access_id] =
            kind == OPT_IR_ACCESS_DECLARATION_READ ? definition :
            find_access_local_definitions_is_definition(kind) ? access_id : INVALID;
        summary.last_block = block;
        summary.last_definition = definition;
    }

    prefix_scan_inclusive<
        DefinitionSummary, DefinitionSummaryScan, 256>(
            lane, summary, lane_summaries);
    DefinitionSummary prior = lane == 0u
        ? DefinitionSummaryScan.identity()
        : lane_summaries[lane - 1u];
    uint carry = prior.valid != 0u && summary.valid != 0u &&
        prior.last_block == summary.first_block
        ? prior.last_definition : INVALID;
    uint first_block = summary.first_block;
    for (uint order_i = begin; order_i < end && carry != INVALID; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        if (access_id >= access_total) continue;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        if (access.block_id != first_block) break;
        uint kind = opt_ir_access_kinds[access_id];
        if (find_access_local_definitions_is_definition(kind)) break;
        if (kind == OPT_IR_ACCESS_DECLARATION_READ)
            opt_ir_local_definition_by_access[access_id] = carry;
    }
}

// Validates the block-local definition relation without requiring block-entry
// reads to be resolved; those rows are the input to cross-CFG propagation.

void validate_access_local_definitions_structure_failure(uint access_id)
{
    {
        uint diagnostic_ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_ACCESS_LOCAL_DEFINITIONS_VALIDATE,
            diagnostic_ignored);
    }
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

bool validate_access_local_definitions_is_definition(uint kind)
{
    return kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
        kind == OPT_IR_ACCESS_DECLARATION_WRITE;
}

public void validate_access_local_definitions(uint order_i, uint total)
{
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        validate_access_local_definitions_structure_failure(access_id);
        return;
    }

    uint kind = opt_ir_access_kinds[access_id];
    uint definition_id = opt_ir_local_definition_by_access[access_id];
    uint expected = INVALID;
    if (validate_access_local_definitions_is_definition(kind))
        expected = access_id;
    else if (kind == OPT_IR_ACCESS_DECLARATION_READ && order_i > 0u)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        if (previous_id < total)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrAccessCore previous = opt_ir_accesses[previous_id];
            uint previous_kind = opt_ir_access_kinds[previous_id];
            if (opt_ir_access_domain(previous_kind) == 0u &&
                previous.subject == access.subject &&
                previous.block_id == access.block_id)
                expected = validate_access_local_definitions_is_definition(previous_kind)
                    ? previous_id
                    : opt_ir_local_definition_by_access[previous_id];
        }
    }

    bool valid = definition_id == expected;
    if (valid && definition_id != INVALID)
    {
        valid = definition_id < total;
        if (valid)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrAccessCore definition = opt_ir_accesses[definition_id];
            uint definition_kind = opt_ir_access_kinds[definition_id];
            valid = validate_access_local_definitions_is_definition(definition_kind) &&
                definition.subject == access.subject &&
                definition.block_id == access.block_id &&
                opt_ir_access_positions[definition_id] <=
                    opt_ir_access_positions[access_id];
        }
    }
    if (!valid) validate_access_local_definitions_structure_failure(access_id);
}

// Finalizes sparse declaration/block ranges and initializes the compact state
// consumed by cross-CFG reaching-definition propagation.

void finalize_access_declaration_blocks_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

public void finalize_access_declaration_blocks(uint row, uint row_total, uint declaration_total, uint access_total)
{
    if (row >= row_total) return;

    OptIrDeclarationBlock declaration_block = opt_ir_declaration_blocks[row];
    uint end = row + 1u < row_total
        ? opt_ir_declaration_blocks[row + 1u].access_start
        : declaration_total;
    bool valid = declaration_block.access_start < end &&
        end <= declaration_total;
    uint first_access_id = valid
        ? opt_ir_access_order[declaration_block.access_start]
        : INVALID;
    valid = valid && first_access_id < access_total;
    uint declaration_id = valid
        ? opt_ir_accesses[first_access_id].subject : INVALID;
    uint block_id = valid
        ? opt_ir_accesses[first_access_id].block_id : INVALID;
    bool needs_incoming = false;

    for (uint order_i = declaration_block.access_start;
         valid && order_i < end; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        valid = access_id < access_total;
        if (!valid) break;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        uint kind = opt_ir_access_kinds[access_id];
        valid = access.subject == declaration_id &&
            access.block_id == block_id &&
            opt_ir_access_domain(kind) == 0u;
        if (kind == OPT_IR_ACCESS_DECLARATION_READ &&
            opt_ir_local_definition_by_access[access_id] == INVALID)
            needs_incoming = true;
    }

    if (!valid)
    {
        finalize_access_declaration_blocks_structure_failure(declaration_block.access_start);
        return;
    }

    OptIrReachingDefinitionState state;
    state.incoming_definition = needs_incoming
        ? OPT_IR_REACHING_DEFINITION_UNRESOLVED
        : OPT_IR_REACHING_DEFINITION_UNUSED;
    opt_ir_reaching_definition_states[row] = state;
}

// Validates the sparse declaration/block relation and its initialized local
// reaching-definition state independently from the construction shader.

void validate_access_declaration_blocks_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

public void validate_access_declaration_blocks(uint row, uint row_total, uint declaration_total, uint access_total)
{
    if (row >= row_total) return;

    OptIrDeclarationBlock declaration_block = opt_ir_declaration_blocks[row];
    OptIrReachingDefinitionState state =
        opt_ir_reaching_definition_states[row];
    uint end = row + 1u < row_total
        ? opt_ir_declaration_blocks[row + 1u].access_start
        : declaration_total;
    bool valid = declaration_block.access_start < end &&
        end <= declaration_total;
    uint first_access_id = valid
        ? opt_ir_access_order[declaration_block.access_start]
        : INVALID;
    valid = valid && first_access_id < access_total;
    uint declaration_id = valid
        ? opt_ir_accesses[first_access_id].subject : INVALID;
    uint block_id = valid
        ? opt_ir_accesses[first_access_id].block_id : INVALID;
    bool expected_incoming = false;

    if (row > 0u)
    {
        OptIrDeclarationBlock previous = opt_ir_declaration_blocks[row - 1u];
        uint previous_access_id =
            opt_ir_access_order[previous.access_start];
        valid = valid && previous_access_id < access_total;
        if (valid)
        {
            OptIrAccessCore previous_access =
                opt_ir_accesses[previous_access_id];
            valid = previous_access.subject < declaration_id ||
                (previous_access.subject == declaration_id &&
                 previous_access.block_id < block_id);
        }
    }

    for (uint order_i = declaration_block.access_start;
         valid && order_i < end; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        valid = access_id < access_total;
        if (!valid) break;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        uint kind = opt_ir_access_kinds[access_id];
        valid = access.subject == declaration_id &&
            access.block_id == block_id &&
            opt_ir_access_domain(kind) == 0u;
        if (kind == OPT_IR_ACCESS_DECLARATION_READ &&
            opt_ir_local_definition_by_access[access_id] == INVALID)
            expected_incoming = true;
    }

    uint expected_state = expected_incoming
        ? OPT_IR_REACHING_DEFINITION_UNRESOLVED
        : OPT_IR_REACHING_DEFINITION_UNUSED;
    valid = valid && state.incoming_definition == expected_state;
    if (!valid) validate_access_declaration_blocks_structure_failure(declaration_block.access_start);
}
