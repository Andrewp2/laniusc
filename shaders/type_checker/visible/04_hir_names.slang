// Resolve HIR name expressions through compact declaration tables.
//
// Scheduling contract:
// - Dispatch after compact HIR declaration records have been sorted by
//   (owner function, interned name id, declaration token).
// - For each HIR name use, this pass performs sorted range queries over the
//   declaration table and a max-scope segment-tree query to find the latest
//   declaration before the use whose scope still contains it.
// - It consumes HIR expression/statement/token-span records, interned name ids,
//   function context records, and compact declaration records. It does not
//   inspect source text, inspect token spelling, match helper names, or
//   recognize function-body shapes. Local self-initializer rejection is driven
//   by compact declaration-node records plus parser-owned initializer spans,
//   not by walking parent/root chains.

import range_query;
import segment_tree;
import status;

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> hir_value_decl_name_present;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_visible_decl_count_out;
StructuredBuffer<uint> hir_visible_decl_owner_fn;
StructuredBuffer<uint> hir_visible_decl_name_id;
StructuredBuffer<uint> hir_visible_decl_token;
StructuredBuffer<uint> hir_visible_decl_scope_end;
StructuredBuffer<uint> hir_visible_decl_node;
StructuredBuffer<uint> hir_visible_decl_key_order;
StructuredBuffer<uint> hir_visible_decl_scope_tree;
StructuredBuffer<uint> module_value_path_call_leaf;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> type_expr_ref_tag;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 20u;
static const uint HIR_VISIBLE_DECL_ROW_BLOCK_SIZE = 64u;

static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint TYPE_REF_INVALID = 0u;

static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

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
    return ((capacity - 1u) / HIR_VISIBLE_DECL_ROW_BLOCK_SIZE) + 1u;
}

uint round_power_of_two_nonzero(uint value)
{
    value = max(value, 1u);
    value -= 1u;
    value |= value >> 1u;
    value |= value >> 2u;
    value |= value >> 4u;
    value |= value >> 8u;
    value |= value >> 16u;
    return value + 1u;
}

uint visible_decl_leaf_base()
{
    return round_power_of_two_nonzero(visible_decl_leaf_count());
}

bool visible_decl_tree_shape_supported()
{
    uint leaves = visible_decl_leaf_count();
    uint leaf_base = visible_decl_leaf_base();
    return leaf_base != 0u &&
        leaves <= leaf_base &&
        leaf_base <= 0x40000000u;
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool parser_published_type_syntax(uint node, uint token_i)
{
    if (valid_token(token_i) && type_expr_ref_tag[token_i] != TYPE_REF_INVALID)
        return true;

    uint owner = valid_node(node) ? parent[node] : INVALID;
    if (valid_node(owner) && hir_kind[owner] == HIR_TYPE)
        return true;
    if (valid_node(owner) && hir_kind[owner] == HIR_PATH_EXPR)
    {
        uint path_owner = parent[owner];
        return valid_node(path_owner) && hir_kind[path_owner] == HIR_TYPE;
    }
    return false;
}

uint expr_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint encoded_owner_fn(uint token)
{
    return valid_token(token) ? enclosing_fn[token] : 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool token_in_required_hir_span(uint token, uint node)
{
    if (!valid_token(token) || !valid_node(node))
        return true;

    uint start = hir_token_pos[node];
    uint end = hir_token_end[node];
    if (!valid_token(start) || end == INVALID)
        return true;

    end = min(end, active_token_count());
    if (end <= start)
        return true;

    return start <= token && token < end;
}

bool local_decl_initializer_contains_token(uint use_token, uint decl_i)
{
    // If the compact row is malformed, do not bind the name through a
    // declaration whose initializer boundary cannot be proven from records.
    if (decl_i == INVALID || decl_i >= active_token_count())
        return true;

    uint decl_node = hir_visible_decl_node[decl_i];
    if (!valid_node(decl_node))
        return true;

    uint kind = hir_kind[decl_node];
    uint stmt_kind = stmt_slot(decl_node, 0u);
    if ((kind == HIR_STMT || kind == HIR_LET_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET ||
         stmt_kind == STMT_RECORD_KIND_CONST))
    {
        uint init_node = stmt_slot(decl_node, 2u);
        return valid_node(init_node) && token_in_required_hir_span(use_token, init_node);
    }

    if ((kind == HIR_STMT || kind == HIR_FOR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_FOR)
    {
        uint iterable_node = stmt_slot(decl_node, 2u);
        return valid_node(iterable_node) && token_in_required_hir_span(use_token, iterable_node);
    }

    return false;
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
        return base != 0u && block < n_blocks() ?
            hir_visible_decl_scope_tree[base + block] : 0u;
    }

    public static uint tree_value(uint node)
    {
        uint base = leaf_base();
        return base != 0u && node < base * 2u ? hir_visible_decl_scope_tree[node] : 0u;
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

uint best_hir_decl_row_from_table(uint use_token, uint owner_encoded, uint use_name)
{
    uint count = active_decl_count();
    if (count == 0u || !visible_decl_tree_shape_supported())
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
    return decl_i == INVALID ? INVALID : row;
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
    if (parser_published_type_syntax(node, use_token))
        return;
    if (module_value_path_call_leaf[use_token] != 0u)
        return;
    if (module_value_path_associated_method_token[use_token] != INVALID)
        return;
    uint use_name = name_id_by_token[use_token];
    if (use_name == INVALID || use_name >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT ||
        hir_value_decl_name_present[use_name] == 0u)
        return;

    uint owner_encoded = encoded_owner_fn(use_token);
    uint decl_row = best_hir_decl_row_from_table(use_token, owner_encoded, use_name);
    uint decl_i = sorted_decl_row(decl_row);
    uint decl_token = decl_i == INVALID ? INVALID : hir_visible_decl_token[decl_i];
    if (valid_token(decl_token))
    {
        if (local_decl_initializer_contains_token(use_token, decl_i))
        {
            record_error(use_token, ERR_UNRESOLVED_IDENT, 0u);
            return;
        }
        visible_decl[use_token] = decl_token;
    }
}
