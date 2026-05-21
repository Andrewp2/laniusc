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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;

RWStructuredBuffer<uint> bracket_semantic_kind;

static const uint WG_SIZE = 256u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const int INF = 2147483647;

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint block_index_for_token(uint token_i)
{
    return token_i / WG_SIZE;
}

bool nearest_bracket_open_kind_before(uint token_i, int depth_before, uint wanted_kind)
{
    if (depth_before <= 0)
        return false;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BracketDepthTree,
            BracketDepthRows,
            BracketDepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return false;

    uint count = active_token_count();
    if (open_i >= count || token_words[open_i].kind != TK_LBRACKET)
        return false;

    return bracket_semantic_kind[open_i] == wanted_kind;
}

public struct BracketDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
    }

    public static uint leaf_base()
    {
        uint n_blocks = gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
        uint base = 1u;
        [loop]
        while (base < n_blocks)
            base <<= 1u;
        return base;
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

public struct BracketDepthRows : IRangeSearchRows<int>
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

public struct BracketDepthAtMost : IRangeSearchPredicate<int, int>
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
    if (open_kind == TK_TYPE_ARRAY_LBRACKET)
        return TK_TYPE_ARRAY_RBRACKET;
    if (open_kind == TK_INDEX_LBRACKET)
        return TK_INDEX_RBRACKET;
    if (open_kind == TK_ARRAY_LBRACKET)
        return TK_ARRAY_RBRACKET;
    return TK_RBRACKET;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = tid.x;
    uint count = active_token_count();
    if (token_i >= gParams.n_tokens || token_i >= count)
        return;

    uint raw_kind = token_words[token_i].kind;
    if (raw_kind == TK_COMMA || raw_kind == TK_SEMICOLON)
    {
        int depth_before = block_prefix_bracket[block_index_for_token(token_i)] +
            depth_bracket_inblock[token_i];
        if (raw_kind == TK_COMMA &&
            nearest_bracket_open_kind_before(token_i, depth_before, TK_ARRAY_LBRACKET))
            bracket_semantic_kind[token_i] = TK_ARRAY_COMMA;
        if (raw_kind == TK_SEMICOLON &&
            nearest_bracket_open_kind_before(token_i, depth_before, TK_TYPE_ARRAY_LBRACKET))
            bracket_semantic_kind[token_i] = TK_TYPE_SEMICOLON;
        return;
    }

    if (raw_kind != TK_RBRACKET)
        return;

    int close_depth = brace_match_depth[token_i];
    if (close_depth == INF)
        return;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BracketDepthTree,
            BracketDepthRows,
            BracketDepthAtMost>(
            token_i,
            close_depth,
            open_i))
        return;

    if (open_i >= count || token_words[open_i].kind != TK_LBRACKET)
        return;

    bracket_semantic_kind[token_i] = close_kind_for_open_kind(bracket_semantic_kind[open_i]);
}
