// Resolve the two virtual close-token kinds for marked `>>` tokens. Each
// marked token performs two independent parallel range queries against the
// already-published raw-angle depth tree; no token walks source text.

import segment_tree;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> angle_match_min_tree;
RWStructuredBuffer<uint> semantic_token_kinds;

static const uint WG_SIZE = 256u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;

uint tree_leaf_base()
{
    uint base = max(gParams.n_blocks, 1u) - 1u;
    base |= base >> 1u; base |= base >> 2u; base |= base >> 4u;
    base |= base >> 8u; base |= base >> 16u;
    return base + 1u;
}

public struct AngleDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks() { return gParams.n_blocks; }
    public static uint leaf_base() { return tree_leaf_base(); }
    public static int leaf_value(uint block) { return angle_match_block_min[block]; }
    public static int tree_value(uint node) { return angle_match_min_tree[node]; }
}

public struct AngleDepthRows : IRangeSearchRows<int>
{
    public static uint item_count() { return gParams.n_tokens; }
    public static uint block_size() { return WG_SIZE; }
    public static int row_value(uint row) { return angle_match_depth[row]; }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query) { return aggregate <= query; }
    public static bool leaf_matches(int leaf, int query) { return leaf <= query; }
}

uint close_kind_for_open(uint open_kind)
{
    if (open_kind == TK_TYPE_ARG_LT) return TK_TYPE_ARG_GT;
    if (open_kind == TK_GENERIC_PARAM_LT) return TK_GENERIC_PARAM_GT;
    if (open_kind == TK_BOUND_TYPE_ARG_LT) return TK_BOUND_TYPE_ARG_GT;
    if (open_kind == TK_PATH_TYPE_ARG_LT) return TK_PATH_TYPE_ARG_GT;
    return TK_GT;
}

uint close_kind_at_depth(uint hi, uint count, int target_depth)
{
    uint open_i = 0u;
    if (target_depth < 0 ||
        !range_search_tree_last_index_before<
            int, int, AngleDepthTree, AngleDepthRows, DepthAtMost>(
                hi, target_depth, open_i) ||
        open_i >= count || token_words[open_i].kind != TK_LT ||
        angle_match_depth[open_i] != target_depth)
        return TK_GT;
    return close_kind_for_open(semantic_token_kinds[open_i + 1u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    if (i >= count || (semantic_token_kinds[i + 1u] & 0x80000000u) == 0u)
        return;

    uint block = i / WG_SIZE;
    int depth_before = block_prefix_angle[block] + depth_angle_inblock[i];
    uint inner = close_kind_at_depth(i, count, depth_before - 1);
    uint outer = close_kind_at_depth(i, count, depth_before - 2);
    semantic_token_kinds[i + 1u] = 0x80000000u |
        (inner & 0x7fffu) | ((outer & 0x7fffu) << 15u);
}
