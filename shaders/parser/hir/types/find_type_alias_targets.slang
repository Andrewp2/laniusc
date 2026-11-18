// Publish each type-alias item's direct right-hand-side type node.
//
// A prior pointer-jump pass computes the nearest item owner for every semantic
// row. The grammar gives the alias exactly one direct type-expression child.
// Header annotations and bounds belong to nested productions; selecting the
// first contained type would mistake `const N: usize` for the alias target.
//
// The same rows also publish each function or impl-method return type node:
// from a canonical type row, walk grammar forwarding parents until reaching
// either the return-type wrapper or another canonical type. The latter means
// this is a nested type rather than the return root. The walk also stops at
// the first production outside type grammar, so a type in a statement or item
// never climbs to the root. Once the return wrapper is found, the remaining
// path to the function declaration is fixed signature grammar, independent of
// user type nesting.
//
// The two outputs are independent: each reads only parser columns that this
// pass does not write, alias targets are plain stores to the alias row, and
// return types are an InterlockedMin into the function row.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirTypeAliasTarget;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_type_alias_owner_value;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> node_kind;
RWStructuredBuffer<uint> hir_type_alias_target_node;
RWStructuredBuffer<uint> hir_fn_return_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirTypeAliasTarget.uses_status_count != 0u ? min(gHirTypeAliasTarget.n, tree_count_status[5u])
                                              : gHirTypeAliasTarget.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

uint item_kind_for_raw(uint node)
{
    if (!valid_original_node(node))
        return 0u;
    uint item_row = gHirTypeAliasTarget.retain_debug_rows != 0u ? node : raw_to_hir[node];
    return item_row != INVALID ? hir_item_kind[item_row] : 0u;
}

void publish_type_alias_target(uint row, uint node)
{
    uint owner = hir_type_alias_owner_value[row];
    if (!valid_original_node(owner) || parent[node] != owner ||
        item_kind_for_raw(owner) != HIR_ITEM_KIND_TYPE_ALIAS)
        return;

    uint output_row = gHirTypeAliasTarget.retain_debug_rows != 0u
        ? owner
        : raw_to_hir[owner];
    if (output_row != INVALID)
        hir_type_alias_target_node[output_row] = node;
}

bool function_decl_node(uint node)
{
    if (!valid_original_node(node) || hir_kind[node] != HIR_FN)
        return false;
    uint production = node_kind[node];
    return production == PROD_FN || production == PROD_EXTERN_FN ||
           production == PROD_IMPL_FN || production == PROD_TRAIT_METHOD ||
           production == PROD_TRAIT_METHOD_PUB;
}

// Productions derivable from `type_expr` in grammar/lanius.bnf, leaving out
// the scalar constant arguments, which never have a type below them.
bool type_grammar_production(uint production)
{
    switch (production)
    {
    case PROD_TYPE_IDENT:
    case PROD_TYPE_ARRAY:
    case PROD_TYPE_REF:
    case PROD_TYPE_REF_MUT:
    case PROD_TYPE_NEVER:
    case PROD_TYPE_PATH:
    case PROD_TYPE_PATH_IDENT:
    case PROD_TYPE_PATH_MORE:
    case PROD_TYPE_PATH_END:
    case PROD_TYPE_ARGS_NONE:
    case PROD_TYPE_ARGS_SOME:
    case PROD_TYPE_ARGS_MORE:
    case PROD_TYPE_ARGS_END:
    case PROD_TYPE_ARGS_AFTER_COMMA_MORE:
    case PROD_TYPE_ARGS_AFTER_COMMA_TRAILING:
    case PROD_GENERIC_ARGUMENT_TYPE:
    case PROD_GENERIC_ARGUMENT_CONSTANT:
    case PROD_TYPE_ARRAY_TAIL:
    case PROD_TYPE_SLICE_TAIL:
    case PROD_TYPE_ARRAY_LEN_NAME:
    case PROD_TYPE_ARRAY_LEN_CONSTANT:
    case PROD_ARRAY_LENGTH_PATH:
    case PROD_ARRAY_LENGTH_PATH_IDENT:
    case PROD_ARRAY_LENGTH_PATH_MORE:
    case PROD_ARRAY_LENGTH_PATH_END:
        return true;
    default:
        return false;
    }
}

uint next_parent(uint node)
{
    uint next = valid_original_node(node) ? parent[node] : INVALID;
    return next != node && valid_original_node(next) ? next : INVALID;
}

void publish_fn_return_type(uint node)
{
    uint cursor = next_parent(node);
    bool inside_return_type = false;
    while (valid_original_node(cursor))
    {
        uint production = node_kind[cursor];
        if (production == PROD_RET_TYPE)
        {
            inside_return_type = true;
            cursor = next_parent(cursor);
            break;
        }
        // A different canonical type between this row and the return wrapper
        // owns this nested type. Only that outer type may become the function's
        // published return root.
        if (hir_kind[cursor] == HIR_TYPE && raw_to_hir[cursor] != INVALID)
            return;
        // Everything between a return wrapper and a type below it is type
        // grammar. Any other production (a let, a parameter, an item list)
        // means this type is not in a return type, so stop here instead of
        // climbing statement and item lists toward the root.
        if (!type_grammar_production(production))
            return;
        cursor = next_parent(cursor);
    }
    if (!inside_return_type)
        return;
    while (valid_original_node(cursor) && !function_decl_node(cursor))
        cursor = next_parent(cursor);
    uint function_owner = cursor;
    if (!function_decl_node(function_owner)) return;
    uint output_row = gHirTypeAliasTarget.retain_debug_rows != 0u
        ? function_owner
        : raw_to_hir[function_owner];
    if (output_row != INVALID)
        InterlockedMin(hir_fn_return_type_node[output_row], node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_semantic_row(row))
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_original_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] == HIR_TYPE_FORM_NONE)
        return;

    publish_type_alias_target(row, node);
    publish_fn_return_type(node);
}
