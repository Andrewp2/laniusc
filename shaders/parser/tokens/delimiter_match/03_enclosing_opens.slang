// Publishes every token's raw delimiter relations once, so the semantic
// token-kind passes read them instead of repeating hierarchy searches.
//
// For each delimiter class, token_enclosing_open[t] is the last earlier row
// whose match depth is at most the class depth before t, minus one: the
// previous-smaller-or-equal element of the match-depth sequence, or INVALID.
// When that row is an opener at exactly that depth it is the delimiter that
// encloses t; consumers apply that check (see to/token_relations.slang). A raw
// `>>` closes two angle levels, so its angle query is two levels down, which
// selects the opener of the outer list it closes. Components follow the match
// buffers: x paren, y brace, z bracket, w angle.
//
// token_angle_close[t] is, for a raw `<`, the first later row whose angle
// match depth is at most the opener's: the closer that ends its list.

import segment_tree;

struct Params
{
    uint token_capacity;
    uint match_tree_n_blocks;
    uint match_tree_leaf_base;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;
StructuredBuffer<int> paren_match_depth;
StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> paren_match_min_tree;
StructuredBuffer<int> bracket_match_depth;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> bracket_match_min_tree;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> angle_match_min_tree;

RWStructuredBuffer<uint4> token_enclosing_open;
RWStructuredBuffer<uint> token_angle_close;

static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const int INF = 2147483647;
static const uint TK_LT = 12u;
static const uint TK_SHR = 44u;

uint depth_search_n_blocks()
{
    return gParams.match_tree_n_blocks == 0u ? 1u : gParams.match_tree_n_blocks;
}

uint depth_search_leaf_base()
{
    uint n_blocks = depth_search_n_blocks();
    uint base = gParams.match_tree_leaf_base > 0u
        ? gParams.match_tree_leaf_base - 1u
        : max(n_blocks, 1u) - 1u;
    base |= base >> 1u;
    base |= base >> 2u;
    base |= base >> 4u;
    base |= base >> 8u;
    base |= base >> 16u;
    return base + 1u;
}

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks() { return depth_search_n_blocks(); }
    public static uint leaf_base() { return depth_search_leaf_base(); }
    public static int leaf_value(uint block) { return brace_match_block_min[block]; }
    public static int tree_value(uint node) { return brace_match_min_tree[node]; }
}

public struct ParenDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks() { return depth_search_n_blocks(); }
    public static uint leaf_base() { return depth_search_leaf_base(); }
    public static int leaf_value(uint block) { return paren_match_block_min[block]; }
    public static int tree_value(uint node) { return paren_match_min_tree[node]; }
}

public struct BracketDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks() { return depth_search_n_blocks(); }
    public static uint leaf_base() { return depth_search_leaf_base(); }
    public static int leaf_value(uint block) { return bracket_match_block_min[block]; }
    public static int tree_value(uint node) { return bracket_match_min_tree[node]; }
}

public struct AngleDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks() { return depth_search_n_blocks(); }
    public static uint leaf_base() { return depth_search_leaf_base(); }
    public static int leaf_value(uint block) { return angle_match_block_min[block]; }
    public static int tree_value(uint node) { return angle_match_min_tree[node]; }
}

public struct BraceDepthRows : IRangeSearchRows<int>
{
    public static uint item_count() { return gParams.token_capacity; }
    public static uint block_size() { return WG_SIZE; }
    public static int row_value(uint row) { return brace_match_depth[row]; }
}

public struct ParenDepthRows : IRangeSearchRows<int>
{
    public static uint item_count() { return gParams.token_capacity; }
    public static uint block_size() { return WG_SIZE; }
    public static int row_value(uint row) { return paren_match_depth[row]; }
}

public struct BracketDepthRows : IRangeSearchRows<int>
{
    public static uint item_count() { return gParams.token_capacity; }
    public static uint block_size() { return WG_SIZE; }
    public static int row_value(uint row) { return bracket_match_depth[row]; }
}

public struct AngleDepthRows : IRangeSearchRows<int>
{
    public static uint item_count() { return gParams.token_capacity; }
    public static uint block_size() { return WG_SIZE; }
    public static int row_value(uint row) { return angle_match_depth[row]; }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query) { return aggregate <= query; }
    public static bool leaf_matches(int leaf, int query) { return leaf <= query; }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = tid.x;
    if (token_i >= gParams.token_capacity)
        return;

    uint count = min(lexer_token_count[0], gParams.token_capacity);
    uint4 open = uint4(INVALID, INVALID, INVALID, INVALID);
    uint close = INVALID;
    if (token_i < count)
    {
        uint block_i = token_i / WG_SIZE;
        uint kind = token_words[token_i].kind;
        int4 query = int4(
            block_prefix_paren[block_i] + depth_paren_inblock[token_i],
            block_prefix_brace[block_i] + depth_brace_inblock[token_i],
            block_prefix_bracket[block_i] + depth_bracket_inblock[token_i],
            block_prefix_angle[block_i] + depth_angle_inblock[token_i]) -
            int4(1, 1, 1, kind == TK_SHR ? 2 : 1);

        // A failed search leaves its index INVALID.
        uint found;
        range_search_tree_last_index_before<int, int, ParenDepthTree, ParenDepthRows, DepthAtMost>(
            token_i, query.x, found);
        open.x = found;
        range_search_tree_last_index_before<int, int, BraceDepthTree, BraceDepthRows, DepthAtMost>(
            token_i, query.y, found);
        open.y = found;
        range_search_tree_last_index_before<int, int, BracketDepthTree, BracketDepthRows, DepthAtMost>(
            token_i, query.z, found);
        open.z = found;
        range_search_tree_last_index_before<int, int, AngleDepthTree, AngleDepthRows, DepthAtMost>(
            token_i, query.w, found);
        open.w = found;

        int open_depth = angle_match_depth[token_i];
        if (kind == TK_LT && open_depth != INF)
        {
            range_search_tree_first_index_at_or_after<int, int, AngleDepthTree, AngleDepthRows, DepthAtMost>(
                token_i + 1u, open_depth, found);
            close = found;
        }
    }
    token_enclosing_open[token_i] = open;
    token_angle_close[token_i] = close;
}
