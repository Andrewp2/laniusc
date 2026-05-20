// x86_64 node-local virtual instruction counts.
//
// This pass is the backend counterpart of Pareas' instruction-count stage:
// each attributed HIR node receives a local virtual instruction count. Prefix
// sums over these rows can later assign instruction locations without
// recognizing whole function bodies.

import gpu_index;
import status;
import tree_walk;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint4> x86_node_tree_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_enclosing_return_node;
StructuredBuffer<uint> x86_return_match_node;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> x86_call_callee_owner_call;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;
StructuredBuffer<uint2> x86_enum_value_record;
StructuredBuffer<uint> x86_enum_record_status;
StructuredBuffer<uint4> x86_match_record;
StructuredBuffer<uint> x86_match_pattern_node_owner;
StructuredBuffer<uint> x86_match_result_value_owner;
StructuredBuffer<uint> x86_struct_access_record;
StructuredBuffer<uint4> x86_struct_store_record;
StructuredBuffer<uint> x86_struct_record_status;

RWStructuredBuffer<uint> x86_node_inst_count_record;
RWStructuredBuffer<uint> x86_node_inst_scan_input;
RWStructuredBuffer<uint> x86_node_inst_count_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_DECL_LAYOUT_OK = 1u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_ERR_NODE_INST_COUNTS = 10u;

static const uint HIR_PARAM = 4u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_STMT = 7u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_PARAM_REG_STRIDE = 5u;
static const uint X86_NODE_INST_COUNT_STRIDE = 3u;
static const uint X86_NODE_INST_COUNT_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_COUNT_COUNT_MASK = 0x0fffffffu;
static const uint X86_INTRINSIC_TAG_MASK = 0x0fu;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;

static const uint ASSIGN_OP_SET = 1u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;

static const uint X86_NODE_INST_NONE = 0u;
static const uint X86_NODE_INST_EXPR_VALUE = 1u;
static const uint X86_NODE_INST_CALL_VALUE = 2u;
static const uint X86_NODE_INST_STMT_VALUE = 3u;
static const uint X86_NODE_INST_BRANCH = 4u;
static const uint X86_NODE_INST_LOOP = 5u;
static const uint X86_NODE_INST_TRANSFER = 6u;
static const uint X86_NODE_INST_PADDING = 7u;
static const uint X86_ENUM_VALUE_CALL_CTOR = 1u;
static const uint X86_ENUM_VALUE_UNIT_CTOR = 2u;
static const uint X86_ENUM_VALUE_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
static const uint X86_AGG_STORE_ARRAY = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint tree_parent_record(uint node)
{
    return x86_node_tree_record[node].x;
}

uint tree_first_child_record(uint node)
{
    return x86_node_tree_record[node].y;
}

uint tree_next_sibling_record(uint node)
{
    return x86_node_tree_record[node].z;
}

uint tree_subtree_end_record(uint node)
{
    return x86_node_tree_record[node].w;
}

public struct X86NodeChildGraph : ITreeChildGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint first_child(uint node)
    {
        return tree_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return tree_next_sibling_record(node);
    }
}

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u &&
           x86_decl_layout_status[0u] == X86_DECL_LAYOUT_OK &&
           x86_decl_layout_status[1u] == 0u &&
           call_record_status[0u] == X86_CALL_RECORDS_OK &&
           call_record_status[1u] == 0u &&
           x86_intrinsic_call_status[0u] == X86_INTRINSIC_CALLS_OK &&
           x86_intrinsic_call_status[1u] == 0u &&
           x86_enum_record_status[0u] == X86_ENUM_RECORDS_OK &&
           x86_enum_record_status[1u] == 0u &&
           x86_struct_record_status[0u] == X86_STRUCT_RECORDS_OK &&
           x86_struct_record_status[1u] == 0u;
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

uint decl_layout_kind(uint row)
{
    uint info = decl_layout_word(row, 2u);
    return info == INVALID ? 0u : info & X86_DECL_LAYOUT_KIND_MASK;
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

uint param_reg_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_param_reg_record,
        decl_token,
        X86_PARAM_REG_STRIDE,
        slot,
        INVALID);
}

uint param_node_decl_token(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;
    uint key = gParams.n_tokens * X86_PARAM_REG_STRIDE + param_node;
    uint decl_token = x86_param_reg_record[key];
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint param_node_reg_word(uint param_node, uint slot)
{
    uint decl_token = param_node_decl_token(param_node);
    return valid_token(decl_token) ? param_reg_word(decl_token, slot) : INVALID;
}

uint param_reg_owner(uint decl_token)
{
    return param_reg_word(decl_token, 0u);
}

uint param_node_reg_owner(uint param_node)
{
    return param_node_reg_word(param_node, 0u);
}

uint param_reg_width(uint decl_token)
{
    return param_reg_word(decl_token, 1u);
}

uint param_node_reg_width(uint param_node)
{
    return param_node_reg_word(param_node, 1u);
}

uint param_reg_link(uint decl_token)
{
    return param_reg_word(decl_token, 4u);
}

uint param_node_reg_link(uint param_node)
{
    return param_node_decl_token(param_node);
}

uint expr_form(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_FORM,
                     0u)
               : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_LEFT,
                     INVALID)
               : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_VALUE_TOKEN,
                     INVALID)
               : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool expression_form_has_value_instr(uint form)
{
    return form == HIR_EXPR_NAME ||
           form == HIR_EXPR_INT ||
           form == HIR_EXPR_TRUE ||
           form == HIR_EXPR_FALSE ||
           form == HIR_EXPR_NOT ||
           form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_NEG ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

bool has_call_record(uint node)
{
    uint4 call = x86_call_record[node];
    return uint4_any_not_equal(call, INVALID);
}

bool has_intrinsic_call_record(uint node)
{
    uint call = x86_intrinsic_call_record[node];
    return call != INVALID && (call & X86_INTRINSIC_TAG_MASK) != 0u;
}

bool has_enum_value_record(uint node)
{
    if (!valid_node(node))
        return false;
    uint2 record = x86_enum_value_record[node];
    uint kind = record.x & X86_ENUM_VALUE_KIND_MASK;
    return kind == X86_ENUM_VALUE_CALL_CTOR || kind == X86_ENUM_VALUE_UNIT_CTOR;
}

uint enum_value_store_count(uint node)
{
    return has_enum_value_record(node) ? 2u : 0u;
}

bool enum_value_node_for_expr(uint expr_node, out uint value_node, out uint width)
{
    value_node = INVALID;
    width = 0u;
    if (!valid_node(expr_node))
        return false;

    uint resolved = resolve_expr(expr_node);
    if (has_enum_value_record(resolved))
    {
        value_node = resolved;
        width = 2u;
        return true;
    }
    if (has_enum_value_record(expr_node))
    {
        value_node = expr_node;
        width = 2u;
        return true;
    }

    return false;
}

bool node_span_contains(uint ancestor, uint node)
{
    if (!valid_node(ancestor) || !valid_node(node))
        return false;
    uint end = tree_subtree_end_record(ancestor);
    return end != INVALID && ancestor <= node && node < end;
}

uint next_sibling_node(uint node)
{
    uint sibling;
    return tree_child_next<X86NodeChildGraph>(node, sibling) ? sibling : INVALID;
}

uint first_child_node(uint node)
{
    uint child;
    return tree_child_first<X86NodeChildGraph>(node, child) ? child : INVALID;
}

uint nth_match_arm_node(uint match_node, uint ordinal)
{
    if (!valid_node(match_node))
        return INVALID;
    uint4 record = x86_match_record[match_node];
    if (ordinal == 0u)
        return record.y;
    if (ordinal == 1u)
        return record.w;
    return INVALID;
}

bool match_expr_is_return_value(uint match_node, out uint return_node)
{
    return_node = INVALID;
    if (!valid_node(match_node))
        return false;
    return_node = x86_match_return_node[match_node];
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return false;
    uint return_expr = stmt_slot(return_node, 1u);
    return node_span_contains(return_expr, match_node);
}

bool supported_return_match(uint match_node)
{
    uint4 record = x86_match_record[match_node];
    uint return_node = INVALID;
    return valid_node(match_node) &&
           hir_kind[match_node] == HIR_MATCH_EXPR &&
           valid_node(record.x) &&
           valid_node(record.y) &&
           record.z == 2u &&
           match_expr_is_return_value(match_node, return_node);
}

uint return_stmt_match_node(uint return_node)
{
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return INVALID;
    uint expr_node = x86_return_match_node[return_node];
    return supported_return_match(expr_node) ? expr_node : INVALID;
}

bool return_stmt_has_supported_match(uint return_node)
{
    return valid_node(return_stmt_match_node(return_node));
}

bool node_belongs_to_match_pattern(uint node)
{
    return valid_node(node) && valid_node(x86_match_pattern_node_owner[node]);
}

bool match_return_arm_value_node(uint node)
{
    return valid_node(node) && valid_node(x86_match_result_value_owner[node]);
}

bool node_precedes_struct_literal(uint node)
{
    uint sibling = next_sibling_node(node);
    return valid_node(sibling) && hir_kind[sibling] == HIR_STRUCT_LITERAL_EXPR;
}

uint array_literal_node_for_expr(uint expr_node)
{
    uint node = resolve_expr(expr_node);
    if (valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR)
        return node;
    return INVALID;
}

uint struct_literal_node_for_expr(uint expr_node)
{
    uint node = resolve_expr(expr_node);
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
        return node;
    if (hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;

    uint sibling = next_sibling_node(node);
    if (valid_node(sibling) && hir_kind[sibling] == HIR_STRUCT_LITERAL_EXPR)
        return sibling;

    uint child = first_child_node(node);
    sibling = next_sibling_node(child);
    return valid_node(sibling) && hir_kind[sibling] == HIR_STRUCT_LITERAL_EXPR ? sibling : INVALID;
}

bool decl_array_len(uint decl_token, out uint len)
{
    len = 0u;
    if (!valid_token(decl_token))
        return false;
    len = decl_layout_width(decl_token);
    return decl_layout_base(decl_token) != INVALID &&
           decl_layout_kind(decl_token) == X86_DECL_AGG_ARRAY &&
           len != 0u;
}

bool decl_aggregate_width(uint decl_token, out uint width)
{
    width = 0u;
    if (valid_token(decl_token))
    {
        uint width_candidate = decl_layout_width(decl_token);
        if (decl_layout_base(decl_token) != INVALID &&
            decl_layout_kind(decl_token) != 0u &&
            width_candidate > 1u)
        {
            width = width_candidate;
            return true;
        }
        uint param_width = param_reg_width(decl_token);
        if (param_reg_owner(decl_token) != INVALID && param_width > 1u)
        {
            width = param_width;
            return true;
        }
    }
    return false;
}

bool decl_is_aggregate(uint decl_token)
{
    uint width = 0u;
    return decl_aggregate_width(decl_token, width);
}

bool name_expr_is_aggregate_local(uint node)
{
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;
    uint name_token = expr_value_token(node);
    if (!valid_token(name_token))
        return false;
    uint decl_token = visible_decl[name_token];
    return decl_is_aggregate(decl_token);
}

bool name_expr_aggregate_width(uint node, out uint width)
{
    width = 0u;
    node = resolve_expr(node);
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;
    uint name_token = expr_value_token(node);
    if (!valid_token(name_token))
        return false;
    uint decl_token = visible_decl[name_token];
    return decl_aggregate_width(decl_token, width);
}

bool scalar_param_decl_node(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return false;
    uint decl_token = param_node_reg_link(node);
    return param_node_reg_owner(node) == x86_node_func[node] &&
           param_node_reg_width(node) == 1u &&
           valid_token(decl_token) &&
           decl_layout_base(decl_token) != INVALID &&
           decl_layout_width(decl_token) == 1u;
}

bool aggregate_let_copy_width(uint node, out uint width)
{
    width = 0u;
    uint stmt_kind = stmt_slot(node, 0u);
    if (!((hir_kind[node] == HIR_LET_STMT && stmt_kind == STMT_RECORD_KIND_LET) ||
          stmt_kind == STMT_RECORD_KIND_CONST))
        return false;

    uint dest_width = 0u;
    if (!decl_aggregate_width(stmt_slot(node, 1u), dest_width) || dest_width <= 1u)
        return false;

    uint source_width = 0u;
    if (!name_expr_aggregate_width(stmt_slot(node, 2u), source_width) ||
        source_width < dest_width)
        return false;

    width = dest_width;
    return true;
}

bool array_literal_width(uint expr_node, out uint width)
{
    width = 0u;
    uint array_node = array_literal_node_for_expr(expr_node);
    if (!valid_node(array_node))
        return false;

    if (struct_access_kind(array_node) != X86_STRUCT_ACCESS_ARRAY_LITERAL)
        return false;
    width = struct_access_payload0(array_node);
    return width > 1u;
}

bool struct_literal_width(uint expr_node, out uint width)
{
    width = 0u;
    uint literal_node = struct_literal_node_for_expr(expr_node);
    if (!valid_node(literal_node))
        return false;
    if (struct_access_kind(literal_node) != X86_STRUCT_ACCESS_LITERAL)
        return false;
    width = struct_access_payload0(literal_node);
    return width > 1u;
}

bool aggregate_return_width(uint return_node, out uint width)
{
    width = 0u;
    uint expr_node = stmt_slot(return_node, 1u);
    if (!valid_node(expr_node))
        return false;
    uint enum_node = INVALID;
    if (enum_value_node_for_expr(expr_node, enum_node, width))
        return true;
    if (struct_literal_width(expr_node, width))
        return true;
    if (array_literal_width(expr_node, width))
        return true;
    return name_expr_aggregate_width(expr_node, width);
}

bool enum_value_belongs_to_aggregate_return(uint node)
{
    uint return_node = valid_node(node) ? x86_enclosing_return_node[node] : INVALID;
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return false;
    uint expr_node = stmt_slot(return_node, 1u);
    return node_span_contains(expr_node, node);
}

bool is_struct_literal_head_node(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return false;

    if (node_precedes_struct_literal(node))
        return true;

    uint child = first_child_node(node);
    return node_precedes_struct_literal(child);
}

bool array_element_store_for_value_node(uint node, out uint decl_token, out uint ordinal)
{
    decl_token = INVALID;
    ordinal = INVALID;

    uint value_node = resolve_expr(node);
    if (!valid_node(value_node))
        return false;

    uint4 record = x86_struct_store_record[value_node];
    decl_token = record.x;
    ordinal = record.y;
    uint len = 0u;
    if (!decl_array_len(decl_token, len))
        return false;

    return record.w == X86_AGG_STORE_ARRAY &&
           valid_node(record.z) &&
           ordinal != INVALID &&
           ordinal < len;
}

bool struct_field_store_for_value_node(uint node, out uint decl_token, out uint ordinal)
{
    decl_token = INVALID;
    ordinal = INVALID;

    uint value_node = resolve_expr(node);
    if (!valid_node(value_node))
        return false;
    uint4 record = x86_struct_store_record[value_node];
    if (record.w != 0u)
        return false;
    decl_token = record.x;
    ordinal = record.y;
    uint width = 0u;
    return valid_token(decl_token) && ordinal != INVALID &&
           decl_aggregate_width(decl_token, width) && ordinal < width;
}

uint aggregate_element_store_count(uint node)
{
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    uint count = 0u;
    if (array_element_store_for_value_node(node, decl_token, ordinal))
        count += 1u;
    if (struct_field_store_for_value_node(node, decl_token, ordinal))
        count += 1u;
    return count;
}

bool is_call_callee_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (x86_call_callee_owner_call[node] != 0u)
        return true;
    uint first_child = x86_node_tree_record[node].y;
    if (valid_node(first_child) && x86_call_callee_owner_call[first_child] != 0u)
        return true;
    uint resolved = resolve_expr(node);
    return valid_node(resolved) && x86_call_callee_owner_call[resolved] != 0u;
}

bool member_field_expr_has_value(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR || is_call_callee_node(node))
        return false;
    return struct_access_kind(node) == X86_STRUCT_ACCESS_MEMBER &&
           valid_node(struct_access_payload0(node)) &&
           struct_access_payload1(node) != INVALID;
}

uint branch_padding_count(uint node)
{
    uint parent = x86_node_tree_record[node].x;
    uint match_padding = 0u;
    if (match_return_arm_value_node(node))
        match_padding += 1u;
    if (!valid_node(parent))
        return match_padding;

    uint parent_kind = hir_kind[parent];
    if (parent_kind == HIR_MATCH_EXPR && supported_return_match(parent))
    {
        uint4 match_record = x86_match_record[parent];
        if (match_record.x == node)
            match_padding += 1u;
    }
    if (parent_kind == HIR_IF_STMT && stmt_slot(parent, 0u) == STMT_RECORD_KIND_IF)
    {
        if (stmt_slot(parent, 1u) == node)
            return match_padding + 1u;
        if (stmt_slot(parent, 2u) == node && valid_node(stmt_slot(parent, 3u)))
            return match_padding + 1u;
    }
    if (parent_kind == HIR_WHILE_STMT && stmt_slot(parent, 0u) == STMT_RECORD_KIND_WHILE)
    {
        if (stmt_slot(parent, 1u) == node)
            return match_padding + 1u;
        if (stmt_slot(parent, 2u) == node)
            return match_padding + 1u;
    }
    if (parent_kind == HIR_FOR_STMT && stmt_slot(parent, 0u) == STMT_RECORD_KIND_FOR)
    {
        if (x86_node_tree_record[parent].y == node)
            return match_padding + 3u;
        if (stmt_slot(parent, 3u) == node)
            return match_padding + 1u;
    }

    return match_padding;
}

void publish_upstream_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_NODE_INST_COUNTS,
        node);
}

void write_count(uint node, uint count, uint kind, uint payload)
{
    if (count > X86_NODE_INST_COUNT_COUNT_MASK)
    {
        publish_stage_error_min_detail4(
            x86_node_inst_count_status,
            X86_ERR_NODE_INST_COUNTS,
            node);
        return;
    }
    row_major_store<uint>(
        x86_node_inst_count_record,
        node,
        X86_NODE_INST_COUNT_STRIDE,
        0u,
        node);
    row_major_store<uint>(
        x86_node_inst_count_record,
        node,
        X86_NODE_INST_COUNT_STRIDE,
        1u,
        (kind << X86_NODE_INST_COUNT_KIND_SHIFT) |
            (count & X86_NODE_INST_COUNT_COUNT_MASK));
    row_major_store<uint>(
        x86_node_inst_count_record,
        node,
        X86_NODE_INST_COUNT_STRIDE,
        2u,
        payload);
    if (count != 0u)
        increment_stage_count4(x86_node_inst_count_status, 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!upstream_ok())
    {
        if (node == 0u)
            publish_upstream_error(node);
        return;
    }

    if (!valid_node(node))
        return;

    uint tree_parent = x86_node_tree_record[node].x;
    if (!valid_node(x86_node_func[node]))
    {
        write_count(node, 0u, X86_NODE_INST_NONE, tree_parent);
        return;
    }

    uint kind = hir_kind[node];
    uint padding = branch_padding_count(node);

    if (scalar_param_decl_node(node))
    {
        write_count(node, 2u + padding, X86_NODE_INST_EXPR_VALUE, tree_parent);
        return;
    }

    if (node_belongs_to_match_pattern(node))
    {
        write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
        return;
    }

    if (kind == HIR_MATCH_EXPR && supported_return_match(node))
    {
        write_count(node, 0u, X86_NODE_INST_BRANCH, x86_match_record[node].x);
        return;
    }

    if (kind == HIR_CALL_EXPR && has_enum_value_record(node))
    {
        if (enum_value_belongs_to_aggregate_return(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        write_count(node, enum_value_store_count(node) + padding, X86_NODE_INST_CALL_VALUE, tree_parent);
        return;
    }

    if (kind == HIR_CALL_EXPR && (has_call_record(node) || has_intrinsic_call_record(node)))
    {
        uint extra_store = aggregate_element_store_count(node);
        uint payload_row = has_call_record(node) ? 1u : 0u;
        write_count(node, 1u + payload_row + extra_store + padding, X86_NODE_INST_CALL_VALUE, tree_parent);
        return;
    }

    if (stmt_slot(node, 0u) == STMT_RECORD_KIND_RETURN)
    {
        if (return_stmt_has_supported_match(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        uint return_width = 0u;
        uint transfer_count = aggregate_return_width(node, return_width) ? return_width + 1u : 1u;
        write_count(node, transfer_count + padding, X86_NODE_INST_TRANSFER, stmt_slot(node, 1u));
        return;
    }

    if (kind == HIR_IF_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_IF)
    {
        write_count(node, 0u, X86_NODE_INST_BRANCH, stmt_slot(node, 1u));
        return;
    }

    if (kind == HIR_WHILE_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_WHILE)
    {
        write_count(node, 0u, X86_NODE_INST_LOOP, stmt_slot(node, 1u));
        return;
    }

    if ((kind == HIR_FOR_STMT || kind == HIR_STMT) && stmt_slot(node, 0u) == STMT_RECORD_KIND_FOR)
    {
        write_count(node, padding, X86_NODE_INST_LOOP, stmt_slot(node, 2u));
        return;
    }

    if ((kind == HIR_LET_STMT || kind == HIR_STMT) &&
        (stmt_slot(node, 0u) == STMT_RECORD_KIND_LET ||
         stmt_slot(node, 0u) == STMT_RECORD_KIND_CONST))
    {
        uint copy_width = 0u;
        if (aggregate_let_copy_width(node, copy_width))
        {
            write_count(node, copy_width * 2u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
            return;
        }

        if (decl_is_aggregate(stmt_slot(node, 1u)))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        write_count(node, 1u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
        return;
    }

    if (kind == HIR_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
    {
        uint op = stmt_slot(node, 3u);
        uint count = op == ASSIGN_OP_SET ? 1u : 3u;
        write_count(node, count + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
        return;
    }

    if (kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT)
    {
        write_count(node, 1u + padding, X86_NODE_INST_TRANSFER, tree_parent);
        return;
    }

    if (kind == HIR_INDEX_EXPR)
    {
        uint extra_store = aggregate_element_store_count(node);
        write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, tree_parent);
        return;
    }

    if (kind == HIR_MEMBER_EXPR)
    {
        if (member_field_expr_has_value(node))
        {
            uint extra_store = aggregate_element_store_count(node);
            write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, tree_parent);
            return;
        }
        write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
        return;
    }

    uint form = expr_form(node);
    if ((kind == HIR_ASSIGN_EXPR ||
         kind == HIR_BINARY_EXPR ||
         kind == HIR_UNARY_EXPR ||
         kind == HIR_NAME_EXPR ||
         kind == HIR_LITERAL_EXPR) &&
        expression_form_has_value_instr(form))
    {
        if (kind == HIR_NAME_EXPR && has_enum_value_record(node))
        {
            if (enum_value_belongs_to_aggregate_return(node))
            {
                write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
                return;
            }
            write_count(node, enum_value_store_count(node) + padding, X86_NODE_INST_EXPR_VALUE, tree_parent);
            return;
        }
        if (is_call_callee_node(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        if (is_struct_literal_head_node(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        if (name_expr_is_aggregate_local(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        uint extra_store = aggregate_element_store_count(node);
        write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, form);
        return;
    }

    if (padding != 0u)
    {
        write_count(node, padding, X86_NODE_INST_PADDING, tree_parent);
        return;
    }

    write_count(node, 0u, X86_NODE_INST_NONE, tree_parent);
}
