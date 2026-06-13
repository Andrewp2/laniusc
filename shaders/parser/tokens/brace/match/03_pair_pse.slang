import segment_tree;

struct Params
{
    uint n_tokens;
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
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;

RWStructuredBuffer<uint> brace_semantic_kind;

static const uint WG_SIZE = 256u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_IMPL_RBRACE = 122u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_TRAIT_RBRACE = 124u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_STRUCT_DECL_RBRACE = 128u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_ENUM_RBRACE = 130u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_MATCH_RBRACE = 120u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_FN_BLOCK_RBRACE = 150u;
static const uint TK_IMPL_FN_BLOCK_LBRACE = 151u;
static const uint TK_IMPL_FN_BLOCK_RBRACE = 152u;
static const int INF = 2147483647;

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
    }

    public static uint leaf_base()
    {
        uint n_blocks = gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
        return range_search_leaf_base_for_block_count(n_blocks);
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
        return gParams.n_tokens;
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

uint close_kind_for_open_kind(uint open_kind)
{
    if (open_kind == TK_MATCH_LBRACE)
        return TK_MATCH_RBRACE;
    if (open_kind == TK_IMPL_LBRACE)
        return TK_IMPL_RBRACE;
    if (open_kind == TK_TRAIT_LBRACE)
        return TK_TRAIT_RBRACE;
    if (open_kind == TK_IF_LBRACE)
        return TK_IF_RBRACE;
    if (open_kind == TK_STRUCT_LIT_LBRACE)
        return TK_STRUCT_LIT_RBRACE;
    if (open_kind == TK_STRUCT_DECL_LBRACE)
        return TK_STRUCT_DECL_RBRACE;
    if (open_kind == TK_ENUM_LBRACE)
        return TK_ENUM_RBRACE;
    if (open_kind == TK_FN_BLOCK_LBRACE)
        return TK_FN_BLOCK_RBRACE;
    if (open_kind == TK_IMPL_FN_BLOCK_LBRACE)
        return TK_IMPL_FN_BLOCK_RBRACE;
    return TK_RBRACE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint close_i = tid.x;
    uint count = active_token_count();
    if (close_i >= gParams.n_tokens || close_i >= count)
        return;
    if (token_words[close_i].kind != TK_RBRACE)
        return;

    int close_depth = brace_match_depth[close_i];
    if (close_depth == INF)
        return;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BraceDepthTree,
            BraceDepthRows,
            BraceDepthAtMost>(
            close_i,
            close_depth,
            open_i))
        return;

    if (open_i >= count || token_words[open_i].kind != TK_LBRACE)
        return;

    brace_semantic_kind[close_i] = close_kind_for_open_kind(brace_semantic_kind[open_i]);
}
