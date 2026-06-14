// Compute token spans for HIR-facing parse nodes.

import generated_parse_production_ids;
import segment_tree;

struct Params
{
    uint n;
    uint uses_status_count;
    uint token_capacity;
};

ConstantBuffer<Params> gHir;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> source_file_token_end;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;

RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_FN = 3u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const int INF = 2147483647;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_status_count != 0u ? min(gHir.n, tree_count_status[5u]) : gHir.n;
}

uint clamped_end_after_token(uint token_pos)
{
    uint n_tokens = token_count[0];
    return token_pos >= n_tokens ? n_tokens : token_pos + 1u;
}

bool valid_node(uint node, uint n)
{
    return node != INVALID && node < n;
}

uint path_leaf_end(uint path_node, uint n)
{
    uint leaf = valid_node(path_node, n) ? hir_type_path_leaf_node[path_node] : INVALID;
    uint leaf_candidate = leaf < n ? hir_token_pos[leaf] : INVALID;
    uint leaf_pos = leaf_candidate == INVALID ? hir_token_pos[path_node] : leaf_candidate;
    return clamped_end_after_token(leaf_pos);
}

uint active_token_count()
{
    return min(token_count[0], gHir.token_capacity);
}

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        uint n_tokens = gHir.token_capacity == 0u ? 1u : gHir.token_capacity;
        return (n_tokens + WG_SIZE - 1u) / WG_SIZE;
    }

    public static uint leaf_base()
    {
        return range_search_leaf_base_for_block_count(n_blocks());
    }

    public static int leaf_value(uint block)
    {
        return brace_match_block_min[block];
    }

    public static int tree_value(uint node)
    {
        return brace_match_min_tree[node];
    }
}

public struct BraceDepthRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return gHir.token_capacity;
    }

    public static uint block_size()
    {
        return WG_SIZE;
    }

    public static int row_value(uint row)
    {
        return brace_match_depth[row];
    }
}

public struct BraceDepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query)
    {
        return aggregate <= query;
    }

    public static bool leaf_matches(int leaf, int query)
    {
        return leaf <= query;
    }
}

uint matching_brace_close_after(uint open_i)
{
    uint count = active_token_count();
    if (open_i >= count || open_i >= gHir.token_capacity)
        return INVALID;

    int open_depth = brace_match_depth[open_i];
    if (open_depth == INF)
        return INVALID;

    uint close_i;
    if (!range_search_tree_first_index_at_or_after<
            int,
            int,
            BraceDepthTree,
            BraceDepthRows,
            BraceDepthAtMost>(
            open_i + 1u,
            open_depth,
            close_i))
        return INVALID;

    return close_i > open_i &&
           close_i < count &&
           brace_match_depth[close_i] == open_depth
        ? close_i
        : INVALID;
}

uint matched_brace_span_end(uint open_i)
{
    uint close_i = matching_brace_close_after(open_i);
    return close_i == INVALID ? INVALID : close_i + 1u;
}

uint function_body_span_end(uint fn_node, uint n)
{
    uint end_node = min(subtree_end[fn_node], n);
    for (uint cursor = fn_node + 1u, step = 0u;
         cursor < end_node && step < 512u;
         cursor += 1u, step += 1u)
    {
        uint prod = node_kind[cursor];
        if (prod == PROD_FN_BLOCK || prod == PROD_IMPL_FN_BLOCK)
        {
            uint end = matched_brace_span_end(hir_token_pos[cursor]);
            if (end != INVALID && end > hir_token_pos[fn_node])
                return end;
        }
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint start = hir_token_pos[i];
    if (start == INVALID)
    {
        hir_token_end[i] = INVALID;
        return;
    }

    if (hir_kind[i] == HIR_FILE)
    {
        uint file_id = hir_token_file_id[i];
        if (file_id != INVALID && file_id < gHir.token_capacity)
        {
            uint file_end = source_file_token_end[file_id];
            if (file_end > start)
            {
                hir_token_end[i] = file_end;
                return;
            }
        }
    }

    if (hir_kind[i] == HIR_PATH_EXPR)
    {
        hir_token_end[i] = path_leaf_end(i, n);
        return;
    }

    if (hir_kind[i] == HIR_BLOCK)
    {
        uint end = matched_brace_span_end(start);
        if (end != INVALID && end > start)
        {
            hir_token_end[i] = end;
            return;
        }
    }

    if (hir_kind[i] == HIR_FN)
    {
        uint end = function_body_span_end(i, n);
        if (end != INVALID)
        {
            hir_token_end[i] = end;
            return;
        }
    }

    if (hir_kind[i] == HIR_NAME_EXPR)
    {
        if (node_kind[i] == PROD_PATTERN_IDENT)
        {
            uint end_node = min(subtree_end[i], n);
            uint max_pos = start;
            if (end_node > i + 1u)
            {
                uint last_pos = hir_token_pos[end_node - 1u];
                if (last_pos != INVALID)
                    max_pos = last_pos;
            }
            hir_token_end[i] = clamped_end_after_token(max_pos);
            return;
        }

        uint child = first_child[i];
        if (valid_node(child, n) && hir_kind[child] == HIR_PATH_EXPR)
        {
            hir_token_end[i] = path_leaf_end(child, n);
            return;
        }
        hir_token_end[i] = clamped_end_after_token(start);
        return;
    }

    uint end_node = min(subtree_end[i], n);
    uint max_pos = start;
    if (end_node > i + 1u)
    {
        uint last_pos = hir_token_pos[end_node - 1u];
        if (last_pos != INVALID)
            max_pos = last_pos;
    }

    hir_token_end[i] = clamped_end_after_token(max_pos);
}
