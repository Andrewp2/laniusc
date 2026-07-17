// Mark only durable language constructs. Grammar forwarding/list/tail rows are
// intentionally excluded from the canonical HIR phase boundary.

import generated_parse_production_ids;
import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> canonical_flag;
RWStructuredBuffer<uint> canonical_anchor_owner;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_ITEM = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_LET_STMT = 8u;
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
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_IMPL = 35u;
static const uint HIR_EXPR_FORWARD = 1u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }

bool direct_expression_kind(uint kind)
{
    return kind == HIR_CALL_EXPR || kind == HIR_INDEX_EXPR || kind == HIR_MEMBER_EXPR ||
           kind == HIR_ARRAY_EXPR || kind == HIR_STRUCT_LITERAL_EXPR || kind == HIR_MATCH_EXPR;
}

bool durable_kind(uint kind)
{
    return kind == HIR_FILE || kind == HIR_ITEM || kind == HIR_FN || kind == HIR_PARAM ||
           kind == HIR_TYPE || kind == HIR_BLOCK || kind == HIR_LET_STMT ||
           kind == HIR_RETURN_STMT || kind == HIR_IF_STMT || kind == HIR_WHILE_STMT ||
           kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT ||
           kind == HIR_CONST_ITEM || kind == HIR_ENUM_ITEM || kind == HIR_STRUCT_ITEM ||
           kind == HIR_TYPE_ALIAS_ITEM || kind == HIR_FOR_STMT ||
           kind == HIR_MODULE_ITEM || kind == HIR_IMPORT_ITEM || kind == HIR_PATH_EXPR ||
           kind == HIR_NAME_EXPR || kind == HIR_LITERAL_EXPR ||
           direct_expression_kind(kind);
}

bool is_canonical(uint node)
{
    uint kind = hir_kind[node];
    uint production = node_kind[node];
    uint expr_form = hir_expr_record[node * 4u];
    uint stmt_kind = hir_stmt_record[node * 4u];
    return hir_token_pos[node] != INVALID && hir_token_pos[node] < gCanonical.canonical_capacity &&
           (durable_kind(kind) || production == PROD_IMPL_INHERENT || production == PROD_IMPL_TRAIT ||
            hir_item_kind[node] != 0u || hir_type_form[node] != 0u ||
            hir_param_record[node].x != INVALID || stmt_kind != 0u ||
            ((kind == HIR_EXPR || kind == HIR_ASSIGN_EXPR || kind == HIR_BINARY_EXPR ||
              kind == HIR_UNARY_EXPR || kind == HIR_POSTFIX_EXPR) &&
             expr_form > HIR_EXPR_FORWARD));
}

uint canonical_kind(uint node)
{
    uint production = node_kind[node];
    return production == PROD_IMPL_INHERENT || production == PROD_IMPL_TRAIT
        ? HIR_IMPL
        : hir_kind[node];
}

uint anchor_for(uint node)
{
    uint kind = hir_kind[node];
    uint callee = hir_call_callee_node[node];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[node * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[node * 4u + 3u];
    return canonical_hir_anchor(
        kind, hir_token_pos[node], hir_token_end[node], open, value_token,
        operator_token, gCanonical.canonical_capacity);
}

uint encoded_winner(uint node)
{
    return (canonical_hir_priority(canonical_kind(node)) << 28u) | (node + 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= gCanonical.raw_capacity) return;
    bool active = node < active_count();
    bool candidate = active && is_canonical(node);
    canonical_flag[node] = candidate ? 1u : 0u;
    if (candidate)
    {
        uint ignored;
        uint anchor = anchor_for(node);
        InterlockedMax(canonical_anchor_owner[anchor], encoded_winner(node), ignored);
        InterlockedAdd(canonical_status[4u], 1u, ignored);
        InterlockedMax(canonical_status[5u], anchor, ignored);
        InterlockedAdd(canonical_status[7u], anchor, ignored);
    }
    if (node == 0u) canonical_status[0u] = 0u;
}
