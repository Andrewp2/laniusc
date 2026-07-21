import gpu_index;
import byte_packing;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint> x86_for_iterable_node;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_subtree_bound_start;
StructuredBuffer<uint> x86_node_inst_subtree_bound_end;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;
StructuredBuffer<uint> x86_node_func;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_ERR_FOR_ITERABLE = 33u;
static const uint X86_VINST_ERROR_FOR_LAYOUT = 2801u;
static const uint X86_VINST_ERROR_FOR_ITERABLE = 2802u;
static const uint X86_VINST_ERROR_FOR_LOCATION = 2803u;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_EXPR = 14u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_PARAM_REG_KIND_BITS = 4u;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
static const uint X86_VINST_STORE_LOCAL_IMM = 16u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_FOR_ARRAY_BRANCH = 17u;
static const uint X86_VINST_FOR_ARRAY_LOAD = 18u;
static const uint X86_VINST_FOR_ARRAY_INC_JMP = 19u;
static const uint X86_VINST_FOR_INTERVAL_BRANCH = 28u;
static const uint X86_VINST_COPY_LOCAL = 29u;
static const uint X86_VINST_FOR_PARAM_ARRAY_LOAD = 31u;

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

uint active_path_count()
{
    return path_count_out[0u];
}

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool virtual_row_in_stream(uint row)
{
    return row != INVALID && row < virtual_inst_count();
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u &&
           x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u;
}

uint gen_worklist_count()
{
    return min(
        x86_node_inst_gen_input_status[4u],
        min(gParams.n_hir_nodes, gParams.inst_capacity));
}

uint gen_worklist_node(uint order_row)
{
    return x86_node_inst_gen_node_record[order_row].x;
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : resolve_expr(node);
}

bool range_for_node(uint node, out uint2 range)
{
    range = uint2(INVALID, 0u);
    if (!valid_node(node))
        return false;
    range = uint2(x86_node_inst_location_record[node].x, x86_node_inst_range_info[node]);
    return range.x != INVALID && range.y != INVALID;
}

uint range_count(uint2 range)
{
    return range.y & X86_NODE_INST_RANGE_COUNT_MASK;
}

bool location_for_node_local(uint node, uint local_i, out uint location)
{
    location = INVALID;
    if (!valid_node(node) || !upstream_ok())
        return false;
    if (local_i < 4u)
    {
        uint4 locations = x86_node_inst_location_record[node];
        if (local_i == 0u) location = locations.x;
        else if (local_i == 1u) location = locations.y;
        else if (local_i == 2u) location = locations.z;
        else location = locations.w;
        if (virtual_row_in_stream(location))
            return true;
    }
    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || local_i >= range_count(range))
        return false;
    uint range_row = range.x + local_i;
    if (range_row < range.x || !virtual_row_in_stream(range_row))
        return false;
    location = range_row;
    return true;
}

bool value_vreg_for_candidate(uint node, out uint vreg)
{
    vreg = INVALID;
    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || range_count(range) == 0u)
        return false;
    return location_for_node_local(node, 0u, vreg);
}

bool value_vreg_for_node(uint node, out uint vreg)
{
    uint resolved = resolve_expr(node);
    if (value_vreg_for_candidate(resolved, vreg))
        return true;
    uint root = expr_result_root(node);
    if (root != resolved && value_vreg_for_candidate(root, vreg))
        return true;
    if (valid_node(node) &&
        hir_kind[node] == HIR_PATH_EXPR &&
        node != resolved &&
        node != root &&
        value_vreg_for_candidate(node, vreg))
        return true;
    vreg = INVALID;
    return false;
}

bool subtree_instruction_bounds(uint root, out uint first_row, out uint after_row)
{
    first_row = INVALID;
    after_row = INVALID;
    if (!valid_node(root))
        return false;
    first_row = x86_node_inst_subtree_bound_start[root];
    after_row = x86_node_inst_subtree_bound_end[root];
    return virtual_row_in_stream(first_row) &&
           after_row != INVALID &&
           after_row <= virtual_inst_count() &&
           after_row >= first_row;
}

bool row_after_subtree(uint root, out uint row)
{
    row = INVALID;
    uint first_row = INVALID;
    return subtree_instruction_bounds(root, first_row, row);
}

uint decl_layout_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        decl_token,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_base(uint decl_token)
{
    return decl_layout_word(decl_token, 0u);
}

uint decl_layout_width(uint decl_token)
{
    return decl_layout_word(decl_token, 1u);
}

uint decl_layout_info(uint decl_token)
{
    return decl_layout_word(decl_token, 2u);
}

uint decl_layout_kind(uint decl_token)
{
    uint info = decl_layout_info(decl_token);
    return info == INVALID ? 0u : info & X86_DECL_LAYOUT_KIND_MASK;
}

uint decl_layout_node(uint decl_token)
{
    uint info = decl_layout_info(decl_token);
    return info == INVALID ? INVALID : info >> X86_DECL_LAYOUT_KIND_BITS;
}

uint param_reg_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_param_reg_record,
        decl_token,
        X86_PARAM_REG_STRIDE,
        slot,
        INVALID);
}

uint param_reg_owner(uint decl_token)
{
    return param_reg_word(decl_token, 0u);
}

uint param_reg_width(uint decl_token)
{
    return param_reg_word(decl_token, 1u);
}

uint param_reg_info(uint decl_token)
{
    return param_reg_word(decl_token, 2u);
}

uint param_reg_ordinal(uint decl_token)
{
    return param_reg_word(decl_token, 3u);
}

uint param_reg_arg_reg(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID ? INVALID : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint param_reg_aggregate_kind(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID ? 0u : info >> X86_PARAM_REG_KIND_BITS;
}

uint4 param_reg_record(uint decl_token)
{
    return uint4(
        param_reg_owner(decl_token),
        param_reg_ordinal(decl_token),
        param_reg_arg_reg(decl_token),
        param_reg_width(decl_token));
}

bool resolved_decl_token_for_name_node(uint name_node, out uint decl_token)
{
    decl_token = INVALID;
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;
    uint dense = raw_to_compact_hir[name_node];
    uint path_i = dense < gParams.n_hir_nodes
                      ? path_id_by_owner_hir[dense]
                      : INVALID;
    if (path_i < active_path_count() &&
        resolved_value_status[path_i] == PATH_RESOLVE_STATUS_OK)
    {
        uint decl_i = resolved_value_decl[path_i];
        if (decl_i < active_hir_node_count())
        {
            uint resolved_token = decl_name_token[decl_i];
            if (valid_token(resolved_token))
            {
                decl_token = resolved_token;
                return true;
            }
        }
    }
    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;
    decl_token = visible_decl[name_token];
    return valid_token(decl_token);
}

bool decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    uint resolved = resolve_expr(node);
    if (valid_node(resolved) &&
        expr_form(resolved) == HIR_EXPR_NAME &&
        resolved_decl_token_for_name_node(resolved, decl_token))
        return true;
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NAME &&
           resolved_decl_token_for_name_node(node, decl_token);
}

bool local_slot_for_decl(uint decl_token, uint owner_fn, out uint slot)
{
    slot = INVALID;
    if (!valid_token(decl_token) || owner_fn == INVALID)
        return false;
    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    if (base != INVALID && valid_node(decl_node) && x86_node_func[decl_node] == owner_fn)
    {
        slot = base;
        return true;
    }
    return false;
}

uint for_element_width(uint node)
{
    if (!valid_node(node) ||
        !((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
          stmt_slot(node, 0u) == STMT_RECORD_KIND_FOR))
        return 1u;
    uint decl_token = stmt_slot(node, 1u);
    uint width = decl_layout_width(decl_token);
    return width == INVALID || width == 0u ? 1u : width;
}

bool for_layout_for_node(uint node, out uint value_slot, out uint index_slot)
{
    value_slot = INVALID;
    index_slot = INVALID;
    if (!valid_node(node))
        return false;
    uint decl_token = stmt_slot(node, 1u);
    if (!valid_token(decl_token))
        return false;
    value_slot = decl_layout_base(decl_token);
    uint element_width = for_element_width(node);
    if (element_width == 0u)
        return false;
    index_slot = value_slot == INVALID ? INVALID : value_slot + element_width;
    return value_slot != INVALID && index_slot != INVALID;
}

bool array_iterable_layout_for_for_node(
    uint node,
    out uint source_kind,
    out uint payload,
    out uint storage_width,
    out uint element_width)
{
    source_kind = 0u;
    payload = INVALID;
    storage_width = 0u;
    element_width = for_element_width(node);
    if (!valid_node(node) || element_width == 0u)
        return false;
    uint iterable_node = x86_for_iterable_node[node];
    if (!valid_node(iterable_node))
        return false;
    uint iterable_token = expr_value_token(iterable_node);
    if (!valid_token(iterable_token))
        return false;

    uint decl_token = visible_decl[iterable_token];
    uint base_slot = INVALID;
    if (local_slot_for_decl(decl_token, x86_node_func[node], base_slot))
    {
        uint kind = decl_layout_kind(decl_token);
        uint width = decl_layout_width(decl_token);
        if (kind == X86_DECL_AGG_ARRAY && width != 0u)
        {
            if (width % element_width != 0u)
                return false;
            source_kind = X86_AGG_SOURCE_LOCAL;
            payload = base_slot;
            storage_width = width;
            return true;
        }
    }

    uint4 param = param_reg_record(decl_token);
    if (param.x == x86_node_func[node] &&
        param.z != INVALID &&
        param.w != 0u &&
        param_reg_aggregate_kind(decl_token) == X86_DECL_AGG_ARRAY)
    {
        if (param.w % element_width != 0u)
            return false;
        source_kind = X86_AGG_SOURCE_PARAM;
        payload = pack_u16_pair(param.z, 0u);
        storage_width = param.w;
        return true;
    }
    return false;
}

bool numeric_range_iterable_for_for_node(uint node, out uint start_node, out uint end_node)
{
    start_node = INVALID;
    end_node = INVALID;
    if (!valid_node(node))
        return false;
    uint iterable_node = x86_for_iterable_node[node];
    if (!valid_node(iterable_node) ||
        hir_kind[iterable_node] != HIR_EXPR ||
        expr_form(iterable_node) != HIR_EXPR_RANGE)
        return false;
    start_node = expr_left(iterable_node);
    end_node = expr_right(iterable_node);
    return valid_node(start_node) && valid_node(end_node);
}

bool local_range_aggregate_iterable_for_for_node(uint node, out uint start_slot, out uint end_slot)
{
    start_slot = INVALID;
    end_slot = INVALID;
    if (!valid_node(node) || for_element_width(node) != 1u)
        return false;

    uint iterable_node = x86_for_iterable_node[node];
    uint decl_token = INVALID;
    uint base_slot = INVALID;
    if (!decl_token_for_name_expr(iterable_node, decl_token) ||
        !local_slot_for_decl(decl_token, x86_node_func[node], base_slot))
    {
        return false;
    }

    if (decl_layout_kind(decl_token) == 0u ||
        decl_layout_kind(decl_token) == X86_DECL_AGG_ARRAY ||
        decl_layout_width(decl_token) != 2u)
    {
        return false;
    }

    start_slot = base_slot;
    end_slot = base_slot + 1u;
    return true;
}

uint aggregate_source_payload_offset(uint source_kind, uint payload, uint offset)
{
    if (source_kind == X86_AGG_SOURCE_PARAM)
        return pack_u16_pair(unpack_u16_pair_low(payload), unpack_u16_pair_high(payload) + offset);
    return payload + offset;
}

void write_status_error_detail(uint node, uint detail)
{
    publish_stage_error_first4(
        x86_virtual_inst_status,
        X86_ERR_NODE_VIRTUAL_INST,
        node,
        detail);
}

void write_for_iterable_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_FOR_ITERABLE,
        node);
}

void write_inst(uint row, uint node, uint local_i, uint op, uint dst, uint4 args)
{
    if (row >= gParams.inst_capacity)
    {
        write_status_error_detail(node, row);
        return;
    }
    x86_virtual_inst_record[row] = uint4(node, local_i, op, dst);
    x86_virtual_inst_args[row] = args;
}

bool emit_for_stmt(uint node)
{
    uint value_slot = INVALID;
    uint index_slot = INVALID;
    uint array_source_kind = 0u;
    uint array_payload = INVALID;
    uint array_storage_width = 0u;
    uint array_element_width = 1u;
    uint range_start_node = INVALID;
    uint range_end_node = INVALID;
    uint range_start_slot = INVALID;
    uint range_end_slot = INVALID;
    uint init_row = INVALID;
    uint branch_row = INVALID;
    uint load_row = INVALID;
    uint inc_row = INVALID;
    uint after_target = INVALID;
    uint body_node = stmt_slot(node, 3u);
    if (!for_layout_for_node(node, value_slot, index_slot))
    {
        write_status_error_detail(node, X86_VINST_ERROR_FOR_LAYOUT);
        return false;
    }
    if (numeric_range_iterable_for_for_node(node, range_start_node, range_end_node))
    {
        uint start_vreg = INVALID;
        uint end_vreg = INVALID;
        if (!value_vreg_for_node(range_start_node, start_vreg) ||
            !value_vreg_for_node(range_end_node, end_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_FOR_ITERABLE);
            return false;
        }
        if (!location_for_node_local(node, 0u, init_row) ||
            !location_for_node_local(node, 1u, load_row) ||
            !location_for_node_local(node, 2u, branch_row) ||
            !location_for_node_local(body_node, 0u, inc_row) ||
            !row_after_subtree(node, after_target))
        {
            write_status_error_detail(node, X86_VINST_ERROR_FOR_LOCATION);
            return false;
        }
        write_inst(init_row, node, 0u, X86_VINST_STORE_LOCAL, INVALID, uint4(value_slot, start_vreg, 0u, 0u));
        write_inst(load_row, node, 1u, X86_VINST_STORE_LOCAL, INVALID, uint4(index_slot, end_vreg, 0u, 0u));
        write_inst(branch_row, node, 2u, X86_VINST_FOR_INTERVAL_BRANCH, INVALID, uint4(value_slot, index_slot, after_target, 0u));
        write_inst(inc_row, node, 3u, X86_VINST_FOR_ARRAY_INC_JMP, INVALID, uint4(value_slot, branch_row, 1u, 0u));
        return true;
    }
    if (local_range_aggregate_iterable_for_for_node(node, range_start_slot, range_end_slot))
    {
        if (!location_for_node_local(node, 0u, init_row) ||
            !location_for_node_local(node, 1u, load_row) ||
            !location_for_node_local(node, 2u, branch_row) ||
            !location_for_node_local(body_node, 0u, inc_row) ||
            !row_after_subtree(node, after_target))
        {
            write_status_error_detail(node, X86_VINST_ERROR_FOR_LOCATION);
            return false;
        }
        write_inst(init_row, node, 0u, X86_VINST_COPY_LOCAL, INVALID, uint4(value_slot, range_start_slot, 0u, 0u));
        write_inst(load_row, node, 1u, X86_VINST_COPY_LOCAL, INVALID, uint4(index_slot, range_end_slot, 0u, 0u));
        write_inst(branch_row, node, 2u, X86_VINST_FOR_INTERVAL_BRANCH, INVALID, uint4(value_slot, index_slot, after_target, 0u));
        write_inst(inc_row, node, 3u, X86_VINST_FOR_ARRAY_INC_JMP, INVALID, uint4(value_slot, branch_row, 1u, 0u));
        return true;
    }
    if (!array_iterable_layout_for_for_node(
            node,
            array_source_kind,
            array_payload,
            array_storage_width,
            array_element_width))
    {
        write_for_iterable_error(node);
        return false;
    }
    if (!location_for_node_local(node, 0u, init_row) ||
        !location_for_node_local(node, 1u, branch_row) ||
        !location_for_node_local(node, 2u, load_row) ||
        !location_for_node_local(body_node, 0u, inc_row) ||
        !row_after_subtree(node, after_target))
    {
        write_status_error_detail(node, X86_VINST_ERROR_FOR_LOCATION);
        return false;
    }
    write_inst(init_row, node, 0u, X86_VINST_STORE_LOCAL_IMM, INVALID, uint4(index_slot, 0u, 0u, 0u));
    write_inst(branch_row, node, 1u, X86_VINST_FOR_ARRAY_BRANCH, INVALID, uint4(index_slot, array_storage_width, after_target, 0u));
    uint load_op = array_source_kind == X86_AGG_SOURCE_PARAM
                       ? X86_VINST_FOR_PARAM_ARRAY_LOAD
                       : X86_VINST_FOR_ARRAY_LOAD;
    for (uint ordinal = 0u; ordinal < array_element_width; ordinal += 1u)
    {
        uint field_load_row = load_row + ordinal;
        uint source_payload = array_source_kind == X86_AGG_SOURCE_PARAM
                                  ? aggregate_source_payload_offset(array_source_kind, array_payload, ordinal)
                                  : array_payload + ordinal;
        write_inst(
            field_load_row,
            node,
            2u + ordinal,
            load_op,
            INVALID,
            uint4(source_payload, index_slot, value_slot + ordinal, 0u));
    }
    write_inst(inc_row, node, 2u + array_element_width, X86_VINST_FOR_ARRAY_INC_JMP, INVALID, uint4(index_slot, branch_row, array_element_width, 0u));
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint order_row = linear_dispatch_id(tid);
    if (!upstream_ok() || order_row >= gen_worklist_count())
        return;
    uint node = gen_worklist_node(order_row);
    if (!valid_node(node))
        return;
    if (!((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
          stmt_slot(node, 0u) == STMT_RECORD_KIND_FOR))
        return;
    if (!emit_for_stmt(node))
        write_status_error_detail(node, hir_kind[node]);
}
