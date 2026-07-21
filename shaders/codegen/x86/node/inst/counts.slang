// x86_64 node-local virtual instruction counts.
//
// This pass is the backend counterpart of Pareas' instruction-count stage:
// each attributed HIR node receives a local virtual instruction count. Prefix
// sums over these rows can later assign instruction locations without
// recognizing whole function bodies.

import gpu_index;
import status;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> x86_struct_field_width_by_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> x86_struct_type_record;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint2> x86_const_value_record;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_for_iterable_node;
StructuredBuffer<uint> x86_node_control_padding;
StructuredBuffer<uint> x86_postfix_operand_owner;
StructuredBuffer<uint> x86_enclosing_return_node;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> x86_call_callee_root_call;
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
StructuredBuffer<uint> x86_aggregate_source_node;
StructuredBuffer<uint> x86_aggregate_source_offset;
StructuredBuffer<uint4> x86_struct_store_record;
StructuredBuffer<uint> x86_struct_record_status;

RWStructuredBuffer<uint> x86_node_inst_count_info;
RWStructuredBuffer<uint> x86_node_inst_count_payload;
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
static const uint X86_ERR_POSTFIX_EXPR = 30u;
static const uint X86_ERR_FOR_ITERABLE = 33u;
static const uint X86_ERR_UNSUPPORTED_UNARY_EXPR = 39u;
static const uint X86_ERR_UNSUPPORTED_MATCH_EXPR = 44u;
static const uint X86_ERR_AGGREGATE_TEMPORARY_MEMBER = 46u;
static const uint X86_ERR_UNSUPPORTED_LITERAL_EXPR = 60u;
static const uint X86_ERR_NESTED_AGGREGATE_MEMBER = 61u;
static const uint X86_FEATURE_ENUM = 1u << 0u;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint X86_FEATURE_AGGREGATE = 1u << 2u;

static const uint HIR_FN = 3u;
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
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_DECL_AGG_STRING = 4u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_PARAM_REG_KIND_BITS = 4u;
static const uint X86_NODE_INST_COUNT_STRIDE = 2u;
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
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NONE = 0u;
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
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_CHAR = 29u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint X86_CONST_VALUE_LITERAL = 1u;

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
static const uint X86_ENUM_VALUE_KIND_BITS = 4u;
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

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool has_enum_feature()
{
    return (gX86Features.mask & X86_FEATURE_ENUM) != 0u;
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

bool has_aggregate_feature()
{
    return (gX86Features.mask & X86_FEATURE_AGGREGATE) != 0u;
}

uint control_role_padding(uint node)
{
    return valid_node(node) ? x86_node_control_padding[node] : 0u;
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

bool node_is_stmt_kind(uint node, uint stmt_kind)
{
    if (!valid_node(node))
        return false;
    uint kind = hir_kind[node];
    return (kind == HIR_STMT ||
            (stmt_kind == STMT_RECORD_KIND_IF && kind == HIR_IF_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_WHILE && kind == HIR_WHILE_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_FOR && kind == HIR_FOR_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_LET && kind == HIR_LET_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_RETURN && kind == HIR_RETURN_STMT)) &&
           stmt_slot(node, 0u) == stmt_kind;
}

bool compiled_function_node(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_FN &&
           x86_node_func[node] == node;
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
    if (!has_aggregate_feature())
        return INVALID;
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

uint struct_access_payload2(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? INVALID : info >> X86_STRUCT_ACCESS_KIND_BITS;
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
    uint dense = raw_to_compact_hir[param_node];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense >= count || compact_hir_core[dense].kind != HIR_PARAM)
        return INVALID;
    // Parameter payloads are { owner, ordinal, name_token, type_node }.
    uint decl_token = compact_hir_payload[dense].c;
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

uint param_reg_info(uint decl_token)
{
    return param_reg_word(decl_token, 2u);
}

uint param_reg_arg_reg(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID
               ? INVALID
               : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint param_reg_aggregate_kind(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID ? 0u : info >> X86_PARAM_REG_KIND_BITS;
}

uint param_reg_link(uint decl_token)
{
    return param_reg_word(decl_token, 5u);
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

uint expr_right(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_RIGHT,
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

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : resolve_expr(node);
}

bool path_literal_value_candidate(uint node)
{
    if (!valid_node(node))
        return false;

    uint dense = raw_to_compact_hir[node];
    uint path_i = dense < gParams.n_hir_nodes
                      ? path_id_by_owner_hir[dense]
                      : INVALID;
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return false;

    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return false;

    uint decl_token = decl_name_token[decl_i];
    if (!valid_token(decl_token))
        return false;

    return x86_const_value_record[decl_token].x == X86_CONST_VALUE_LITERAL;
}

bool path_literal_value_node(uint node)
{
    if (path_literal_value_candidate(node))
        return true;

    uint resolved = resolve_expr(node);
    if (resolved != node && path_literal_value_candidate(resolved))
        return true;

    uint root = expr_result_root(node);
    return root != node && root != resolved && path_literal_value_candidate(root);
}

bool expression_form_has_value_instr(uint form)
{
    return form == HIR_EXPR_NAME ||
           form == HIR_EXPR_INT ||
           form == HIR_EXPR_FLOAT ||
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

uint direct_call_payload_rows(uint node)
{
    if (!has_call_record(node))
        return 0u;
    return 2u;
}

bool enum_value_record_is_supported(uint2 record)
{
    if (record.x == INVALID || record.y == INVALID)
        return false;

    uint kind = record.x & X86_ENUM_VALUE_KIND_MASK;
    uint payload_count = record.x >> X86_ENUM_VALUE_KIND_BITS;
    return (kind == X86_ENUM_VALUE_UNIT_CTOR && payload_count == 0u) ||
           (kind == X86_ENUM_VALUE_CALL_CTOR && payload_count == 1u);
}

bool has_enum_value_record(uint node)
{
    if (!has_enum_feature() || !valid_node(node))
        return false;
    return enum_value_record_is_supported(x86_enum_value_record[node]);
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

bool match_expr_is_return_value(uint match_node, out uint return_node)
{
    return_node = INVALID;
    if (!valid_node(match_node))
        return false;
    return_node = x86_match_return_node[match_node];
    return valid_node(return_node) && stmt_slot(return_node, 0u) == STMT_RECORD_KIND_RETURN;
}

bool supported_return_match(uint match_node)
{
    if (!has_match_feature() || !valid_node(match_node))
        return false;
    uint4 record = x86_match_record[match_node];
    uint return_node = INVALID;
    return hir_kind[match_node] == HIR_MATCH_EXPR &&
           valid_node(record.x) &&
           record.y != INVALID &&
           record.z == 2u &&
           match_expr_is_return_value(match_node, return_node);
}

uint return_stmt_match_node(uint return_node)
{
    if (!has_match_feature())
        return INVALID;
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return INVALID;
    uint return_expr = stmt_slot(return_node, 1u);
    uint expr_node = resolve_expr(return_expr);
    return supported_return_match(expr_node) ? expr_node : INVALID;
}

bool return_stmt_has_supported_match(uint return_node)
{
    return valid_node(return_stmt_match_node(return_node));
}

bool node_belongs_to_match_pattern(uint node)
{
    return has_match_feature() && valid_node(node) &&
           valid_node(x86_match_pattern_node_owner[node]);
}

bool match_return_arm_value_node(uint node)
{
    return has_match_feature() && valid_node(node) &&
           valid_node(x86_match_result_value_owner[node]);
}

uint array_literal_node_for_expr(uint expr_node)
{
    uint node = expr_result_root(expr_node);
    if (valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR)
        return node;
    return INVALID;
}

uint struct_literal_record_node_for_expr(uint expr_node)
{
    if (valid_node(expr_node) && struct_access_kind(expr_node) == X86_STRUCT_ACCESS_LITERAL)
        return expr_node;
    uint resolved = resolve_expr(expr_node);
    if (valid_node(resolved) && struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL)
        return resolved;
    uint root = expr_result_root(expr_node);
    if (valid_node(root) && struct_access_kind(root) == X86_STRUCT_ACCESS_LITERAL)
        return root;
    uint parent = valid_node(expr_node) ? x86_tree_parent[expr_node] : INVALID;
    if (valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        return parent;
    parent = valid_node(resolved) ? x86_tree_parent[resolved] : INVALID;
    if (valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        return parent;
    parent = valid_node(root) ? x86_tree_parent[root] : INVALID;
    return valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL
        ? parent
        : INVALID;
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

uint for_element_width(uint node)
{
    if (!node_is_stmt_kind(node, STMT_RECORD_KIND_FOR))
        return 1u;
    uint decl_token = stmt_slot(node, 1u);
    uint width = decl_layout_width(decl_token);
    return width == INVALID || width == 0u ? 1u : width;
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

bool decl_storage_aggregate_width(uint decl_token, out uint width)
{
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint width_candidate = decl_layout_width(decl_token);
    if (decl_layout_base(decl_token) != INVALID &&
        decl_layout_kind(decl_token) != 0u &&
        width_candidate > 0u)
    {
        width = width_candidate;
        return true;
    }

    uint param_width = param_reg_width(decl_token);
    if (param_reg_owner(decl_token) != INVALID &&
        param_reg_aggregate_kind(decl_token) != 0u &&
        param_width > 0u)
    {
        width = param_width;
        return true;
    }
    return false;
}

bool decl_is_aggregate(uint decl_token)
{
    uint width = 0u;
    return decl_aggregate_width(decl_token, width);
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

bool for_iterable_has_array_layout(uint node)
{
    if (!node_is_stmt_kind(node, STMT_RECORD_KIND_FOR))
        return false;

    uint iterable_node = x86_for_iterable_node[node];
    if (!valid_node(iterable_node))
        return false;

    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(iterable_node, decl_token))
        return false;
    uint element_width = for_element_width(node);
    if (element_width == 0u)
        return false;
    if (decl_layout_base(decl_token) != INVALID &&
        decl_layout_kind(decl_token) == X86_DECL_AGG_ARRAY &&
        decl_layout_width(decl_token) != 0u &&
        decl_layout_width(decl_token) % element_width == 0u)
        return true;
    return param_reg_owner(decl_token) == x86_node_func[node] &&
           param_reg_arg_reg(decl_token) != INVALID &&
           param_reg_aggregate_kind(decl_token) == X86_DECL_AGG_ARRAY &&
           param_reg_width(decl_token) != 0u &&
           param_reg_width(decl_token) % element_width == 0u;
}

bool for_iterable_has_numeric_range_layout(uint node)
{
    if (!node_is_stmt_kind(node, STMT_RECORD_KIND_FOR))
        return false;

    uint iterable_node = x86_for_iterable_node[node];
    if (!valid_node(iterable_node) ||
        hir_kind[iterable_node] != HIR_EXPR ||
        expr_form(iterable_node) != HIR_EXPR_RANGE)
        return false;

    return valid_node(expr_left(iterable_node)) &&
           valid_node(expr_right(iterable_node));
}

bool for_iterable_has_local_range_aggregate_layout(uint node)
{
    if (!node_is_stmt_kind(node, STMT_RECORD_KIND_FOR) || for_element_width(node) != 1u)
        return false;

    uint iterable_node = x86_for_iterable_node[node];
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(iterable_node, decl_token))
        return false;

    return decl_layout_base(decl_token) != INVALID &&
           decl_layout_kind(decl_token) != 0u &&
           decl_layout_kind(decl_token) != X86_DECL_AGG_ARRAY &&
           decl_layout_width(decl_token) == 2u;
}

bool for_iterable_has_supported_layout(uint node)
{
    return for_iterable_has_array_layout(node) ||
           for_iterable_has_numeric_range_layout(node) ||
           for_iterable_has_local_range_aggregate_layout(node);
}

bool name_expr_is_aggregate_local(uint node)
{
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(node, decl_token))
        return false;
    return decl_is_aggregate(decl_token);
}

bool scalar_name_expr_has_value_instr(uint node)
{
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(node, decl_token))
        return false;
    if (!valid_token(decl_token) || decl_is_aggregate(decl_token))
        return false;

    if (decl_layout_base(decl_token) != INVALID &&
        decl_layout_width(decl_token) == 1u)
        return true;

    return param_reg_owner(decl_token) == x86_node_func[node] &&
           param_reg_arg_reg(decl_token) != INVALID &&
           param_reg_width(decl_token) == 1u;
}

bool name_expr_aggregate_width(uint node, out uint width)
{
    width = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(node, decl_token))
        return false;
    return decl_aggregate_width(decl_token, width);
}

bool name_expr_storage_aggregate_width(uint node, out uint width)
{
    width = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(node, decl_token))
        return false;
    return decl_storage_aggregate_width(decl_token, width);
}

bool member_aggregate_width(uint member_token, out uint width)
{
    width = 0u;
    if (!valid_token(member_token))
        return false;
    uint field_token = member_result_field_node[member_token];
    uint field_node = valid_token(field_token)
                          ? x86_decl_node_by_token[field_token]
                          : INVALID;
    if (!valid_node(field_node))
        return false;
    width = x86_struct_field_width_by_node[field_node];
    return width > 1u;
}

bool aggregate_storage_source_width(uint node, out uint width)
{
    width = 0u;
    if (!valid_node(node))
        return false;
    uint current = x86_aggregate_source_node[node];
    uint offset = x86_aggregate_source_offset[node];
    uint selected_width = 0u;
    uint first = resolve_expr(node);
    if (valid_node(first) &&
        hir_kind[first] == HIR_MEMBER_EXPR &&
        struct_access_kind(first) == X86_STRUCT_ACCESS_MEMBER)
    {
        uint member_token = struct_access_payload2(first);
        if (!valid_token(member_token) ||
            !member_aggregate_width(member_token, selected_width))
            return false;
    }

    if (!valid_node(current) || expr_form(current) != HIR_EXPR_NAME)
        return false;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(current, decl_token))
        return false;
    uint source_width = 0u;
    if (!decl_storage_aggregate_width(decl_token, source_width))
        return false;
    if (selected_width == 0u)
    {
        width = source_width;
        return true;
    }
    if (offset > source_width || selected_width > source_width - offset)
        return false;
    width = selected_width;
    return true;
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
    if (!((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
          (stmt_kind == STMT_RECORD_KIND_LET ||
           stmt_kind == STMT_RECORD_KIND_CONST)))
        return false;

    uint dest_width = 0u;
    if (!decl_aggregate_width(stmt_slot(node, 1u), dest_width) || dest_width <= 1u)
        return false;

    uint source_width = 0u;
    if (!aggregate_storage_source_width(stmt_slot(node, 2u), source_width) ||
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
    uint record_node = struct_literal_record_node_for_expr(expr_node);
    if (!valid_node(record_node))
        return false;
    width = struct_access_payload0(record_node);
    return width > 1u;
}

bool struct_literal_storage_width(uint expr_node, out uint width)
{
    width = 0u;
    uint record_node = struct_literal_record_node_for_expr(expr_node);
    if (!valid_node(record_node))
        return false;
    width = struct_access_payload0(record_node);
    return width > 0u;
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
    return aggregate_storage_source_width(expr_node, width);
}

bool enum_value_belongs_to_aggregate_return(uint node)
{
    uint return_node = valid_node(node) ? x86_enclosing_return_node[node] : INVALID;
    return valid_node(return_node) && stmt_slot(return_node, 0u) == STMT_RECORD_KIND_RETURN;
}

bool is_struct_literal_head_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (struct_access_kind(node) == X86_STRUCT_ACCESS_LITERAL)
        return true;
    uint resolved = resolve_expr(node);
    return valid_node(resolved) && struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL;
}

bool is_struct_literal_head_or_path_child(uint node)
{
    if (is_struct_literal_head_node(node))
        return true;
    uint token = expr_value_token(node);
    if (valid_token(token) && x86_struct_type_record[token] != 0u)
        return true;
    return false;
}

bool array_element_store_for_value_node(uint node, out uint decl_token, out uint ordinal)
{
    decl_token = INVALID;
    ordinal = INVALID;

    if (!has_aggregate_feature() || !valid_node(node))
        return false;

    uint4 record = x86_struct_store_record[node];
    if (record.x == INVALID || record.y == INVALID)
    {
        uint value_node = resolve_expr(node);
        if (!valid_node(value_node))
            return false;
        record = x86_struct_store_record[value_node];
    }
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

    if (!has_aggregate_feature() || !valid_node(node))
        return false;
    uint4 record = x86_struct_store_record[node];
    if (record.x == INVALID || record.y == INVALID)
    {
        uint value_node = resolve_expr(node);
        if (!valid_node(value_node))
            return false;
        record = x86_struct_store_record[value_node];
    }
    if (record.w != 0u)
        return false;
    decl_token = record.x;
    ordinal = record.y;
    uint width = 0u;
    return valid_token(decl_token) && ordinal != INVALID &&
           decl_storage_aggregate_width(decl_token, width) && ordinal < width;
}

bool struct_field_aggregate_copy_width(uint node, out uint width)
{
    width = 0u;
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    if (!struct_field_store_for_value_node(node, decl_token, ordinal))
        return false;

    uint dest_width = 0u;
    if (!decl_storage_aggregate_width(decl_token, dest_width) ||
        ordinal >= dest_width)
        return false;

    uint source_node = resolve_expr(node);
    if (!valid_node(source_node))
        source_node = node;

    uint source_width = 0u;
    if (!aggregate_storage_source_width(source_node, source_width) ||
        source_width <= 1u)
        return false;

    width = min(source_width, dest_width - ordinal);
    return width > 1u;
}

uint aggregate_element_store_count(uint node)
{
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    uint count = 0u;
    if (array_element_store_for_value_node(node, decl_token, ordinal))
        count += 1u;
    uint copy_width = 0u;
    if (struct_field_store_for_value_node(node, decl_token, ordinal) &&
        !struct_field_aggregate_copy_width(node, copy_width))
        count += 1u;
    return count;
}

bool storage_aggregate_literal_initializer_stores_to_local(uint node)
{
    uint stmt_kind = stmt_slot(node, 0u);
    if (!((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
          (stmt_kind == STMT_RECORD_KIND_LET ||
           stmt_kind == STMT_RECORD_KIND_CONST)))
        return false;

    uint dest_width = 0u;
    if (!decl_storage_aggregate_width(stmt_slot(node, 1u), dest_width))
        return false;

    uint init_width = 0u;
    return struct_literal_storage_width(stmt_slot(node, 2u), init_width) &&
           init_width == dest_width;
}

bool is_call_callee_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (x86_call_callee_root_call[node] != 0u)
        return true;
    if (x86_call_callee_owner_call[node] != 0u)
        return true;
    uint resolved = resolve_expr(node);
    return valid_node(resolved) &&
           (x86_call_callee_root_call[resolved] != 0u ||
            x86_call_callee_owner_call[resolved] != 0u);
}

bool member_receiver_has_supported_aggregate_source(uint member_node)
{
    if (!valid_node(member_node) || struct_access_kind(member_node) != X86_STRUCT_ACCESS_MEMBER)
        return false;

    uint receiver_node = struct_access_payload0(member_node);
    uint ordinal = struct_access_payload1(member_node);
    uint width = 0u;
    return valid_node(receiver_node) &&
           ordinal != INVALID &&
           aggregate_storage_source_width(receiver_node, width) &&
           ordinal < width;
}

bool assignment_target_param_aggregate_member(uint target_node)
{
    uint member_node = resolve_expr(target_node);
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        member_node = target_node;
    if (!valid_node(member_node) ||
        struct_access_kind(member_node) != X86_STRUCT_ACCESS_MEMBER ||
        !valid_node(struct_access_payload0(member_node)) ||
        struct_access_payload1(member_node) == INVALID)
        return false;

    uint receiver = resolve_expr(struct_access_payload0(member_node));
    if (!valid_node(receiver) || expr_form(receiver) != HIR_EXPR_NAME)
        return false;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(receiver, decl_token))
        return false;
    uint width = param_reg_width(decl_token);
    return param_reg_owner(decl_token) == x86_node_func[member_node] &&
           param_reg_arg_reg(decl_token) != INVALID &&
           width > 1u &&
           struct_access_payload1(member_node) < width;
}

bool member_field_expr_has_value(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR || is_call_callee_node(node))
        return false;
    return member_receiver_has_supported_aggregate_source(node);
}

bool unsupported_aggregate_temporary_member(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR || is_call_callee_node(node))
        return false;
    if (struct_access_kind(node) != X86_STRUCT_ACCESS_MEMBER ||
        !valid_node(struct_access_payload0(node)) ||
        struct_access_payload1(node) == INVALID)
        return false;
    return !member_receiver_has_supported_aggregate_source(node);
}

bool unsupported_nested_aggregate_member(uint node)
{
    if (!unsupported_aggregate_temporary_member(node))
        return false;

    uint receiver = struct_access_payload0(node);
    uint resolved_receiver = valid_node(receiver) ? resolve_expr(receiver) : INVALID;
    return (valid_node(receiver) && hir_kind[receiver] == HIR_MEMBER_EXPR) ||
           (valid_node(resolved_receiver) && hir_kind[resolved_receiver] == HIR_MEMBER_EXPR);
}

uint aggregate_temporary_member_detail(uint member_node)
{
    uint receiver = valid_node(member_node) ? struct_access_payload0(member_node) : INVALID;
    uint resolved = valid_node(receiver) ? resolve_expr(receiver) : INVALID;
    if (valid_node(resolved))
        return resolved;
    if (valid_node(receiver))
        return receiver;
    return member_node;
}

void publish_aggregate_temporary_member_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_AGGREGATE_TEMPORARY_MEMBER,
        aggregate_temporary_member_detail(node));
}

void publish_nested_aggregate_member_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_NESTED_AGGREGATE_MEMBER,
        aggregate_temporary_member_detail(node));
}

uint branch_padding_count(uint node)
{
    return control_role_padding(node);
}

uint upstream_error_code()
{
    if (x86_node_tree_status[1u] != 0u)
        return x86_node_tree_status[1u];
    if (x86_decl_layout_status[1u] != 0u)
        return x86_decl_layout_status[1u];
    if (call_record_status[1u] != 0u)
        return call_record_status[1u];
    if (x86_intrinsic_call_status[1u] != 0u)
        return x86_intrinsic_call_status[1u];
    if (x86_enum_record_status[1u] != 0u)
        return x86_enum_record_status[1u];
    if (x86_struct_record_status[1u] != 0u)
        return x86_struct_record_status[1u];
    return X86_ERR_NODE_INST_COUNTS;
}

uint upstream_error_detail()
{
    if (x86_node_tree_status[1u] != 0u)
        return x86_node_tree_status[2u];
    if (x86_decl_layout_status[1u] != 0u)
        return x86_decl_layout_status[2u];
    if (call_record_status[1u] != 0u)
        return call_record_status[2u];
    if (x86_intrinsic_call_status[1u] != 0u)
        return x86_intrinsic_call_status[2u];
    if (x86_enum_record_status[1u] != 0u)
        return x86_enum_record_status[2u];
    if (x86_struct_record_status[1u] != 0u)
        return x86_struct_record_status[2u];
    return 0u;
}

void publish_upstream_error()
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        upstream_error_code(),
        upstream_error_detail());
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
    x86_node_inst_count_info[node] =
        (kind << X86_NODE_INST_COUNT_KIND_SHIFT) |
        (count & X86_NODE_INST_COUNT_COUNT_MASK);
    x86_node_inst_count_payload[node] = payload;
    if (count != 0u)
        increment_stage_count4(x86_node_inst_count_status, 1u);
}

uint postfix_diagnostic_node(uint node)
{
    uint resolved = resolve_expr(node);
    if (valid_node(resolved))
        return resolved;
    return node;
}

bool postfix_expr_is_incdec(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_POSTFIX_EXPR)
        return false;
    uint resolved = resolve_expr(node);
    return valid_node(resolved) && hir_kind[resolved] == HIR_UNARY_EXPR;
}

void publish_postfix_expr_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_POSTFIX_EXPR,
        postfix_diagnostic_node(node));
}

bool unsupported_unary_expr(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_UNARY_EXPR &&
           expr_form(node) == HIR_EXPR_NONE &&
           !valid_node(x86_postfix_operand_owner[node]);
}

void publish_unsupported_unary_expr_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_UNSUPPORTED_UNARY_EXPR,
        node);
}

bool unsupported_literal_expr(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = hir_kind[node];
    if (kind != HIR_LITERAL_EXPR)
        return false;
    uint form = expr_form(node);
    return form == HIR_EXPR_CHAR;
}

bool string_literal_initializer_stores_to_local(uint node)
{
    if (!valid_node(node) ||
        !(node_is_stmt_kind(node, STMT_RECORD_KIND_LET) ||
          (hir_kind[node] == HIR_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_CONST)))
        return false;

    uint decl_token = stmt_slot(node, 1u);
    if (!valid_token(decl_token) ||
        decl_layout_base(decl_token) == INVALID ||
        decl_layout_width(decl_token) < 2u)
        return false;

    uint init_node = resolve_expr(stmt_slot(node, 2u));
    return valid_node(init_node) &&
           hir_kind[init_node] == HIR_LITERAL_EXPR &&
           expr_form(init_node) == HIR_EXPR_STRING;
}

void publish_unsupported_literal_expr_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_UNSUPPORTED_LITERAL_EXPR,
        node);
}

void publish_unsupported_match_expr_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_UNSUPPORTED_MATCH_EXPR,
        node);
}

void publish_for_iterable_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_node_inst_count_status,
        X86_ERR_FOR_ITERABLE,
        node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!upstream_ok())
    {
        if (node == 0u)
            publish_upstream_error();
        return;
    }

    if (!valid_node(node))
        return;

    if (!valid_node(x86_node_func[node]))
    {
        write_count(node, 0u, X86_NODE_INST_NONE, INVALID);
        return;
    }

    uint kind = hir_kind[node];
    uint padding = branch_padding_count(node);

    if (postfix_expr_is_incdec(node))
    {
        publish_postfix_expr_error(node);
        return;
    }

    if (unsupported_unary_expr(node))
    {
        publish_unsupported_unary_expr_error(node);
        return;
    }

    if (unsupported_literal_expr(node))
    {
        publish_unsupported_literal_expr_error(node);
        return;
    }

    if (unsupported_nested_aggregate_member(node))
    {
        publish_nested_aggregate_member_error(node);
        return;
    }

    if (unsupported_aggregate_temporary_member(node))
    {
        publish_aggregate_temporary_member_error(node);
        return;
    }

    if (scalar_param_decl_node(node))
    {
        write_count(node, 2u + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
        return;
    }

    if (node_belongs_to_match_pattern(node))
    {
        write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
        return;
    }

    if (compiled_function_node(node))
    {
        write_count(node, 2u + padding, X86_NODE_INST_TRANSFER, INVALID);
        return;
    }

    if (kind == HIR_MATCH_EXPR && supported_return_match(node))
    {
        write_count(node, 0u, X86_NODE_INST_BRANCH, x86_match_record[node].x);
        return;
    }

    if (kind == HIR_MATCH_EXPR && has_match_feature())
    {
        publish_unsupported_match_expr_error(node);
        return;
    }

    if (kind == HIR_CALL_EXPR && has_enum_value_record(node))
    {
        if (enum_value_belongs_to_aggregate_return(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        write_count(node, enum_value_store_count(node) + padding, X86_NODE_INST_CALL_VALUE, INVALID);
        return;
    }

    uint field_copy_width = 0u;
    if (struct_field_aggregate_copy_width(node, field_copy_width))
    {
        write_count(node, field_copy_width * 2u + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
        return;
    }

    if (kind == HIR_CALL_EXPR && (has_call_record(node) || has_intrinsic_call_record(node)))
    {
        uint extra_store = aggregate_element_store_count(node);
        uint payload_rows = direct_call_payload_rows(node);
        write_count(node, 1u + payload_rows + extra_store + padding, X86_NODE_INST_CALL_VALUE, INVALID);
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_RETURN))
    {
        if (return_stmt_has_supported_match(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        if (!valid_node(stmt_slot(node, 1u)))
        {
            write_count(node, 2u + padding, X86_NODE_INST_TRANSFER, INVALID);
            return;
        }
        uint return_width = 0u;
        aggregate_return_width(node, return_width);
        uint transfer_count = return_width > 0u ? return_width + 1u : 1u;
        write_count(node, transfer_count + padding, X86_NODE_INST_TRANSFER, stmt_slot(node, 1u));
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_IF))
    {
        write_count(node, 0u, X86_NODE_INST_BRANCH, stmt_slot(node, 1u));
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_WHILE))
    {
        write_count(node, 0u, X86_NODE_INST_LOOP, stmt_slot(node, 1u));
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_FOR))
    {
        if (!for_iterable_has_supported_layout(node))
        {
            publish_for_iterable_error(node);
            return;
        }
        write_count(node, padding, X86_NODE_INST_LOOP, stmt_slot(node, 2u));
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_LET) ||
        (kind == HIR_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_CONST))
    {
        uint copy_width = 0u;
        if (aggregate_let_copy_width(node, copy_width))
        {
            write_count(node, copy_width * 2u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
            return;
        }

        if (string_literal_initializer_stores_to_local(node))
        {
            write_count(node, 2u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
            return;
        }

        if (decl_is_aggregate(stmt_slot(node, 1u)))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        if (storage_aggregate_literal_initializer_stores_to_local(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        write_count(node, 1u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
        return;
    }

    if (kind == HIR_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
    {
        uint op = stmt_slot(node, 3u);
        uint count = assignment_target_param_aggregate_member(stmt_slot(node, 1u))
                         ? (op == ASSIGN_OP_SET ? 2u : 4u)
                         : (op == ASSIGN_OP_SET ? 1u : 3u);
        write_count(node, count + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
        return;
    }

    if (kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT)
    {
        write_count(node, 1u + padding, X86_NODE_INST_TRANSFER, INVALID);
        return;
    }

    if (kind == HIR_INDEX_EXPR)
    {
        uint extra_store = aggregate_element_store_count(node);
        write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
        return;
    }

    if (kind == HIR_MEMBER_EXPR)
    {
        if (member_field_expr_has_value(node))
        {
            uint extra_store = aggregate_element_store_count(node);
            write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
            return;
        }
        write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
        return;
    }

    if (kind == HIR_PATH_EXPR && !is_call_callee_node(node) && path_literal_value_node(node))
    {
        uint extra_store = aggregate_element_store_count(node);
        write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
        return;
    }

    uint form = expr_form(node);
    uint extra_store = aggregate_element_store_count(node);
    if (extra_store == 0u && is_struct_literal_head_or_path_child(node))
    {
        write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
        return;
    }
    bool expression_value_node =
        kind == HIR_ASSIGN_EXPR ||
        kind == HIR_BINARY_EXPR ||
        kind == HIR_UNARY_EXPR ||
        kind == HIR_NAME_EXPR ||
        kind == HIR_LITERAL_EXPR ||
        (kind == HIR_POSTFIX_EXPR && extra_store != 0u) ||
        (kind == HIR_EXPR && extra_store != 0u);
    if (expression_value_node &&
        expression_form_has_value_instr(form))
    {
        if (kind == HIR_NAME_EXPR && has_enum_value_record(node))
        {
            if (enum_value_belongs_to_aggregate_return(node))
            {
                write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
                return;
            }
            write_count(node, enum_value_store_count(node) + padding, X86_NODE_INST_EXPR_VALUE, INVALID);
            return;
        }
        if (is_call_callee_node(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        if (name_expr_is_aggregate_local(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, INVALID);
            return;
        }
        write_count(node, 1u + extra_store + padding, X86_NODE_INST_EXPR_VALUE, form);
        return;
    }

    if (padding != 0u)
    {
        write_count(node, padding, X86_NODE_INST_PADDING, INVALID);
        return;
    }

    write_count(node, 0u, X86_NODE_INST_NONE, INVALID);
}
