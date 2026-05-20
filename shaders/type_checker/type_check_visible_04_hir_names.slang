// Resolve HIR name expressions through compact declaration tables.
//
// Scheduling contract:
// - Dispatch after compact HIR declaration records have been sorted by
//   (owner function, interned name id, declaration token).
// - For each HIR name use, this pass performs sorted range queries over the
//   declaration table and a max-scope segment-tree query to find the latest
//   declaration before the use whose scope still contains it.
// - It consumes HIR expression records, interned name ids, function context
//   records, and compact declaration records. It does not scan
//   all HIR nodes per use, inspect source text, inspect token spelling, match
//   helper names, or recognize function-body shapes.

import range_query;
import segment_tree;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> hir_value_decl_name_present;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_visible_decl_count_out;
StructuredBuffer<uint> hir_visible_decl_owner_fn;
StructuredBuffer<uint> hir_visible_decl_name_id;
StructuredBuffer<uint> hir_visible_decl_token;
StructuredBuffer<uint> hir_visible_decl_scope_end;
StructuredBuffer<uint> hir_visible_decl_key_order;
StructuredBuffer<uint> hir_visible_decl_scope_tree;

RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 19u;
static const uint HIR_VISIBLE_DECL_ROW_BLOCK_SIZE = 64u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;

public struct HirVisibleDeclLookupKey
{
    uint owner_fn;
    uint name_id;
    uint decl_token;
};

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_semantic_hir_count()
{
    return min(hir_semantic_count[0], gParams.n_hir_nodes);
}

uint active_decl_count()
{
    return min(hir_visible_decl_count_out[0], gParams.n_tokens);
}

uint visible_decl_leaf_count()
{
    uint capacity = max(gParams.n_tokens, 1u);
    return max(1u, (capacity + HIR_VISIBLE_DECL_ROW_BLOCK_SIZE - 1u) /
                     HIR_VISIBLE_DECL_ROW_BLOCK_SIZE);
}

uint visible_decl_leaf_base()
{
    uint base = 1u;
    uint leaves = visible_decl_leaf_count();
    [loop]
    while (base < leaves)
        base <<= 1u;
    return base;
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint expr_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint encoded_owner_fn(uint token)
{
    return valid_token(token) ? enclosing_fn[token] : 0u;
}

int compare_u32(uint left, uint right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

HirVisibleDeclLookupKey hir_visible_decl_lookup_key(
    uint owner_fn,
    uint name_id,
    uint decl_token)
{
    HirVisibleDeclLookupKey key;
    key.owner_fn = owner_fn;
    key.name_id = name_id;
    key.decl_token = decl_token;
    return key;
}

uint sorted_decl_row(uint row)
{
    if (row >= active_decl_count())
        return INVALID;
    uint decl_i = hir_visible_decl_key_order[row];
    return decl_i < gParams.n_tokens ? decl_i : INVALID;
}

public struct HirVisibleDeclRowCompare : IRowQueryCompare<HirVisibleDeclLookupKey>
{
    public static int compare(uint row, HirVisibleDeclLookupKey key)
    {
        uint decl_i = sorted_decl_row(row);
        if (decl_i == INVALID)
            return 1;

        int owner_cmp = compare_u32(hir_visible_decl_owner_fn[decl_i], key.owner_fn);
        if (owner_cmp != 0)
            return owner_cmp;

        int name_cmp = compare_u32(hir_visible_decl_name_id[decl_i], key.name_id);
        if (name_cmp != 0)
            return name_cmp;

        return compare_u32(hir_visible_decl_token[decl_i], key.decl_token);
    }
}

public struct HirVisibleDeclScopeTree : IRangeSearchTree<uint>
{
    public static uint n_blocks()
    {
        return visible_decl_leaf_count();
    }

    public static uint leaf_base()
    {
        return visible_decl_leaf_base();
    }

    public static uint leaf_value(uint block)
    {
        uint base = leaf_base();
        return block < n_blocks() ? hir_visible_decl_scope_tree[base + block] : 0u;
    }

    public static uint tree_value(uint node)
    {
        return node < leaf_base() * 2u ? hir_visible_decl_scope_tree[node] : 0u;
    }
}

public struct HirVisibleDeclScopeRows : IRangeSearchRows<uint>
{
    public static uint item_count()
    {
        return active_decl_count();
    }

    public static uint block_size()
    {
        return HIR_VISIBLE_DECL_ROW_BLOCK_SIZE;
    }

    public static uint row_value(uint row)
    {
        uint decl_i = sorted_decl_row(row);
        return decl_i == INVALID ? 0u : hir_visible_decl_scope_end[decl_i];
    }
}

public struct ScopeEndAfterUse : IRangeSearchPredicate<uint, uint>
{
    public static bool aggregate_may_match(uint aggregate, uint use_token)
    {
        return aggregate > use_token;
    }

    public static bool leaf_matches(uint scope_end_value, uint use_token)
    {
        return scope_end_value > use_token;
    }
}

uint best_hir_decl_from_table(uint use_token, uint owner_encoded, uint use_name)
{
    uint count = active_decl_count();
    if (count == 0u)
        return INVALID;

    HirVisibleDeclLookupKey range_start =
        hir_visible_decl_lookup_key(owner_encoded, use_name, 0u);
    HirVisibleDeclLookupKey use_key =
        hir_visible_decl_lookup_key(owner_encoded, use_name, use_token);

    uint lo = lower_bound_query<HirVisibleDeclLookupKey, HirVisibleDeclRowCompare>(
        count,
        range_start);
    uint hi = lower_bound_query<HirVisibleDeclLookupKey, HirVisibleDeclRowCompare>(
        count,
        use_key);
    if (hi <= lo)
        return INVALID;

    uint row;
    if (!range_search_tree_last_index_between<
            uint,
            uint,
            HirVisibleDeclScopeTree,
            HirVisibleDeclScopeRows,
            ScopeEndAfterUse>(
            lo,
            hi,
            use_token,
            row))
        return INVALID;

    uint decl_i = sorted_decl_row(row);
    return decl_i == INVALID ? INVALID : hir_visible_decl_token[decl_i];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_hir_count())
        return;
    uint node = hir_semantic_dense_node[row];
    if (!valid_node(node))
        return;
    if (expr_slot(node, EXPR_RECORD_FORM) != HIR_EXPR_NAME)
        return;

    uint use_token = expr_slot(node, EXPR_RECORD_VALUE_TOKEN);
    if (!valid_token(use_token))
        return;
    uint use_name = name_id_by_token[use_token];
    if (use_name == INVALID || use_name >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT ||
        hir_value_decl_name_present[use_name] == 0u)
        return;

    uint owner_encoded = encoded_owner_fn(use_token);
    uint decl_token = best_hir_decl_from_table(use_token, owner_encoded, use_name);
    if (valid_token(decl_token))
        visible_decl[use_token] = decl_token;
}
