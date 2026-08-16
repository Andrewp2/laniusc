// Mark only durable language constructs. Grammar forwarding/list/tail rows are
// intentionally excluded from the canonical HIR phase boundary.

import generated_parse_production_ids;
import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
RWStructuredBuffer<uint> canonical_anchor_by_raw;
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
static const uint HIR_STMT = 7u;
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
static const uint HIR_EXPR_RANGE_FROM = 31u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }

bool valid_node(uint node)
{
    return node != INVALID && node < active_count();
}

uint direct_child(uint node)
{
    uint child = valid_node(node) ? first_child[node] : INVALID;
    return valid_node(child) && parent[child] == node ? child : INVALID;
}

uint direct_next(uint owner, uint node)
{
    uint sibling = valid_node(node) ? next_sibling[node] : INVALID;
    return valid_node(sibling) && parent[sibling] == owner ? sibling : INVALID;
}

bool assignment_tail(uint production)
{
    return production == PROD_ASSIGN_SET || production == PROD_ASSIGN_ADD ||
           production == PROD_ASSIGN_SUB || production == PROD_ASSIGN_MUL ||
           production == PROD_ASSIGN_DIV || production == PROD_ASSIGN_MOD ||
           production == PROD_ASSIGN_XOR || production == PROD_ASSIGN_SHL ||
           production == PROD_ASSIGN_SHR || production == PROD_ASSIGN_BAND ||
           production == PROD_ASSIGN_BOR;
}

uint assignment_tail_for_stmt(uint node)
{
    if (node_kind[node] != PROD_EXPR_STMT) return INVALID;
    uint expr = direct_child(node);
    if (!valid_node(expr)) return INVALID;
    uint assign = node_kind[expr] == PROD_ASSIGN ? expr : direct_child(expr);
    if (!valid_node(assign) || node_kind[assign] != PROD_ASSIGN) return INVALID;
    uint lhs = direct_child(assign);
    uint tail = direct_next(assign, lhs);
    return valid_node(tail) && assignment_tail(node_kind[tail]) ? tail : INVALID;
}

bool assignment_statement(uint node)
{
    return assignment_tail_for_stmt(node) != INVALID;
}

uint token_before(uint token)
{
    return token != INVALID && token > 0u ? token - 1u : INVALID;
}

uint call_open_token(uint call_node)
{
    if (!valid_node(call_node) || node_kind[call_node] != PROD_POSTFIX_CALL)
        return INVALID;
    // Terminal rows are absent from the production tree. The argument-list
    // production begins immediately after the opening parenthesis for both
    // empty and nonempty calls.
    uint args = direct_child(call_node);
    if (!valid_node(args) ||
        (node_kind[args] != PROD_ARGS_SOME && node_kind[args] != PROD_ARGS_NONE))
        return INVALID;
    return token_before(hir_token_pos[args]);
}

uint struct_literal_head_token(uint literal_node)
{
    if (!valid_node(literal_node) || node_kind[literal_node] != PROD_STRUCT_LIT)
        return INVALID;
    uint owner = parent[literal_node];
    if (!valid_node(owner) || node_kind[owner] != PROD_IDENT)
        return INVALID;
    uint head = direct_child(owner);
    return valid_node(head) && node_kind[head] == PROD_PATH &&
        direct_next(owner, head) == literal_node
        ? hir_token_pos[head]
        : INVALID;
}

uint member_name_token(uint member_node)
{
    if (!valid_node(member_node) || node_kind[member_node] != PROD_POSTFIX_MEMBER)
        return INVALID;
    uint tail = direct_child(member_node);
    uint tail_token = valid_node(tail) ? hir_token_pos[tail] : INVALID;
    if (tail_token != INVALID && tail_token > hir_token_pos[member_node])
        return tail_token - 1u;
    uint end = hir_token_end[member_node];
    return end != INVALID && end > hir_token_pos[member_node]
        ? end - 1u
        : INVALID;
}

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
    uint anchor = hir_token_pos[node];
    return anchor != INVALID && anchor < gCanonical.canonical_capacity &&
           (durable_kind(kind) || production == PROD_IMPL_INHERENT || production == PROD_IMPL_TRAIT ||
            assignment_statement(node) ||
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
    bool assignment_stmt = assignment_statement(node);
    uint expr_form = hir_expr_record[node * 4u];
    uint identity_kind = canonical_hir_identity_kind(kind, expr_form, assignment_stmt);
    uint open = call_open_token(node);
    uint default_token = kind == HIR_STRUCT_LITERAL_EXPR
        ? struct_literal_head_token(node)
        : hir_token_pos[node];
    if (default_token == INVALID)
        default_token = hir_token_pos[node];
    uint assign_tail = assignment_stmt ? assignment_tail_for_stmt(node) : INVALID;
    uint right = assignment_stmt
        ? direct_child(assign_tail)
        : hir_expr_record[node * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint token_end = hir_token_end[node];
    uint member_token = kind == HIR_MEMBER_EXPR ? member_name_token(node) : INVALID;
    if (member_token != INVALID)
        token_end = member_token + 1u;
    // `start..` initially spans into the following block because its empty
    // postfix tail is anchored at the next token. Match the later range-span
    // normalization now so the operator cannot collide with that block.
    if (expr_form == HIR_EXPR_RANGE_FROM)
    {
        uint left = hir_expr_record[node * 4u + 1u];
        uint left_end = valid_node(left) ? hir_token_end[left] : INVALID;
        if (left_end < token_end)
            token_end = left_end + 1u;
    }
    uint operator_token = canonical_hir_operator_anchor(
        identity_kind, expr_form, right_start, token_end,
        gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[node * 4u + 3u];
    return canonical_hir_anchor(
        identity_kind, default_token, token_end, open, value_token,
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
    uint anchor = active ? anchor_for(node) : INVALID;
    canonical_anchor_by_raw[node] = anchor;
    candidate = candidate && anchor < gCanonical.canonical_capacity;
    canonical_flag[node] = candidate ? 1u : 0u;
    if (candidate)
    {
        uint ignored;
        InterlockedMax(canonical_anchor_owner[anchor], encoded_winner(node), ignored);
        InterlockedAdd(canonical_status[4u], 1u, ignored);
        InterlockedMax(canonical_status[5u], anchor, ignored);
        InterlockedAdd(canonical_status[7u], anchor, ignored);
    }
    if (node == 0u) canonical_status[0u] = 0u;
}
