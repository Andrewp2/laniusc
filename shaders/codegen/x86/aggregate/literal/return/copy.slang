// Direct aggregate-literal return copy emission.
//
// Each invocation owns one compact aggregate-literal candidate row. Array
// element nodes and struct literal field nodes scatter their returned element
// into the enclosing return node's virtual instruction range. This avoids a
// hir_words * max_width lookup table, avoids per-return linked-list walks, and
// avoids sweeping all HIR nodes.

import gpu_index;
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
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_struct_access_record;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;
StructuredBuffer<uint> x86_enclosing_return_node;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_VALUE = 2603u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_LOCATION = 2604u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_VALUE = 2613u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_LOCATION = 2614u;

static const uint HIR_STMT = 7u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_VINST_COPY_AGG_RET = 23u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_REG = 3u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;
static const uint X86_REG_ESI = 6u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u;
}

uint gen_worklist_base()
{
    return 0u;
}

uint gen_worklist_count()
{
    return min(
        x86_node_inst_gen_input_status[4u],
        min(gParams.n_hir_nodes, gParams.inst_capacity));
}

uint gen_worklist_node(uint order_row)
{
    return x86_node_inst_gen_node_record[gen_worklist_base() + order_row].x;
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

bool is_return_stmt_node(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_STMT || hir_kind[node] == HIR_RETURN_STMT) &&
           stmt_slot(node, 0u) == STMT_RECORD_KIND_RETURN;
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

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint decl_layout_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        row,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_base(uint row)
{
    return decl_layout_word(row, 0u);
}

uint decl_layout_width(uint row)
{
    return decl_layout_word(row, 1u);
}

uint decl_layout_node(uint row)
{
    uint info = decl_layout_word(row, 2u);
    return info == INVALID ? INVALID : info >> X86_DECL_LAYOUT_KIND_BITS;
}

bool scalar_local_source_for_expr(uint value_node, uint owner_fn, out uint payload)
{
    payload = INVALID;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node) || expr_form(value_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(value_node);
    if (!valid_node(owner_fn) || !valid_token(name_token))
        return false;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token) || decl_layout_width(decl_token) != 1u)
        return false;

    uint decl_node = decl_layout_node(decl_token);
    uint base = decl_layout_base(decl_token);
    if (base == INVALID || !valid_node(decl_node) || x86_node_func[decl_node] != owner_fn)
        return false;

    payload = base;
    return true;
}

bool explicit_receiver_reg_source_for_expr(uint value_node, uint owner_fn, out uint payload)
{
    payload = INVALID;
    value_node = resolve_expr(value_node);
    if (!valid_node(owner_fn) || !valid_node(value_node) || expr_form(value_node) != HIR_EXPR_NAME)
        return false;

    uint fn_token = hir_token_pos[owner_fn];
    if (!valid_token(fn_token) || method_decl_receiver_mode[fn_token] != METHOD_RECEIVER_EXPLICIT)
        return false;

    uint name_token = expr_value_token(value_node);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    if (!valid_token(decl_token) || method_decl_param_offset[fn_token] != decl_token)
        return false;

    payload = X86_REG_ESI;
    return true;
}

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : resolve_expr(node);
}

uint struct_access_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_struct_access_record,
        row,
        X86_STRUCT_ACCESS_STRIDE,
        slot,
        INVALID);
}

uint struct_access_kind(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
}

uint struct_access_payload0(uint row)
{
    return struct_access_word(row, 0u);
}

uint struct_access_payload1(uint row)
{
    return struct_access_word(row, 1u);
}

uint array_literal_node_for_expr(uint expr_node)
{
    uint node = resolve_expr(expr_node);
    if (valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR)
        return node;
    return INVALID;
}

bool struct_literal_record_for_expr(uint expr_node, out uint width, out uint first_field)
{
    width = 0u;
    first_field = INVALID;
    uint node = INVALID;
    if (valid_node(expr_node) && struct_access_kind(expr_node) == X86_STRUCT_ACCESS_LITERAL)
        node = expr_node;
    uint resolved = resolve_expr(expr_node);
    if (!valid_node(node) && valid_node(resolved) &&
        struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL)
        node = resolved;
    uint root = expr_result_root(expr_node);
    if (!valid_node(node) && valid_node(root) &&
        struct_access_kind(root) == X86_STRUCT_ACCESS_LITERAL)
        node = root;
    uint parent = valid_node(expr_node) ? x86_tree_parent[expr_node] : INVALID;
    if (!valid_node(node) && valid_node(parent) &&
        struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        node = parent;
    parent = valid_node(resolved) ? x86_tree_parent[resolved] : INVALID;
    if (!valid_node(node) && valid_node(parent) &&
        struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        node = parent;
    parent = valid_node(root) ? x86_tree_parent[root] : INVALID;
    if (!valid_node(node) && valid_node(parent) &&
        struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        node = parent;
    if (!valid_node(node) || struct_access_kind(node) != X86_STRUCT_ACCESS_LITERAL)
        return false;
    width = struct_access_payload0(node);
    first_field = struct_access_payload1(node);
    return width != 0u && valid_node(first_field);
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
        if (location != INVALID && location < gParams.inst_capacity)
            return true;
    }

    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || local_i >= range_count(range) ||
        range.x + local_i >= gParams.inst_capacity)
        return false;

    location = range.x + local_i;
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

    vreg = INVALID;
    return false;
}

void write_status_error_detail(uint node, uint detail)
{
    publish_stage_error_first4(
        x86_virtual_inst_status,
        X86_ERR_NODE_VIRTUAL_INST,
        node,
        detail);
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

bool return_expr_is_array_literal(uint return_node, uint literal_node)
{
    if (!is_return_stmt_node(return_node) || !valid_node(literal_node))
        return false;
    uint expr_node = stmt_slot(return_node, 1u);
    return array_literal_node_for_expr(expr_node) == literal_node &&
           struct_access_kind(literal_node) == X86_STRUCT_ACCESS_ARRAY_LITERAL;
}

bool return_expr_is_struct_literal(uint return_node, uint literal_node)
{
    if (!is_return_stmt_node(return_node) || !valid_node(literal_node))
        return false;
    uint expr_node = stmt_slot(return_node, 1u);
    uint expr_width = 0u;
    uint expr_first_field = INVALID;
    return struct_literal_record_for_expr(expr_node, expr_width, expr_first_field) &&
           struct_access_kind(literal_node) == X86_STRUCT_ACCESS_LITERAL &&
           struct_access_payload0(literal_node) == expr_width &&
           struct_access_payload1(literal_node) == expr_first_field;
}

void emit_array_element_return_copy(uint node)
{
    uint literal_node = hir_array_element_parent_lit[node];
    uint ordinal = hir_array_element_ordinal[node];
    uint return_node = valid_node(node) ? x86_enclosing_return_node[node] : INVALID;
    if (!valid_node(return_node) ||
        !return_expr_is_array_literal(return_node, literal_node))
        return;
    uint src = INVALID;
    if (!value_vreg_for_node(node, src))
    {
        write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_ARRAY_VALUE);
        return;
    }

    uint row = INVALID;
    if (!location_for_node_local(return_node, ordinal, row))
    {
        write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_ARRAY_LOCATION);
        return;
    }
    write_inst(row, return_node, ordinal, X86_VINST_STORE_RET_PTR, INVALID, uint4(src, ordinal, 0u, 0u));
}

void emit_struct_field_return_copy(uint node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[node];
    uint value_node = hir_struct_lit_field_value_node[node];
    uint ordinal = struct_init_field_ordinal_by_node[node];
    uint return_node = valid_node(node) ? x86_enclosing_return_node[node] : INVALID;
    if (!valid_node(return_node) ||
        !valid_node(value_node) ||
        !return_expr_is_struct_literal(return_node, literal_node))
        return;
    uint scalar_payload = INVALID;
    if (explicit_receiver_reg_source_for_expr(value_node, x86_node_func[return_node], scalar_payload))
    {
        uint row = INVALID;
        if (!location_for_node_local(return_node, ordinal, row))
        {
            write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_STRUCT_LOCATION);
            return;
        }
        write_inst(
            row,
            return_node,
            ordinal,
            X86_VINST_COPY_AGG_RET,
            INVALID,
            uint4(X86_AGG_SOURCE_REG, scalar_payload, ordinal, 0u));
        return;
    }

    if (scalar_local_source_for_expr(value_node, x86_node_func[return_node], scalar_payload))
    {
        uint row = INVALID;
        if (!location_for_node_local(return_node, ordinal, row))
        {
            write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_STRUCT_LOCATION);
            return;
        }
        write_inst(
            row,
            return_node,
            ordinal,
            X86_VINST_COPY_AGG_RET,
            INVALID,
            uint4(X86_AGG_SOURCE_LOCAL, scalar_payload, ordinal, 0u));
        return;
    }

    uint src = INVALID;
    if (!value_vreg_for_node(value_node, src))
    {
        write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_STRUCT_VALUE);
        return;
    }

    uint row = INVALID;
    if (!location_for_node_local(return_node, ordinal, row))
    {
        write_status_error_detail(return_node, X86_VINST_ERROR_AGG_RET_STRUCT_LOCATION);
        return;
    }
    write_inst(row, return_node, ordinal, X86_VINST_STORE_RET_PTR, INVALID, uint4(src, ordinal, 0u, 0u));
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

    emit_array_element_return_copy(node);
    emit_struct_field_return_copy(node);
}
