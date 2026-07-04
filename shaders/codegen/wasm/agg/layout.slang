// Project aggregate field ordinals for HIR-driven WASM lowering.
//
// Type checking already resolves member and struct-literal field ordinals with
// sorted HIR/type records. This active WASM boundary only copies those records
// into the token-keyed buffers that the aggregate layout clear pass owns.
// Unsupported or unresolved aggregate shapes remain INVALID from the clear pass.

import gpu_index;

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
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_struct_decl_field_count;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_field_count;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;

RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;
RWStructuredBuffer<uint> wasm_agg_local_width_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint field_name_token(uint field_node)
{
    uint token_i = valid_node(field_node) ? hir_token_pos[field_node] : INVALID;
    return token_i < gParams.n_tokens ? token_i : INVALID;
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint visible_type_for_token(uint token)
{
    if (token >= gParams.n_tokens)
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint struct_width_for_type(uint ty)
{
    if (ty < TY_STRUCT_BASE || ty >= TY_ENUM_BASE)
        return 0u;

    uint decl_token = ty - TY_STRUCT_BASE;
    if (decl_token >= gParams.n_tokens)
        return 0u;

    uint struct_node = type_decl_hir_node_by_token[decl_token];
    if (!valid_node(struct_node))
        return 0u;

    return hir_struct_decl_field_count[struct_node];
}

uint call_return_width(uint call_node)
{
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return 0u;

    uint call_token = hir_token_pos[call_node];
    if (call_token >= gParams.n_tokens)
        return 0u;

    return struct_width_for_type(call_return_type[call_token]);
}

void publish_member_projection(uint member_node)
{
    uint member_i = valid_node(member_node) ? hir_member_name_token[member_node] : INVALID;
    if (member_i >= gParams.n_tokens)
        return;

    uint index = member_result_field_ordinal[member_i];
    if (index != INVALID)
        member_result_field_index[member_i] = index;
}

void publish_struct_init_projection(uint field_node)
{
    uint field_i = field_name_token(field_node);
    if (field_i == INVALID || field_i >= gParams.n_tokens)
        return;

    uint index = struct_init_field_ordinal_by_node[field_node];
    if (index != INVALID)
        struct_init_field_index[field_i] = index;
}

void publish_aggregate_local_width(uint lit_node)
{
    if (hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
    {
        return;
    }

    uint let_node = hir_struct_lit_context_stmt_node[lit_node];
    if (!valid_node(let_node) ||
        hir_kind[let_node] != HIR_LET_STMT ||
        stmt_record_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }
    uint decl_token = stmt_record_slot(let_node, 1u);
    if (decl_token >= gParams.n_tokens)
        return;

    uint width = hir_struct_lit_field_count[lit_node];
    if (width != INVALID)
        wasm_agg_local_width_by_token[decl_token] = width;
}

void publish_return_aggregate_width(uint lit_node)
{
    if (hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    uint return_node = hir_struct_lit_context_stmt_node[lit_node];
    if (!valid_node(return_node) || hir_kind[return_node] != HIR_RETURN_STMT)
        return;

    uint return_token = hir_token_pos[return_node];
    if (return_token >= gParams.n_tokens)
        return;

    uint width = hir_struct_lit_field_count[lit_node];
    if (width != INVALID)
        wasm_agg_local_width_by_token[return_token] = width;
}

void publish_let_aggregate_local_width(uint let_node)
{
    if (!valid_node(let_node) ||
        hir_kind[let_node] != HIR_LET_STMT ||
        stmt_record_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint decl_token = stmt_record_slot(let_node, 1u);
    if (decl_token >= gParams.n_tokens)
        return;

    uint width = struct_width_for_type(visible_type_for_token(decl_token));
    if (width == 0u)
        width = call_return_width(stmt_record_slot(let_node, 2u));

    if (width != 0u)
        wasm_agg_local_width_by_token[decl_token] = width;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i >= active_hir_node_count())
        return;

    publish_aggregate_local_width(i);
    publish_return_aggregate_width(i);
    publish_let_aggregate_local_width(i);

    if (hir_struct_lit_field_parent_lit[i] != INVALID)
        publish_struct_init_projection(i);
    else if (hir_kind[i] == HIR_MEMBER_EXPR)
        publish_member_projection(i);
}
