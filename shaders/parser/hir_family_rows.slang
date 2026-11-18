// Which tree rows belong to an HIR family whose kernels write only their own
// rows. A family array holds defined words only on its family's rows, so a
// reader tests the row here before it reads one.

import generated_parse_production_ids;

static const uint HIR_FAMILY_EXPR = 14u;
static const uint HIR_FAMILY_ASSIGN_EXPR = 15u;
static const uint HIR_FAMILY_BINARY_EXPR = 16u;
static const uint HIR_FAMILY_UNARY_EXPR = 17u;
static const uint HIR_FAMILY_POSTFIX_EXPR = 18u;
static const uint HIR_FAMILY_CALL_EXPR = 19u;
static const uint HIR_FAMILY_INDEX_EXPR = 20u;
static const uint HIR_FAMILY_MEMBER_EXPR = 21u;
static const uint HIR_FAMILY_NAME_EXPR = 22u;
static const uint HIR_FAMILY_LITERAL_EXPR = 23u;
static const uint HIR_FAMILY_ARRAY_EXPR = 24u;
static const uint HIR_FAMILY_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FAMILY_PATH_EXPR = 33u;
static const uint HIR_FAMILY_MATCH_EXPR = 34u;
static const uint HIR_FAMILY_TRY_EXPR = 36u;

bool hir_family_expr_kind(uint kind)
{
    return kind == HIR_FAMILY_EXPR ||
           kind == HIR_FAMILY_ASSIGN_EXPR ||
           kind == HIR_FAMILY_BINARY_EXPR ||
           kind == HIR_FAMILY_UNARY_EXPR ||
           kind == HIR_FAMILY_POSTFIX_EXPR ||
           kind == HIR_FAMILY_CALL_EXPR ||
           kind == HIR_FAMILY_INDEX_EXPR ||
           kind == HIR_FAMILY_MEMBER_EXPR ||
           kind == HIR_FAMILY_NAME_EXPR ||
           kind == HIR_FAMILY_LITERAL_EXPR ||
           kind == HIR_FAMILY_ARRAY_EXPR ||
           kind == HIR_FAMILY_STRUCT_LITERAL_EXPR ||
           kind == HIR_FAMILY_PATH_EXPR ||
           kind == HIR_FAMILY_MATCH_EXPR ||
           kind == HIR_FAMILY_TRY_EXPR;
}

bool hir_array_element_container(uint prod)
{
    return prod == PROD_ARRAY_SOME || prod == PROD_ARRAY_AFTER_COMMA_MORE;
}

// An array element: an expression directly under an element container. The
// array element arrays (owner, link, rank, previous, parent literal and
// ordinal) are defined on these rows only.
bool hir_array_element_row(uint row_hir_kind, uint parent_prod)
{
    return hir_family_expr_kind(row_hir_kind) && hir_array_element_container(parent_prod);
}

bool hir_call_arg_container(uint prod)
{
    return prod == PROD_ARGS_SOME || prod == PROD_ARGS_AFTER_COMMA_MORE;
}

// A call argument: a plain expression row that is the first child of an
// argument container. The argument arrays (end token, owner, link, rank,
// parent call and ordinal) are defined on these rows only. The first-child
// test belongs to the caller, which has the tree.
bool hir_call_arg_row(uint row_hir_kind, uint parent_prod)
{
    return row_hir_kind == HIR_FAMILY_EXPR && hir_call_arg_container(parent_prod);
}
