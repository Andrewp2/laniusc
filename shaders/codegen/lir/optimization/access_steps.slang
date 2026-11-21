import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.argument_tables;

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


public void mark_local_accesses(uint position, uint total)
{
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    uint kind = node < total ? opt_ir_access_kind(opt_ir_core[node]) : OPT_IR_ACCESS_INVALID;
    opt_ir_access_flag[position] = opt_ir_node_is_executable(node, total) &&
        kind != OPT_IR_ACCESS_INVALID && opt_ir_access_domain(kind) == 0u ? 1u : 0u;
}

public void scatter_local_accesses(uint position, uint total, uint metadata_total)
{
    if (position == 0u &&
        opt_ir_instruction_access_total[0u] > access_params.access_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
            opt_ir_instruction_access_total[0u]);
        lowering_status[0u].available_capacity = access_params.access_capacity;
    }
    if (position >= total || opt_ir_access_flag[position] == 0u) return;

    uint node = semantic_schedule_order[position];
    uint access_id = metadata_total + opt_ir_access_prefix[position];
    if (node >= total || access_id >= access_params.access_capacity) return;

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

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

void local_access_layout_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = access_params.access_capacity;
}

void write_metadata_access(uint access_id, uint subject, uint source_row,
    uint function_id, uint kind, uint function_total)
{
    if (access_id >= access_params.access_capacity) return;
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
        uint active_total = min(final_total, access_params.access_capacity);
        opt_ir_metadata_access_total[0u] = min(metadata_total, active_total);
        opt_ir_access_total[0u] = active_total;
        if (final_total > access_params.access_capacity)
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
            valid = valid && access.subject < access_params.declaration_capacity;
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
                access.subject < access_params.declaration_capacity &&
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
                access.subject < access_params.declaration_capacity &&
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

public void mark_access_declaration_blocks(uint order_i, uint total)
{
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    bool starts = order_i == 0u || access_id >= access_params.access_capacity;
    if (!starts)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        starts = previous_id >= access_params.access_capacity ||
            opt_ir_accesses[previous_id].subject !=
                opt_ir_accesses[access_id].subject ||
            opt_ir_accesses[previous_id].block_id !=
                opt_ir_accesses[access_id].block_id;
    }
    opt_ir_access_group_start_flag[order_i] = starts ? 1u : 0u;
}

// Compacts one row per `(declaration, basic block)` present in the stable
// declaration-access ordering. This relation is sparse by construction: a
// declaration allocates no persistent state for blocks that do not access it.

void scatter_access_declaration_blocks_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = access_params.access_capacity;
}

public void scatter_access_declaration_blocks(uint order_i, uint total)
{
    if (order_i >= total ||
        opt_ir_access_group_start_flag[order_i] == 0u)
        return;

    uint access_id = opt_ir_access_order[order_i];
    uint row = opt_ir_access_group_prefix[order_i];
    if (access_id >= total || row >= access_params.access_capacity)
    {
        scatter_access_declaration_blocks_capacity(row + 1u);
        return;
    }

    OptIrAccessCore access = opt_ir_accesses[access_id];
    OptIrDeclarationBlock declaration_block;
    declaration_block.access_start = order_i;
    declaration_block.declaration = access.subject;
    declaration_block.block = access.block_id;
    opt_ir_declaration_blocks[row] = declaration_block;
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

// Each lane resolves a declaration within one block in schedule order.
// Reads before the first local definition seed the backward CFG walk.

void finalize_access_declaration_blocks_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

public void finalize_access_declaration_blocks(uint row, uint row_total, uint access_total)
{
    if (row >= row_total) return;

    OptIrDeclarationBlock declaration_block = opt_ir_declaration_blocks[row];
    uint end = row + 1u < row_total
        ? opt_ir_declaration_blocks[row + 1u].access_start
        : access_total;
    bool valid = declaration_block.access_start < end &&
        end <= access_total;
    uint first_access_id = valid
        ? opt_ir_access_order[declaration_block.access_start]
        : INVALID;
    valid = valid && first_access_id < access_total;
    uint declaration_id = valid
        ? opt_ir_accesses[first_access_id].subject : INVALID;
    uint block_id = valid
        ? opt_ir_accesses[first_access_id].block_id : INVALID;
    bool needs_incoming = false;
    uint definition = INVALID;
    uint outgoing = INVALID;

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
        bool defines = kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
            kind == OPT_IR_ACCESS_DECLARATION_WRITE;
        bool reads = kind == OPT_IR_ACCESS_DECLARATION_READ;
        if (defines) definition = access_id;
        outgoing = reads || defines ? definition : INVALID;
        opt_ir_local_definition_by_access[access_id] = outgoing;
        needs_incoming = needs_incoming || (reads && definition == INVALID);
    }

    if (!valid)
    {
        finalize_access_declaration_blocks_structure_failure(declaration_block.access_start);
        return;
    }

    opt_ir_ssa_demand_seed_flag[row] = needs_incoming ? 1u : 0u;
    opt_ir_outgoing_definition_by_declaration_block[row] = outgoing;
}
