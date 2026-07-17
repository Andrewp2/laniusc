import generated_parse_production_ids;
import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> canonical_prefix_before_raw;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> parent_value;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_item_namespace;
StructuredBuffer<uint> hir_item_visibility;
StructuredBuffer<uint> hir_item_import_target_kind;
StructuredBuffer<uint> hir_method_name_token;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> hir_type_alias_target_node;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_match_scrutinee_node;
RWStructuredBuffer<HirCore> hir_core;
RWStructuredBuffer<HirLinks> hir_links;
RWStructuredBuffer<HirPayload> hir_payload;
RWStructuredBuffer<uint> hir_canonical_fn_return_type;
RWStructuredBuffer<uint> hir_canonical_type_alias_target;
RWStructuredBuffer<uint> hir_canonical_const_type;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_CONST = 4u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint STMT_FOR = 7u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_FILE = 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_IMPL = 35u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
bool valid_raw(uint raw) { return raw != INVALID && raw < gCanonical.raw_capacity; }

uint semantic_anchor(uint raw)
{
    uint kind = hir_kind[raw];
    uint callee = hir_call_callee_node[raw];
    uint open = valid_raw(callee) ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = valid_raw(right) ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(
        kind, hir_token_pos[raw], hir_token_end[raw], open, value_token,
        operator_token, gCanonical.canonical_capacity);
}

uint dense_id(uint raw)
{
    if (!valid_raw(raw)) return INVALID;
    if (canonical_flag[raw] != 0u) return canonical_prefix_before_raw[raw];
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint encoded = canonical_anchor_owner[anchor];
    uint winner_plus_one = encoded & 0x0fffffffu;
    if (winner_plus_one == 0u) return INVALID;
    uint winner = winner_plus_one - 1u;
    return valid_raw(winner) && canonical_flag[winner] != 0u
        ? canonical_prefix_before_raw[winner]
        : INVALID;
}

uint expression_id(uint raw)
{
    if (!valid_raw(raw)) return INVALID;
    uint root = hir_expr_result_root_node[raw];
    uint mapped = dense_id(root);
    return mapped != INVALID ? mapped : dense_id(raw);
}

uint dense_boundary(uint raw)
{
    return raw >= gCanonical.raw_capacity ? canonical_count[0u] : canonical_prefix_before_raw[raw];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (row >= count) return;
    uint raw = canonical_dense_to_raw[row];
    uint item_kind = hir_item_kind[raw];

    HirCore core;
    uint production = node_kind[raw];
    core.kind = hir_kind[raw];
    if (production == PROD_IMPL_INHERENT || production == PROD_IMPL_TRAIT)
        core.kind = HIR_IMPL;
    else if (item_kind == 1u)
        core.kind = 31u;
    else if (item_kind == 2u)
        core.kind = 32u;
    else if (item_kind == 3u)
        core.kind = 25u;
    else if (item_kind == 4u || item_kind == 5u)
        core.kind = 3u;
    else if (item_kind == 6u)
        core.kind = 27u;
    else if (item_kind == 7u)
        core.kind = 26u;
    else if (item_kind == 8u)
        core.kind = 29u;
    else if (item_kind == 9u || item_kind == 10u)
        core.kind = 2u;
    core.parent = dense_id(parent_value[raw]);
    core.token_start = hir_token_pos[raw];
    core.token_end = hir_token_end[raw];

    HirLinks links;
    links.first_child = INVALID;
    links.next_sibling = INVALID;
    links.subtree_end = dense_boundary(subtree_end[raw]);
    links.file_id = hir_token_file_id[raw];

    HirPayload payload;
    payload.a = INVALID;
    payload.b = INVALID;
    payload.c = INVALID;
    payload.d = INVALID;

    uint type_form = hir_type_form[raw];
    uint4 parameter = hir_param_record[raw];
    uint stmt_base = raw * 4u;
    uint stmt_kind = hir_stmt_record[stmt_base];
    uint expr_form = hir_expr_record[stmt_base];
    if (item_kind != 0u)
    {
        payload.a = item_kind;
        payload.b = hir_item_name_token[raw];
        payload.c = hir_item_namespace[raw];
        payload.d = item_kind == 2u
            ? hir_item_import_target_kind[raw]
            : hir_item_visibility[raw];
    }
    else if (core.kind == 3u)
    {
        // Impl and trait methods are semantic function nodes even though they
        // do not enter the ordinary item namespace. Every compact function
        // still carries its declaration-name token in the same payload slot.
        payload.b = hir_method_name_token[raw];
    }
    else if (parameter.x != INVALID)
    {
        payload.a = dense_id(parameter.x);
        payload.b = parameter.y;
        payload.c = parameter.z;
        payload.d = dense_id(hir_param_type_node[raw]);
    }
    else if (type_form != 0u)
    {
        payload.a = type_form;
        payload.b = dense_id(hir_type_value_node[raw]);
        payload.c = hir_type_len_token[raw];
        payload.d = hir_type_len_value[raw];
    }
    else if (stmt_kind != 0u)
    {
        payload.a = stmt_kind;
        uint x = hir_stmt_record[stmt_base + 1u];
        uint y = hir_stmt_record[stmt_base + 2u];
        uint z = hir_stmt_record[stmt_base + 3u];
        if (stmt_kind == STMT_LET || stmt_kind == STMT_CONST)
        {
            payload.b = x;
            payload.c = expression_id(y);
            payload.d = dense_id(z);
        }
        else if (stmt_kind == STMT_RETURN)
        {
            payload.b = expression_id(x);
            payload.c = INVALID;
            payload.d = z;
        }
        else if (stmt_kind == STMT_ASSIGN)
        {
            payload.b = expression_id(x);
            payload.c = expression_id(y);
            payload.d = z;
        }
        else if (stmt_kind == STMT_FOR)
        {
            payload.b = x;
            payload.c = expression_id(y);
            payload.d = dense_id(z);
        }
        else if (stmt_kind == STMT_IF || stmt_kind == STMT_WHILE)
        {
            payload.b = expression_id(x);
            payload.c = dense_id(y);
            payload.d = dense_id(z);
        }
    }
    else if (core.kind == HIR_CALL_EXPR)
    {
        // A callee is an operand identity, not the result root of the
        // expression containing the call. Following its result-root link can
        // incorrectly turn `f()` inside `f() + g()` into the outer binary
        // node and causes backends to suppress the binary as callee syntax.
        payload.a = dense_id(hir_call_callee_node[raw]);
        payload.b = INVALID;
        payload.c = hir_call_arg_count[raw];
        payload.d = dense_id(hir_call_context_stmt_node[raw]);
    }
    else if (core.kind == HIR_MEMBER_EXPR)
    {
        // Member access keeps its receiver and selected name entirely in the
        // compact expression domain. Backends may project the dense receiver
        // to their own executable row without retaining parser member columns.
        payload.a = expr_form;
        payload.b = dense_id(hir_member_receiver_node[raw]);
        payload.c = hir_member_name_token[raw];
        payload.d = hir_member_receiver_token[raw];
    }
    else if (core.kind == HIR_ARRAY_EXPR)
    {
        payload.d = dense_id(hir_array_lit_context_stmt_node[raw]);
    }
    else if (core.kind == HIR_STRUCT_LITERAL_EXPR)
    {
        // Struct-literal fields are a compact source-ordered family. The
        // field scatter fills b/c with its start/count, while d keeps the
        // dense statement context needed by backends.
        payload.a = expr_form;
        payload.b = INVALID;
        payload.c = 0u;
        payload.d = dense_id(hir_struct_lit_context_stmt_node[raw]);
    }
    else if (core.kind == HIR_MATCH_EXPR)
    {
        payload.a = expression_id(hir_match_scrutinee_node[raw]);
        // Compact match arms are a source-ordered family. Their scatter pass
        // fills this node-local start/count range without retaining raw arm
        // production rows.
        payload.b = INVALID;
        payload.c = 0u;
    }
    else if (expr_form != 0u)
    {
        payload.a = expr_form;
        payload.b = expression_id(hir_expr_record[stmt_base + 1u]);
        payload.c = expression_id(hir_expr_record[stmt_base + 2u]);
        payload.d = hir_expr_record[stmt_base + 3u];
    }

    hir_core[row] = core;
    hir_links[row] = links;
    hir_payload[row] = payload;
    hir_canonical_fn_return_type[row] = dense_id(hir_fn_return_type_node[raw]);
    hir_canonical_type_alias_target[row] = dense_id(hir_type_alias_target_node[raw]);
    hir_canonical_const_type[row] = item_kind == 3u
        ? dense_id(hir_stmt_record[stmt_base + 3u])
        : INVALID;
}
