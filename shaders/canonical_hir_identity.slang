// Shared source-token identity rules for compact HIR materialization.
// Every pass that selects or resolves an anchor must use these functions so
// winner election and reference projection cannot disagree.

static const uint CANONICAL_HIR_INVALID = 0xffffffffu;
static const uint CANONICAL_HIR_FILE = 1u;
static const uint CANONICAL_HIR_PARAM = 4u;
static const uint CANONICAL_HIR_TYPE = 5u;
static const uint CANONICAL_HIR_EXPR = 14u;
static const uint CANONICAL_HIR_ASSIGN_EXPR = 15u;
static const uint CANONICAL_HIR_BINARY_EXPR = 16u;
static const uint CANONICAL_HIR_UNARY_EXPR = 17u;
static const uint CANONICAL_HIR_POSTFIX_EXPR = 18u;
static const uint CANONICAL_HIR_CALL_EXPR = 19u;
static const uint CANONICAL_HIR_INDEX_EXPR = 20u;
static const uint CANONICAL_HIR_MEMBER_EXPR = 21u;
static const uint CANONICAL_HIR_NAME_EXPR = 22u;
static const uint CANONICAL_HIR_LITERAL_EXPR = 23u;
static const uint CANONICAL_HIR_ARRAY_EXPR = 24u;
static const uint CANONICAL_HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint CANONICAL_HIR_PATH_EXPR = 33u;
static const uint CANONICAL_HIR_MATCH_EXPR = 34u;
static const uint CANONICAL_HIR_EXPR_RANGE = 30u;
static const uint CANONICAL_HIR_EXPR_RANGE_FROM = 31u;
static const uint CANONICAL_HIR_EXPR_RANGE_INCLUSIVE = 34u;

uint canonical_hir_identity_kind(uint kind, uint expr_form, bool assignment_stmt)
{
    if (assignment_stmt) return CANONICAL_HIR_ASSIGN_EXPR;
    // A range beginning with an explicit operand shares its default source
    // token with that operand. Treat it as an operator-anchored expression so
    // both the range and its first operand retain distinct compact identities.
    if (kind == CANONICAL_HIR_EXPR &&
        (expr_form == CANONICAL_HIR_EXPR_RANGE ||
         expr_form == CANONICAL_HIR_EXPR_RANGE_FROM ||
         expr_form == CANONICAL_HIR_EXPR_RANGE_INCLUSIVE))
        return CANONICAL_HIR_BINARY_EXPR;
    return kind;
}

uint canonical_hir_priority(uint kind)
{
    if (kind == CANONICAL_HIR_CALL_EXPR || kind == CANONICAL_HIR_INDEX_EXPR ||
        kind == CANONICAL_HIR_MEMBER_EXPR || kind == CANONICAL_HIR_ARRAY_EXPR ||
        kind == CANONICAL_HIR_STRUCT_LITERAL_EXPR || kind == CANONICAL_HIR_MATCH_EXPR)
        return 14u;
    // Type paths are represented by a side table owned by the type row.
    if (kind == CANONICAL_HIR_TYPE) return 13u;
    if (kind == CANONICAL_HIR_NAME_EXPR || kind == CANONICAL_HIR_LITERAL_EXPR) return 1u;
    if (kind == CANONICAL_HIR_PARAM || kind == CANONICAL_HIR_PATH_EXPR) return 2u;
    if (kind == CANONICAL_HIR_FILE) return 15u;
    return 8u;
}

bool canonical_hir_uses_value_anchor(uint kind)
{
    return kind == CANONICAL_HIR_EXPR || kind == CANONICAL_HIR_ASSIGN_EXPR ||
           kind == CANONICAL_HIR_BINARY_EXPR || kind == CANONICAL_HIR_UNARY_EXPR ||
           kind == CANONICAL_HIR_POSTFIX_EXPR || kind == CANONICAL_HIR_NAME_EXPR ||
           kind == CANONICAL_HIR_LITERAL_EXPR;
}

uint canonical_hir_operator_anchor(uint kind, uint right_start, uint canonical_capacity)
{
    // Assignment and binary productions are `operator + right operand`.
    // Raw grammar spans can include the operator in the left subtree, so the
    // right operand is the stable boundary from which to recover its token.
    if ((kind == CANONICAL_HIR_ASSIGN_EXPR || kind == CANONICAL_HIR_BINARY_EXPR ||
         kind == CANONICAL_HIR_INDEX_EXPR) &&
        right_start != CANONICAL_HIR_INVALID && right_start > 0u &&
        right_start <= canonical_capacity)
        return right_start - 1u;
    return CANONICAL_HIR_INVALID;
}

uint canonical_hir_anchor(
    uint kind,
    uint default_token,
    uint token_end,
    uint call_open_token,
    uint value_token,
    uint operator_token,
    uint canonical_capacity)
{
    // A source pack contains one EOF token per file. Use that file-local EOF
    // as the sentinel so file roots remain distinct without allocating rows
    // proportional to anything other than the packed token stream.
    if (kind == CANONICAL_HIR_FILE && token_end > default_token &&
        token_end <= canonical_capacity)
        return token_end - 1u;
    if (kind == CANONICAL_HIR_CALL_EXPR && call_open_token < canonical_capacity)
        return call_open_token;
    if (kind == CANONICAL_HIR_MEMBER_EXPR && token_end > default_token &&
        token_end <= canonical_capacity)
        return token_end - 1u;
    if ((kind == CANONICAL_HIR_ASSIGN_EXPR || kind == CANONICAL_HIR_BINARY_EXPR ||
         kind == CANONICAL_HIR_INDEX_EXPR) &&
        operator_token < canonical_capacity)
        return operator_token;
    if (value_token < canonical_capacity && canonical_hir_uses_value_anchor(kind))
        return value_token;
    return default_token;
}
