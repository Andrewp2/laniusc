import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;

public struct ValueParams
{
    public uint semantic_capacity;
    public uint parameter_capacity;
    public uint block_argument_capacity;
    public uint value_capacity;
    public uint call_argument_capacity;
    public uint aggregate_element_capacity;
    public uint block_capacity;
    public uint access_capacity;
    public uint incoming_capacity;
    public uint hir_capacity;
    public uint use_capacity;
    public uint reserved;
};

public ConstantBuffer<ValueParams> gParams;
public StructuredBuffer<uint> opt_ir_block_total;
public StructuredBuffer<OptIrNodeControl> opt_ir_control;
public StructuredBuffer<uint> opt_ir_reachable;
public StructuredBuffer<uint> opt_ir_ssa_demand_total;
public StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
public StructuredBuffer<uint> opt_ir_total;
public StructuredBuffer<OptIrNodeCore> opt_ir_core;
public StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
public StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
public RWStructuredBuffer<uint> opt_ir_ssa_node_value_flag;
public RWStructuredBuffer<uint> opt_ir_ssa_block_argument_value_flag;
public RWStructuredBuffer<LoweringStatus> lowering_status;
public StructuredBuffer<uint> semantic_param_total;
public RWStructuredBuffer<uint> opt_ir_ssa_node_value_total;
public RWStructuredBuffer<uint> opt_ir_ssa_surviving_block_argument_total;
public RWStructuredBuffer<OptIrNodeResults> opt_ir_results;
public RWStructuredBuffer<uint> opt_ir_ssa_value_total;
public RWStructuredBuffer<OptIrValueDefinition> opt_ir_ssa_value_definitions;
public RWStructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
public RWStructuredBuffer<uint> opt_ir_ssa_value_link_a;
public StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
public StructuredBuffer<uint> opt_ir_access_total;
public StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
public StructuredBuffer<uint> opt_ir_access_source_rows;
public StructuredBuffer<uint> opt_ir_access_kinds;
public StructuredBuffer<uint> opt_ir_local_definition_by_access;
public StructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
public StructuredBuffer<uint> opt_ir_source_hir;
public StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
public StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
public StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
public StructuredBuffer<uint> semantic_lir_aggregate_element_total;
public StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
public RWStructuredBuffer<OptIrNodeOperands> opt_ir_ssa_operands;
public RWStructuredBuffer<uint> opt_ir_ssa_call_argument_values;
public RWStructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
public StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
public StructuredBuffer<OptIrBlockArgumentIncoming> opt_ir_ssa_block_argument_incoming;
public RWStructuredBuffer<OptIrIncomingValue> opt_ir_ssa_incoming_values;
public StructuredBuffer<SemanticLirParam> semantic_params;
public StructuredBuffer<uint> opt_ir_position_by_node;
public StructuredBuffer<OptIrBlock> opt_ir_blocks;
public StructuredBuffer<OptIrEdge> opt_ir_edges;
public StructuredBuffer<uint> opt_ir_dominator_preorder;
public StructuredBuffer<uint> opt_ir_dominator_subtree_end;
public StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
public StructuredBuffer<uint> semantic_lir_call_arg_total;
public RWStructuredBuffer<uint> opt_ir_ssa_node_use_count;
public RWStructuredBuffer<uint> opt_ir_ssa_call_use_flag;
public RWStructuredBuffer<uint> opt_ir_ssa_aggregate_use_flag;
public RWStructuredBuffer<uint> opt_ir_ssa_node_use_total;
public RWStructuredBuffer<uint> opt_ir_ssa_call_use_total;
public RWStructuredBuffer<uint> opt_ir_ssa_aggregate_use_total;
public RWStructuredBuffer<uint> opt_ir_ssa_use_total;
public RWStructuredBuffer<uint> opt_ir_ssa_use_values;
public RWStructuredBuffer<uint> opt_ir_ssa_use_users;
public RWStructuredBuffer<uint> opt_ir_ssa_use_order;
public RWStructuredBuffer<uint> opt_ir_ssa_use_group_start_flag;
public RWStructuredBuffer<OptIrUseGroup> opt_ir_ssa_use_groups;
public RWStructuredBuffer<uint> opt_ir_ssa_use_group_total;
public RWStructuredBuffer<uint> opt_ir_ssa_value_link_b;
public RWStructuredBuffer<uint> use_order_temporary;
public RWStructuredBuffer<uint> use_histogram;
public RWStructuredBuffer<uint> use_bucket_total;

// CFG reachability is the authority for executable instruction ownership.
// Stable source rows and structured markers remain available as provenance;
// dead owners publish no canonical SSA values, operands, or uses.

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

// Canonical lookup over physically ordered sparse SSA block-entry demands.

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

// Marks the three sources that own canonical SSA definitions: parameters,
// ordinary value-producing nodes, and nontrivial block arguments. Parameters
// are already dense and therefore need no scan lane.

static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void mark_ssa_values_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_MARK,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void mark_ssa_values(uint row, uint node_total, uint argument_total)
{
    if (row < node_total)
    {
        uint op = opt_ir_op(opt_ir_core[row]);
        bool owns_definition = opt_ir_node_is_executable(row, node_total) &&
            semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        opt_ir_ssa_node_value_flag[row] = owns_definition ? 1u : 0u;
    }

    if (row < argument_total)
    {
        OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[row]);
        bool survives = replacement.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == row;
        bool valid = survives ||
            replacement.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        opt_ir_ssa_block_argument_value_flag[row] = survives ? 1u : 0u;
        if (!valid) mark_ssa_values_structure_failure(row);
    }
}

// Assigns one deterministic dense ID to every canonical SSA definition.

static const uint INVALID = 0xffffffffu;

void scatter_ssa_values_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.value_capacity;
}

void scatter_ssa_values_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_SCATTER,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint checked_total(uint parameters, uint nodes, uint arguments)
{
    uint first = parameters + nodes;
    if (first < parameters) return INVALID;
    uint total = first + arguments;
    return total < first ? INVALID : total;
}

public void scatter_ssa_values(
    uint row,
    uint parameter_total,
    uint node_total,
    uint node_value_total,
    uint argument_total,
    uint surviving_argument_total)
{
    uint surviving_argument_total =
        opt_ir_ssa_surviving_block_argument_total[0u];
    uint value_total = checked_total(parameter_total, node_value_total,
        surviving_argument_total);
    if (row == 0u)
    {
        if (value_total == INVALID || value_total > gParams.value_capacity)
            scatter_ssa_values_capacity(value_total);
        opt_ir_ssa_value_total[0u] = min(value_total,
            gParams.value_capacity);
    }

    if (row < parameter_total && row < gParams.value_capacity)
    {
        OptIrValueDefinition definition;
        definition.source = opt_ir_pack_value_definition(
            OPT_IR_VALUE_DEFINITION_PARAMETER, row);
        opt_ir_ssa_value_definitions[row] = definition;
    }

    if (row < node_total)
    {
        uint prefix = opt_ir_ssa_node_value_flag[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_value_flag[row + 1u]
            : node_value_total;
        uint op = opt_ir_op(opt_ir_core[row]);
        bool expected = opt_ir_node_is_executable(row, node_total) &&
            semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        bool valid = prefix <= end && end <= node_value_total &&
            end - prefix <= 1u && expected == (end != prefix);
        OptIrNodeResults result = opt_ir_results[row];
        result.value_out = INVALID;
        if (valid && expected)
        {
            uint value = parameter_total + prefix;
            valid = value >= parameter_total && value < value_total &&
                value < gParams.value_capacity;
            if (valid)
            {
                result.value_out = value;
                OptIrValueDefinition definition;
                definition.source = opt_ir_pack_value_definition(
                    OPT_IR_VALUE_DEFINITION_NODE, row);
                opt_ir_ssa_value_definitions[value] = definition;
            }
        }
        opt_ir_results[row] = result;
        if (!valid) scatter_ssa_values_structure_failure(row);
    }

    if (row < argument_total)
    {
        uint prefix = opt_ir_ssa_block_argument_value_flag[row];
        uint end = row + 1u < argument_total
            ? opt_ir_ssa_block_argument_value_flag[row + 1u]
            : surviving_argument_total;
        bool valid = prefix <= end && end <= surviving_argument_total &&
            end - prefix <= 1u;
        uint value = INVALID;
        if (valid && end != prefix)
        {
            uint base = parameter_total + node_value_total;
            value = base + prefix;
            valid = base >= parameter_total && value >= base &&
                value < value_total && value < gParams.value_capacity;
            if (valid)
            {
                OptIrValueDefinition definition;
                definition.source = opt_ir_pack_value_definition(
                    OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT, row);
                opt_ir_ssa_value_definitions[value] = definition;
            }
        }
        opt_ir_ssa_value_by_block_argument[row] = value;
        if (!valid) scatter_ssa_values_structure_failure(row);
    }
}

// Independently validates the dense value bijection and each category's
// prefix-derived assignment.

void validate_ssa_values_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool valid_definition(uint value, uint parameter_total, uint node_total,
    uint argument_total)
{
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return payload < parameter_total && value == payload;
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
        return opt_ir_node_is_executable(payload, node_total) &&
            opt_ir_results[payload].value_out == value;
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
        return payload < argument_total &&
            opt_ir_ssa_value_by_block_argument[payload] == value;
    return false;
}

public void validate_ssa_values(
    uint row,
    uint parameter_total,
    uint node_total,
    uint node_value_total,
    uint argument_total,
    uint surviving_argument_total,
    uint value_total)
{
    uint surviving_argument_total =
        opt_ir_ssa_surviving_block_argument_total[0u];
    bool valid = value_total == parameter_total + node_value_total +
        surviving_argument_total && value_total <= gParams.value_capacity;

    if (row < node_total)
    {
        valid = valid && opt_ir_node_has_cfg_owner(row, node_total);
        uint prefix = opt_ir_ssa_node_value_flag[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_value_flag[row + 1u]
            : node_value_total;
        uint op = opt_ir_op(opt_ir_core[row]);
        bool owns_definition = opt_ir_node_is_executable(row, node_total) &&
            semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        valid = valid && prefix <= end && end - prefix <= 1u &&
            owns_definition == (end != prefix);
        uint expected = owns_definition ? parameter_total + prefix : INVALID;
        valid = valid && opt_ir_results[row].value_out == expected;
    }

    if (row < argument_total)
    {
        uint prefix = opt_ir_ssa_block_argument_value_flag[row];
        uint end = row + 1u < argument_total
            ? opt_ir_ssa_block_argument_value_flag[row + 1u]
            : surviving_argument_total;
        OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[row]);
        bool survives = replacement.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == row;
        valid = valid && prefix <= end && end - prefix <= 1u &&
            survives == (end != prefix);
        uint expected = survives
            ? parameter_total + node_value_total + prefix
            : INVALID;
        valid = valid &&
            opt_ir_ssa_value_by_block_argument[row] == expected;
    }

    if (row < value_total)
        valid = valid && valid_definition(row, parameter_total,
            node_total, argument_total);

    if (!valid) validate_ssa_values_structure_failure(row);
}

// Initializes the temporary value-link graph. Canonical producers terminate
// at their dense value; declaration reads are filled from the reaching-
// definition relation by the following pass.

void seed_ssa_value_resolution_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 101u);
}

public void seed_ssa_value_resolution(uint row, uint total)
{
    if (row >= total) return;

    uint op = opt_ir_op(opt_ir_core[row]);
    bool produces = opt_ir_node_is_executable(row, total) &&
        semantic_lir_produces_value(op);
    uint link = 0u;
    if (produces && op != SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint value = opt_ir_results[row].value_out;
        if (value < gParams.value_capacity)
            link = opt_ir_pack_ssa_value_link(
                OPT_IR_SSA_VALUE_LINK_VALUE, value);
        else
            seed_ssa_value_resolution_structure_failure(row);
    }
    else if (!produces && opt_ir_results[row].value_out != INVALID)
        seed_ssa_value_resolution_structure_failure(row);

    opt_ir_ssa_value_link_a[row] = link;
}

// Turns each declaration read into a temporary link to either a canonical
// dense value or another declaration-read node. The latter links are compact
// copy chains and are collapsed in logarithmic GPU rounds.

void resolve_ssa_value_reads_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 102u);
}

uint node_link(uint node, uint node_total, uint value_total)
{
    if (node >= node_total) return 0u;
    uint value = opt_ir_results[node].value_out;
    if (value < value_total)
        return opt_ir_pack_ssa_value_link(
            OPT_IR_SSA_VALUE_LINK_VALUE, value);
    if (opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET)
        return opt_ir_pack_ssa_value_link(
            OPT_IR_SSA_VALUE_LINK_NODE, node);
    return 0u;
}

uint declaration_write_value_node(uint node, uint node_total)
{
    if (node >= node_total) return INVALID;
    OptIrNodeCore core = opt_ir_core[node];
    OptIrNodeOperands operands = opt_ir_operands[node];
    uint found = INVALID;
    uint count = 0u;
    for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
    {
        if (!opt_ir_operand_is_value(core, ordinal)) continue;
        found = opt_ir_operand(operands, ordinal);
        count += 1u;
    }
    return count == 1u ? found : INVALID;
}

uint definition_link(
    uint access_id,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint value_total)
{
    if (access_id >= access_total ||
        opt_ir_accesses[access_id].subject != declaration)
        return 0u;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total && source < value_total
            ? opt_ir_pack_ssa_value_link(
                OPT_IR_SSA_VALUE_LINK_VALUE, source)
            : 0u;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE || source >= node_total)
        return 0u;
    uint value_node = declaration_write_value_node(source, node_total);
    return node_link(value_node, node_total, value_total);
}

uint source_link(
    OptIrSsaValueRef source,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total,
    uint value_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return 0u;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
        {
            uint value = source.payload < argument_total
                ? opt_ir_ssa_value_by_block_argument[source.payload]
                : INVALID;
            return value < value_total
                ? opt_ir_pack_ssa_value_link(
                    OPT_IR_SSA_VALUE_LINK_VALUE, value)
                : 0u;
        }
    }
    return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION
        ? definition_link(source.payload, declaration, access_total,
            node_total, parameter_total, value_total)
        : 0u;
}

public void resolve_ssa_value_reads(
    uint access_id,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total,
    uint value_total)
{
    // `access_total` was already clamped to the physical access capacity by
    // access materialization. It also includes local-declaration metadata, so
    // semantic-plus-parameter capacity is not a valid upper bound here.
    if (access_id >= access_total ||
        opt_ir_access_kinds[access_id] !=
            OPT_IR_ACCESS_DECLARATION_READ)
        return;

    uint node = opt_ir_access_source_rows[access_id];
    OptIrAccessCore access = opt_ir_accesses[access_id];
    bool valid = node < node_total &&
        opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET &&
        opt_ir_operands[node].a == access.subject;

    OptIrSsaValueRef source;
    source.kind = OPT_IR_SSA_SOURCE_INVALID;
    source.payload = INVALID;
    uint local = opt_ir_local_definition_by_access[access_id];
    if (local != INVALID)
    {
        source.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        source.payload = local;
    }
    else
    {
        uint demand_total = opt_ir_active_ssa_demand_total(
            gParams.block_argument_capacity);
        uint demand = opt_ir_find_ssa_demand(
            access.subject, access.block_id, demand_total);
        if (demand != INVALID)
            source = opt_ir_unpack_ssa_source(
                opt_ir_ssa_demand_resolutions[demand]);
    }

    uint link = valid ? source_link(source, access.subject,
        access_total, node_total, parameter_total, argument_total,
        value_total) : 0u;
    if (link == 0u)
    {
        resolve_ssa_value_reads_structure_failure(access_id);
        return;
    }
    opt_ir_ssa_value_link_a[node] = link;
}

// One pointer-jump round over declaration-read copy chains: a round follows
// up to POINTER_JUMP_HOPS input links, so the reach of a link grows by that
// factor per round (`pointer_jump_hop_pairs` in lowering_ir.rs).

static const uint POINTER_JUMP_HOPS = 64u;

public void propagate_ssa_value_resolutions(
    uint row,
    uint total,
    RWStructuredBuffer<uint> source_links,
    RWStructuredBuffer<uint> destination_links)
{
    if (row >= total) return;

    uint link = source_links[row];
    for (uint hop = 0u; hop < POINTER_JUMP_HOPS &&
        opt_ir_ssa_value_link_kind(link) == OPT_IR_SSA_VALUE_LINK_NODE; ++hop)
    {
        uint target = opt_ir_ssa_value_link_payload(link);
        link = target < total ? source_links[target] : 0u;
    }
    destination_links[row] = link;
}

// Publishes resolved declaration-read aliases in the canonical node results.

void publish_ssa_value_resolutions_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 103u);
}

public void publish_ssa_value_resolutions(uint row, uint total, uint value_total)
{
    if (row >= total) return;

    uint op = opt_ir_op(opt_ir_core[row]);
    uint link = opt_ir_ssa_value_link_a[row];
    uint kind = opt_ir_ssa_value_link_kind(link);
    uint value = opt_ir_ssa_value_link_payload(link);
    bool executable = opt_ir_node_is_executable(row, total);
    bool produces = executable && semantic_lir_produces_value(op);
    bool valid = produces
        ? kind == OPT_IR_SSA_VALUE_LINK_VALUE && value < value_total
        : kind == OPT_IR_SSA_VALUE_LINK_INVALID;

    if (valid && !executable)
        valid = opt_ir_results[row].value_out == 0xffffffffu;
    else if (valid && op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        OptIrNodeResults result = opt_ir_results[row];
        result.value_out = value;
        opt_ir_results[row] = result;
    }
    else if (valid && produces)
        valid = opt_ir_results[row].value_out == value;

    if (!valid) publish_ssa_value_resolutions_structure_failure(row);
}

// Independently checks the local/global reaching-definition equation after
// declaration-read aliases have been published. This does not inspect the
// temporary pointer-jump links.

void validate_ssa_value_resolutions_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 104u);
}

uint definition_value(
    uint access_id,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total)
{
    if (access_id >= access_total ||
        opt_ir_accesses[access_id].subject != declaration)
        return INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total ? source : INVALID;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE || source >= node_total)
        return INVALID;
    uint value_node = declaration_write_value_node(source, node_total);
    return value_node < node_total
        ? opt_ir_results[value_node].value_out : INVALID;
}

uint source_value(
    OptIrSsaValueRef source,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return INVALID;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
            return source.payload < argument_total
                ? opt_ir_ssa_value_by_block_argument[source.payload]
                : INVALID;
    }
    return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION
        ? definition_value(source.payload, declaration, access_total,
            node_total, parameter_total)
        : INVALID;
}

public void validate_ssa_value_resolutions(
    uint access_id,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total,
    uint value_total)
{
    if (access_id >= access_total ||
        opt_ir_access_kinds[access_id] !=
            OPT_IR_ACCESS_DECLARATION_READ)
        return;

    uint node = opt_ir_access_source_rows[access_id];
    OptIrAccessCore access = opt_ir_accesses[access_id];

    OptIrSsaValueRef source;
    source.kind = OPT_IR_SSA_SOURCE_INVALID;
    source.payload = INVALID;
    uint local = opt_ir_local_definition_by_access[access_id];
    if (local != INVALID)
    {
        source.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        source.payload = local;
    }
    else
    {
        uint demand_total = opt_ir_active_ssa_demand_total(
            gParams.block_argument_capacity);
        uint demand = opt_ir_find_ssa_demand(
            access.subject, access.block_id, demand_total);
        if (demand != INVALID)
            source = opt_ir_unpack_ssa_source(
                opt_ir_ssa_demand_resolutions[demand]);
    }

    uint expected = source_value(source, access.subject, access_total,
        node_total, parameter_total, argument_total);
    bool valid = node < node_total && expected < value_total &&
        opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET &&
        opt_ir_operands[node].a == access.subject &&
        opt_ir_results[node].value_out == expected;
    if (!valid)
    {
        lowering_status[0u].first_unsupported_semantic_row = node;
        lowering_status[0u].required_capacity = access.subject;
        lowering_status[0u].available_capacity = access.block_id;
        lowering_status[0u].diagnostic_detail_kind = local;
        uint failed_demand = opt_ir_find_ssa_demand(
            access.subject, access.block_id,
            opt_ir_active_ssa_demand_total(
                gParams.block_argument_capacity));
        lowering_status[0u].diagnostic_detail = failed_demand == INVALID
            ? INVALID : opt_ir_ssa_demand_resolutions[failed_demand];
        validate_ssa_value_resolutions_structure_failure(access_id);
    }
}

// Projects every ordinary and variable-arity value edge into the canonical
// dense SSA value domain. The original semantic operands remain readable until
// the two target stages are cut over; this construction relation is temporary
// and is independently checked by the following pass.

void rewrite_operands_to_ssa_values_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_OPERAND_REWRITE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint value_for_node(uint node, uint node_total, uint value_total,
    inout bool valid)
{
    if (node >= node_total)
    {
        valid = false;
        return INVALID;
    }
    uint value = opt_ir_results[node].value_out;
    if (value >= value_total) valid = false;
    return value;
}

uint rewritten_operand(OptIrNodeCore core, OptIrNodeOperands operands,
    uint ordinal, uint node_total, uint value_total, inout bool valid)
{
    uint operand = opt_ir_operand(operands, ordinal);
    return opt_ir_operand_is_value(core, ordinal)
        ? value_for_node(operand, node_total, value_total, valid)
        : operand;
}

bool rewrite_operands_to_ssa_values_active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (!opt_ir_node_is_executable(argument.call_instruction, node_total) ||
        !semantic_lir_is_call(opt_ir_op(opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

public void rewrite_operands_to_ssa_values(uint row, uint node_total, uint value_total)
{
    if (row < gParams.semantic_capacity)
    {
        OptIrNodeOperands rewritten;
        rewritten.result = INVALID;
        rewritten.a = INVALID;
        rewritten.b = INVALID;
        rewritten.c = INVALID;
        if (opt_ir_node_is_executable(row, node_total))
        {
            bool valid = true;
            OptIrNodeCore core = opt_ir_core[row];
            OptIrNodeOperands operands = opt_ir_operands[row];
            uint result = opt_ir_results[row].value_out;
            rewritten.result = result < value_total ? result : INVALID;
            rewritten.a = rewritten_operand(core, operands, 0u,
                node_total, value_total, valid);
            rewritten.b = rewritten_operand(core, operands, 1u,
                node_total, value_total, valid);
            rewritten.c = rewritten_operand(core, operands, 2u,
                node_total, value_total, valid);
            if (!valid) rewrite_operands_to_ssa_values_structure_failure(row);
        }
        opt_ir_ssa_operands[row] = rewritten;
    }

    if (row < gParams.call_argument_capacity)
    {
        uint value = INVALID;
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        if (rewrite_operands_to_ssa_values_active_call_argument(row, argument, node_total))
        {
            bool valid = true;
            value = value_for_node(argument.value_instruction,
                node_total, value_total, valid);
            if (!valid) rewrite_operands_to_ssa_values_structure_failure(argument.call_instruction);
        }
        opt_ir_ssa_call_argument_values[row] = value;
    }

    if (row < gParams.aggregate_element_capacity)
    {
        uint aggregate_total = min(
            semantic_lir_aggregate_element_total[0u],
            gParams.aggregate_element_capacity);
        uint value = INVALID;
        if (row < aggregate_total)
        {
            SemanticLirAggregateElement element =
                semantic_lir_aggregate_elements[row];
            bool active = opt_ir_node_is_executable(
            element.aggregate_instruction, node_total) &&
            opt_ir_op(opt_ir_core[element.aggregate_instruction]) ==
                SEMANTIC_LIR_OP_AGGREGATE_NEW &&
                element.value_instruction < node_total;
            if (active)
            {
                bool valid = true;
                value = value_for_node(element.value_instruction,
                    node_total, value_total, valid);
                if (!valid)
                    rewrite_operands_to_ssa_values_structure_failure(element.aggregate_instruction);
            }
        }
        opt_ir_ssa_aggregate_element_values[row] = value;
    }
}

// Independently checks that the rewritten fixed and variable-arity operand
// relations are the exact dense-value projection of the semantic inputs.

void validate_ssa_operands_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_OPERAND_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint expected_value(uint node, uint node_total, uint value_total)
{
    return opt_ir_node_is_executable(node, node_total) &&
        opt_ir_results[node].value_out < value_total
        ? opt_ir_results[node].value_out : INVALID;
}

bool validate_ssa_operands_active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (!opt_ir_node_is_executable(argument.call_instruction, node_total) ||
        !semantic_lir_is_call(opt_ir_op(opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

public void validate_ssa_operands(uint row, uint node_total, uint value_total, uint aggregate_total)
{
    if (row < node_total)
    {
        bool executable = opt_ir_node_is_executable(row, node_total);
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands source = opt_ir_operands[row];
        OptIrNodeOperands rewritten = opt_ir_ssa_operands[row];
        bool valid = rewritten.result == expected_value(
            row, node_total, value_total);
        for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
        {
            uint original = opt_ir_operand(source, ordinal);
            uint expected = !executable ? INVALID
                : opt_ir_operand_is_value(core, ordinal)
                ? expected_value(original, node_total, value_total)
                : original;
            valid = valid && opt_ir_operand(rewritten, ordinal) == expected;
        }
        if (!valid) validate_ssa_operands_structure_failure(row);
    }

    if (row < gParams.call_argument_capacity)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        bool active = validate_ssa_operands_active_call_argument(row, argument, node_total);
        uint expected = active
            ? expected_value(argument.value_instruction, node_total, value_total)
            : INVALID;
        if ((active && expected == INVALID) ||
            opt_ir_ssa_call_argument_values[row] != expected)
            validate_ssa_operands_structure_failure(argument.call_instruction);
    }

    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = opt_ir_node_is_executable(
            element.aggregate_instruction, node_total) &&
            opt_ir_op(opt_ir_core[element.aggregate_instruction]) ==
                SEMANTIC_LIR_OP_AGGREGATE_NEW &&
            element.value_instruction < node_total;
        uint expected = active
            ? expected_value(element.value_instruction,
                node_total, value_total)
            : INVALID;
        if ((expected == INVALID && active) ||
            opt_ir_ssa_aggregate_element_values[row] != expected)
            validate_ssa_operands_structure_failure(active
                ? element.aggregate_instruction : row);
    }
}

// Replaces construction-only packed reaching-definition sources with the
// canonical dense values carried by each block-argument edge.

void rewrite_incoming_block_values_structure_failure(uint row, uint packed_source)
{
    uint prior;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_INCOMING_REWRITE,
        prior);
    if (prior == LOWERING_DIAGNOSTIC_NONE)
    {
        lowering_status[0u].diagnostic_detail_kind =
            LOWERING_DIAGNOSTIC_DETAIL_SSA_SOURCE;
        lowering_status[0u].diagnostic_detail = packed_source;
    }
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint local_definition_value(uint access_id, uint access_total,
    uint node_total, uint parameter_total, uint value_total)
{
    if (access_id >= access_total) return INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total && source < value_total
            ? source : INVALID;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE) return INVALID;
    uint value_node = declaration_write_value_node(source, node_total);
    if (value_node >= node_total) return INVALID;
    uint value = opt_ir_results[value_node].value_out;
    return value < value_total ? value : INVALID;
}

uint incoming_source_value(OptIrSsaValueRef source, uint access_total,
    uint node_total, uint parameter_total, uint argument_total,
    uint value_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return INVALID;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
    }
    if (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        return local_definition_value(source.payload, access_total,
            node_total, parameter_total, value_total);
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        uint value = source.payload < argument_total
            ? opt_ir_ssa_value_by_block_argument[source.payload]
            : INVALID;
        return value < value_total ? value : INVALID;
    }
    return INVALID;
}

public void rewrite_incoming_block_values(uint row, uint incoming_total)
{
    if (row >= gParams.incoming_capacity) return;

    OptIrIncomingValue rewritten;
    rewritten.predecessor = INVALID;
    rewritten.value = INVALID;
    if (row < incoming_total)
    {
        uint node_total = min(opt_ir_total[0u],
            gParams.semantic_capacity);
        uint parameter_total = min(semantic_param_total[0u],
            gParams.parameter_capacity);
        uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
            gParams.block_argument_capacity);
        uint access_total = min(opt_ir_access_total[0u],
            gParams.access_capacity);
        uint value_total = min(opt_ir_ssa_value_total[0u],
            gParams.value_capacity);
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        rewritten.predecessor = incoming.predecessor;
        rewritten.value = incoming_source_value(
            opt_ir_unpack_ssa_source(incoming.source),
            access_total, node_total, parameter_total, argument_total,
            value_total);
        if (rewritten.predecessor >= gParams.block_capacity ||
            rewritten.value == INVALID)
            rewrite_incoming_block_values_structure_failure(row, incoming.source);
    }
    opt_ir_ssa_incoming_values[row] = rewritten;
}

// Independently validates the final dense value edges. Every ordinary,
// variable-arity, and block-argument use must name one canonical definition
// that is available at the use site.

// The winning diagnostic records one coherent use/definition witness. The
// independently minimized opt row may identify an earlier failing use; it is
// not the owner of the witness fields below.
void validate_operand_dominance_structure_failure(uint row, uint use_node, uint use_block,
    uint value, uint site)
{
    uint prior;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_DOMINANCE,
        prior);
    if (prior == LOWERING_DIAGNOSTIC_NONE)
    {
        uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
        uint value_total = min(opt_ir_ssa_value_total[0u],
            gParams.value_capacity);
        // OptIR preserves semantic row identity at this boundary. For an
        // incoming edge without a terminator, use_node is explicitly INVALID.
        lowering_status[0u].first_unsupported_semantic_row = use_node;
        lowering_status[0u].first_unsupported_hir = use_node < node_total
            ? opt_ir_source_hir[use_node] : INVALID;
        // For this internal diagnostic these two slots carry the use block
        // and value identity, not a resource-capacity failure.
        lowering_status[0u].required_capacity = use_block;
        lowering_status[0u].available_capacity = value;
        lowering_status[0u].diagnostic_detail_kind =
            LOWERING_DIAGNOSTIC_DETAIL_VALUE_SOURCE | (site << 8u);
        lowering_status[0u].diagnostic_detail = value < value_total
            ? opt_ir_ssa_value_definitions[value].source : 0u;
    }
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool block_dominates(uint definition, uint use, uint block_total)
{
    if (definition >= block_total || use >= block_total) return false;
    if (opt_ir_blocks[definition].function_id !=
        opt_ir_blocks[use].function_id)
        return false;
    uint begin = opt_ir_dominator_preorder[definition];
    uint end = opt_ir_dominator_subtree_end[definition];
    uint point = opt_ir_dominator_preorder[use];
    return begin != INVALID && end != INVALID && point != INVALID &&
        begin <= point && point < end;
}

bool parameter_available(uint parameter, uint use_block,
    uint parameter_total, uint block_total)
{
    return parameter < parameter_total && use_block < block_total &&
        semantic_params[parameter].function_id ==
            opt_ir_blocks[use_block].function_id;
}

bool value_available_at_node(uint value, uint use_node, uint node_total,
    uint parameter_total, uint argument_total, uint value_total,
    uint block_total)
{
    if (value >= value_total || use_node >= node_total) return false;
    uint use_block = opt_ir_control[use_node].block_id;
    if (use_block >= block_total) return false;
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return parameter_available(payload, use_block,
            parameter_total, block_total);
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
    {
        if (payload >= node_total || opt_ir_results[payload].value_out != value)
            return false;
        uint definition_block = opt_ir_control[payload].block_id;
        if (definition_block == use_block)
            return opt_ir_position_by_node[payload] <
                opt_ir_position_by_node[use_node];
        return block_dominates(definition_block, use_block, block_total);
    }
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
    {
        if (payload >= argument_total ||
            opt_ir_ssa_value_by_block_argument[payload] != value)
            return false;
        uint definition_block = opt_ir_ssa_block_arguments[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    return false;
}

bool value_available_at_block_end(uint value, uint use_block,
    uint node_total, uint parameter_total, uint argument_total,
    uint value_total, uint block_total)
{
    if (value >= value_total || use_block >= block_total) return false;
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return parameter_available(payload, use_block,
            parameter_total, block_total);
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
    {
        if (payload >= node_total || opt_ir_results[payload].value_out != value)
            return false;
        uint definition_block = opt_ir_control[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
    {
        if (payload >= argument_total ||
            opt_ir_ssa_value_by_block_argument[payload] != value)
            return false;
        uint definition_block = opt_ir_ssa_block_arguments[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    return false;
}

uint expected_local_definition_value(uint access_id, uint access_total,
    uint node_total, uint parameter_total, uint value_total)
{
    if (access_id >= access_total) return INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total && source < value_total
            ? source : INVALID;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE) return INVALID;
    uint value_node = declaration_write_value_node(source, node_total);
    if (value_node >= node_total) return INVALID;
    uint value = opt_ir_results[value_node].value_out;
    return value < value_total ? value : INVALID;
}

uint expected_source_value(OptIrSsaValueRef source, uint access_total,
    uint node_total, uint parameter_total, uint argument_total,
    uint value_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return INVALID;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
    }
    if (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        return expected_local_definition_value(source.payload, access_total,
            node_total, parameter_total, value_total);
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        uint value = source.payload < argument_total
            ? opt_ir_ssa_value_by_block_argument[source.payload]
            : INVALID;
        return value < value_total ? value : INVALID;
    }
    return INVALID;
}

uint incoming_owner(uint row, uint argument_total)
{
    uint lo = 0u;
    uint hi = argument_total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (opt_ir_ssa_block_arguments[mid].incoming_start <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo == 0u) return INVALID;
    uint owner = lo - 1u;
    OptIrBlockArgument argument = opt_ir_ssa_block_arguments[owner];
    return row - argument.incoming_start < argument.incoming_count
        ? owner : INVALID;
}

bool has_cfg_edge(uint from, uint to, uint block_total)
{
    if (from >= block_total || to >= block_total) return false;
    OptIrBlock block = opt_ir_blocks[from];
    uint start = opt_ir_block_edge_start(block);
    uint count = opt_ir_block_edge_count(block);
    for (uint ordinal = 0u; ordinal < count; ++ordinal)
    {
        OptIrEdge edge = opt_ir_edges[start + ordinal];
        if (edge.from_block == from &&
            opt_ir_edge_to_block(edge.packed_target) == to)
            return true;
    }
    return false;
}

bool validate_operand_dominance_active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (!opt_ir_node_is_executable(argument.call_instruction, node_total) ||
        !semantic_lir_is_call(opt_ir_op(opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

public void validate_operand_dominance(
    uint row,
    uint node_total,
    uint parameter_total,
    uint block_total,
    uint argument_total,
    uint incoming_total,
    uint value_total,
    uint access_total,
    uint aggregate_total)
{
    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        bool executable = opt_ir_node_is_executable(row, node_total);
        if (!executable &&
            (opt_ir_results[row].value_out != INVALID ||
             operands.result != INVALID || operands.a != INVALID ||
             operands.b != INVALID || operands.c != INVALID))
            validate_operand_dominance_structure_failure(row, row, opt_ir_control[row].block_id,
                opt_ir_results[row].value_out, 6u);
        for (uint ordinal = 0u; executable && ordinal < 3u; ++ordinal)
        {
            if (!opt_ir_operand_is_value(core, ordinal)) continue;
            uint value = opt_ir_operand(operands, ordinal);
            if (!value_available_at_node(value, row, node_total,
                    parameter_total, argument_total, value_total,
                    block_total))
                validate_operand_dominance_structure_failure(row, row,
                    opt_ir_control[row].block_id, value, ordinal);
        }
    }

    if (row < gParams.call_argument_capacity)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        if (validate_operand_dominance_active_call_argument(row, argument, node_total) &&
            !value_available_at_node(opt_ir_ssa_call_argument_values[row],
                argument.call_instruction, node_total, parameter_total,
                argument_total, value_total, block_total))
            validate_operand_dominance_structure_failure(argument.call_instruction,
                argument.call_instruction,
                opt_ir_control[argument.call_instruction].block_id,
                opt_ir_ssa_call_argument_values[row], 3u);
    }

    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = opt_ir_node_is_executable(
            element.aggregate_instruction, node_total) &&
            opt_ir_op(opt_ir_core[element.aggregate_instruction]) ==
                SEMANTIC_LIR_OP_AGGREGATE_NEW &&
            element.value_instruction < node_total;
        if (active && !value_available_at_node(
                opt_ir_ssa_aggregate_element_values[row],
                element.aggregate_instruction, node_total, parameter_total,
                argument_total, value_total, block_total))
            validate_operand_dominance_structure_failure(element.aggregate_instruction,
                element.aggregate_instruction,
                opt_ir_control[element.aggregate_instruction].block_id,
                opt_ir_ssa_aggregate_element_values[row], 4u);
    }

    if (row < incoming_total)
    {
        OptIrBlockArgumentIncoming source =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrIncomingValue incoming = opt_ir_ssa_incoming_values[row];
        uint owner = incoming_owner(row, argument_total);
        uint expected = expected_source_value(
            opt_ir_unpack_ssa_source(source.source), access_total,
            node_total, parameter_total, argument_total, value_total);
        bool valid = owner < argument_total && expected != INVALID &&
            incoming.predecessor == source.predecessor &&
            incoming.value == expected;
        uint target = valid
            ? opt_ir_ssa_block_arguments[owner].block_id : INVALID;
        valid = valid && has_cfg_edge(incoming.predecessor, target,
            block_total) && value_available_at_block_end(incoming.value,
            incoming.predecessor, node_total, parameter_total,
            argument_total, value_total, block_total);
        if (!valid)
        {
            uint use_node = incoming.predecessor < block_total
                ? opt_ir_blocks[incoming.predecessor].terminator : INVALID;
            validate_operand_dominance_structure_failure(row, use_node, incoming.predecessor,
                incoming.value, 5u);
        }
    }
}

// Counts canonical fixed-operand uses per OptIR node. Declaration-state rows
// disappear at the SSA boundary, so their assignment operands do not become
// optimizer uses merely to preserve the old mutable representation.

void mark_ssa_value_uses_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_COMPACTION,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool mark_ssa_value_uses_active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (!opt_ir_node_is_executable(argument.call_instruction, node_total) ||
        !semantic_lir_is_call(opt_ir_op(
            opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

bool mark_ssa_value_uses_active_aggregate_element(SemanticLirAggregateElement element,
    uint node_total)
{
    return opt_ir_node_is_executable(element.aggregate_instruction, node_total) &&
        opt_ir_op(opt_ir_core[element.aggregate_instruction]) ==
            SEMANTIC_LIR_OP_AGGREGATE_NEW &&
        element.value_instruction < node_total;
}

public void mark_ssa_value_uses(
    uint row,
    uint node_total,
    uint call_total,
    uint aggregate_total,
    uint value_total)
{
    if (row >= max(gParams.semantic_capacity,
        max(gParams.call_argument_capacity,
            gParams.aggregate_element_capacity))) return;
    if (row < node_total)
    {
        uint count = 0u;
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        if (opt_ir_node_is_executable(row, node_total) &&
            !opt_ir_is_declaration_state_node(core))
        {
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                uint value = opt_ir_operand(operands, ordinal);
                if (value >= value_total)
                    mark_ssa_value_uses_structure_failure(row);
                else
                    count += 1u;
            }
        }
        opt_ir_ssa_node_use_count[row] = count;
    }

    if (row < call_total)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        bool active = mark_ssa_value_uses_active_call_argument(row, argument, node_total);
        if (active && opt_ir_ssa_call_argument_values[row] >= value_total)
            mark_ssa_value_uses_structure_failure(argument.call_instruction);
        opt_ir_ssa_call_use_flag[row] = active ? 1u : 0u;
    }

    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = mark_ssa_value_uses_active_aggregate_element(element, node_total);
        if (active &&
            opt_ir_ssa_aggregate_element_values[row] >= value_total)
            mark_ssa_value_uses_structure_failure(element.aggregate_instruction);
        opt_ir_ssa_aggregate_use_flag[row] = active ? 1u : 0u;
    }
}

// Concatenates fixed operands and the three already-compact variable-arity
// relations into one deterministic value-use relation.
//
// The relation's storage is not cleared before a job. On success every row
// below `opt_ir_ssa_use_total` is written here: the fixed, call, aggregate
// and incoming intervals tile [0, total), which validate_ssa_value_uses.slang checks row by
// row. A relation over capacity publishes no rows, and a
// rejected use still writes its row while the destination is in range.

void scatter_ssa_value_uses_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.use_capacity;
}

void scatter_ssa_value_uses_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_COMPACTION,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint checked_add(uint left, uint right, inout bool valid)
{
    uint result = left + right;
    if (result < left) valid = false;
    return result;
}

void write_use(uint destination, uint value, uint user,
    uint value_total, uint diagnostic_row)
{
    if (destination >= gParams.use_capacity || value >= value_total)
        scatter_ssa_value_uses_structure_failure(diagnostic_row);
    if (destination >= gParams.use_capacity) return;
    opt_ir_ssa_use_values[destination] = value;
    opt_ir_ssa_use_users[destination] = user;
}

public void scatter_ssa_value_uses(
    uint row,
    uint node_total,
    uint fixed_total,
    uint call_candidate_total,
    uint call_total,
    uint aggregate_candidate_total,
    uint aggregate_total,
    uint incoming_total,
    uint value_total)
{
    bool valid = gParams.semantic_capacity <=
        OPT_IR_USE_FIXED_NODE_MASK + 1u &&
        gParams.call_argument_capacity <= OPT_IR_USE_ROW_MASK + 1u &&
        gParams.aggregate_element_capacity <= OPT_IR_USE_ROW_MASK + 1u &&
        gParams.incoming_capacity <= OPT_IR_USE_ROW_MASK + 1u;
    uint call_base = fixed_total;
    uint aggregate_base = checked_add(call_base, call_total, valid);
    uint incoming_base = checked_add(aggregate_base, aggregate_total, valid);
    uint total = checked_add(incoming_base, incoming_total, valid);
    valid = valid && total <= gParams.use_capacity;
    if (row == 0u)
    {
        uint published = valid ? total : 0u;
        opt_ir_ssa_use_total[0u] = published;
        if (!valid) scatter_ssa_value_uses_capacity(total);
    }
    if (!valid) return;

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        uint destination = opt_ir_ssa_node_use_count[row];
        if (opt_ir_node_is_executable(row, node_total) &&
            !opt_ir_is_declaration_state_node(core))
        {
            uint rank = 0u;
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                write_use(destination + rank,
                    opt_ir_operand(operands, ordinal),
                    opt_ir_pack_fixed_use(row, ordinal),
                    value_total, row);
                rank += 1u;
            }
        }
    }

    if (row < call_candidate_total)
    {
        uint start = opt_ir_ssa_call_use_flag[row];
        uint end = row + 1u < call_candidate_total
            ? opt_ir_ssa_call_use_flag[row + 1u] : call_total;
        if (start > end || end > call_total || end - start > 1u)
        {
            scatter_ssa_value_uses_structure_failure(
                semantic_lir_call_args[row].call_instruction);
        }
        else if (end != start)
        {
            SemanticLirCallArg argument = semantic_lir_call_args[row];
            write_use(call_base + start,
                opt_ir_ssa_call_argument_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_CALL_ARGUMENT, row),
                value_total, argument.call_instruction);
        }
    }

    if (row < aggregate_candidate_total)
    {
        uint start = opt_ir_ssa_aggregate_use_flag[row];
        uint end = row + 1u < aggregate_candidate_total
            ? opt_ir_ssa_aggregate_use_flag[row + 1u]
            : aggregate_total;
        if (start > end || end > aggregate_total || end - start > 1u)
        {
            scatter_ssa_value_uses_structure_failure(
                semantic_lir_aggregate_elements[row].aggregate_instruction);
        }
        else if (end != start)
        {
            SemanticLirAggregateElement element =
                semantic_lir_aggregate_elements[row];
            write_use(aggregate_base + start,
                opt_ir_ssa_aggregate_element_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_AGGREGATE_ELEMENT, row),
                value_total, element.aggregate_instruction);
        }
    }

    if (row < incoming_total)
    {
        OptIrIncomingValue incoming = opt_ir_ssa_incoming_values[row];
        write_use(incoming_base + row, incoming.value,
            opt_ir_pack_side_use(
                OPT_IR_USE_BLOCK_ARGUMENT_INCOMING, row),
            value_total, row);
    }
}

// Independently reconstructs every compact value-use row from the canonical
// operand and side-table relations.

void validate_ssa_value_uses_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool matches_use(uint destination, uint value, uint user, uint total)
{
    return destination < total &&
        opt_ir_ssa_use_values[destination] == value &&
        opt_ir_ssa_use_users[destination] == user;
}

bool validate_ssa_value_uses_active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (!opt_ir_node_is_executable(argument.call_instruction, node_total) ||
        !semantic_lir_is_call(opt_ir_op(
            opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

bool validate_ssa_value_uses_active_aggregate_element(SemanticLirAggregateElement element,
    uint node_total)
{
    return opt_ir_node_is_executable(element.aggregate_instruction, node_total) &&
        opt_ir_op(opt_ir_core[element.aggregate_instruction]) ==
            SEMANTIC_LIR_OP_AGGREGATE_NEW &&
        element.value_instruction < node_total;
}

public void validate_ssa_value_uses(
    uint row,
    uint node_total,
    uint fixed_total,
    uint call_candidate_total,
    uint call_total,
    uint aggregate_candidate_total,
    uint aggregate_total,
    uint incoming_total,
    uint total)
{
    bool valid_total = true;
    uint call_base = fixed_total;
    uint aggregate_base = checked_add(call_base, call_total, valid_total);
    uint incoming_base = checked_add(aggregate_base, aggregate_total,
        valid_total);
    uint expected_total = checked_add(incoming_base, incoming_total,
        valid_total);
    if (row == 0u && (!valid_total || total != expected_total))
        validate_ssa_value_uses_structure_failure(0u);

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        uint start = opt_ir_ssa_node_use_count[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_use_count[row + 1u] : fixed_total;
        uint expected = 0u;
        bool valid = start <= end && end <= fixed_total;
        if (opt_ir_node_is_executable(row, node_total) &&
            !opt_ir_is_declaration_state_node(core))
        {
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                valid = valid && matches_use(start + expected,
                    opt_ir_operand(operands, ordinal),
                    opt_ir_pack_fixed_use(row, ordinal), total);
                expected += 1u;
            }
        }
        valid = valid && end - start == expected;
        if (!valid) validate_ssa_value_uses_structure_failure(row);
    }

    if (row < call_candidate_total)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        uint start = opt_ir_ssa_call_use_flag[row];
        uint end = row + 1u < call_candidate_total
            ? opt_ir_ssa_call_use_flag[row + 1u] : call_total;
        bool expected_active = validate_ssa_value_uses_active_call_argument(row, argument,
            node_total);
        bool valid = start <= end && end <= call_total &&
            end - start == (expected_active ? 1u : 0u);
        if (expected_active)
            valid = valid && matches_use(call_base + start,
                opt_ir_ssa_call_argument_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_CALL_ARGUMENT, row), total);
        if (!valid)
            validate_ssa_value_uses_structure_failure(argument.call_instruction);
    }

    if (row < aggregate_candidate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        uint start = opt_ir_ssa_aggregate_use_flag[row];
        uint end = row + 1u < aggregate_candidate_total
            ? opt_ir_ssa_aggregate_use_flag[row + 1u]
            : aggregate_total;
        bool expected_active = validate_ssa_value_uses_active_aggregate_element(element,
            node_total);
        bool valid = start <= end && end <= aggregate_total &&
            end - start == (expected_active ? 1u : 0u);
        if (expected_active)
            valid = valid && matches_use(aggregate_base + start,
                opt_ir_ssa_aggregate_element_values[row],
                opt_ir_pack_side_use(
                    OPT_IR_USE_AGGREGATE_ELEMENT, row), total);
        if (!valid)
            validate_ssa_value_uses_structure_failure(element.aggregate_instruction);
    }

    if (row < incoming_total && !matches_use(incoming_base + row,
        opt_ir_ssa_incoming_values[row].value,
        opt_ir_pack_side_use(
            OPT_IR_USE_BLOCK_ARGUMENT_INCOMING, row), total))
        validate_ssa_value_uses_structure_failure(row);
}

// Independently proves value ordering, stable tie order, and uniqueness.

void validate_sorted_ssa_uses_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_ORDER,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, use_id);
}

public void validate_sorted_ssa_uses(uint order_i, uint total)
{
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    if (use_id >= total)
    {
        validate_sorted_ssa_uses_failure(use_id);
        return;
    }
    if (order_i == 0u) return;
    uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
    bool valid = previous_id < total;
    if (valid)
    {
        uint previous_value = opt_ir_ssa_use_values[previous_id];
        uint value = opt_ir_ssa_use_values[use_id];
        valid = previous_value < value ||
            (previous_value == value && previous_id < use_id);
    }
    if (!valid) validate_sorted_ssa_uses_failure(use_id);
}

// Marks the first ordered use of every dense SSA value.

void mark_ssa_use_groups_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, use_id);
}

public void mark_ssa_use_groups(uint order_i, uint total)
{
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    if (use_id >= total)
    {
        opt_ir_ssa_use_group_start_flag[order_i] = 0u;
        mark_ssa_use_groups_failure(use_id);
        return;
    }
    bool starts = order_i == 0u;
    if (!starts)
    {
        uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
        starts = previous_id >= total ||
            opt_ir_ssa_use_values[previous_id] !=
                opt_ir_ssa_use_values[use_id];
    }
    opt_ir_ssa_use_group_start_flag[order_i] = starts ? 1u : 0u;
}

// Compacts ordered SSA value boundaries into one group per used value.

void scatter_ssa_use_groups_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.value_capacity;
}

public void scatter_ssa_use_groups(uint order_i, uint total)
{
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    bool starts = order_i == 0u;
    if (!starts && use_id < total)
    {
        uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
        starts = previous_id >= total ||
            opt_ir_ssa_use_values[previous_id] !=
                opt_ir_ssa_use_values[use_id];
    }
    if (!starts) return;
    uint group_id = opt_ir_ssa_use_group_start_flag[order_i];
    if (use_id >= total || group_id >= gParams.value_capacity)
    {
        scatter_ssa_use_groups_capacity(group_id + 1u);
        return;
    }
    OptIrUseGroup group;
    group.value = opt_ir_ssa_use_values[use_id];
    group.start = order_i;
    group.count = 0u;
    opt_ir_ssa_use_groups[group_id] = group;
}

// Finalizes exact ranges for the compact SSA value-use groups.

void finalize_ssa_use_groups_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void finalize_ssa_use_groups(uint group_id, uint group_total, uint use_total)
{
    if (group_id >= group_total) return;
    OptIrUseGroup group = opt_ir_ssa_use_groups[group_id];
    uint end = group_id + 1u < group_total
        ? opt_ir_ssa_use_groups[group_id + 1u].start : use_total;
    bool valid = group.start < end && end <= use_total;
    if (valid)
    {
        uint first_id = opt_ir_ssa_use_order[group.start];
        uint last_id = opt_ir_ssa_use_order[end - 1u];
        valid = first_id < use_total && last_id < use_total &&
            opt_ir_ssa_use_values[first_id] == group.value &&
            opt_ir_ssa_use_values[last_id] == group.value;
        if (group_id > 0u)
            valid = valid &&
                opt_ir_ssa_use_groups[group_id - 1u].value < group.value;
    }
    if (!valid)
    {
        finalize_ssa_use_groups_failure(group.start);
        return;
    }
    group.count = end - group.start;
    opt_ir_ssa_use_groups[group_id] = group;
}

// Checks that every ordered use belongs to exactly one finalized value group.

void validate_ssa_use_groups_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, use_id);
}

public void validate_ssa_use_groups(uint order_i, uint total, uint group_total)
{
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    bool starts = order_i == 0u;
    if (!starts && use_id < total)
    {
        uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
        starts = previous_id >= total ||
            opt_ir_ssa_use_values[previous_id] !=
                opt_ir_ssa_use_values[use_id];
    }
    uint prefix = opt_ir_ssa_use_group_start_flag[order_i];
    uint group_id = starts ? prefix : prefix - 1u;
    bool valid = use_id < total && prefix >= (starts ? 0u : 1u) &&
        group_id < group_total;
    if (valid)
    {
        OptIrUseGroup group = opt_ir_ssa_use_groups[group_id];
        valid = group.value == opt_ir_ssa_use_values[use_id] &&
            group.start <= order_i && order_i - group.start < group.count;
    }
    if (!valid) validate_ssa_use_groups_failure(use_id);
}
