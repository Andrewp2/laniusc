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
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<int> bracket_match_depth;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> bracket_match_min_tree;
StructuredBuffer<int> paren_match_depth;
StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> paren_match_min_tree;
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> angle_match_min_tree;
StructuredBuffer<uint> brace_semantic_kind;

RWStructuredBuffer<uint> bracket_semantic_kind;

static const uint WG_SIZE = 256u;
static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_LT = 12u;
static const uint TK_LBRACKET = 20u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_RBRACKET = 21u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_ARROW = 75u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
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
            DepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return false;

    uint count = active_token_count();
    if (open_i >= count || token_words[open_i].kind != TK_LBRACKET)
        return false;

    return bracket_semantic_kind[open_i] == wanted_kind;
}

bool nearest_paren_open_before(uint token_i, int depth_before, out uint open_i)
{
    open_i = 0u;
    if (depth_before <= 0)
        return false;

    if (!range_search_tree_last_index_before<
            int,
            int,
            ParenDepthTree,
            ParenDepthRows,
            DepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return false;

    uint count = active_token_count();
    return open_i < count && token_words[open_i].kind == TK_LPAREN;
}

uint enclosing_semantic_brace_open_before(uint token_i)
{
    int depth_before = block_prefix_brace[block_index_for_token(token_i)] +
        depth_brace_inblock[token_i];
    if (depth_before <= 0)
        return 0u;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BraceDepthTree,
            BraceDepthRows,
            DepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return 0u;

    uint count = active_token_count();
    if (open_i >= count || token_words[open_i].kind != TK_LBRACE)
        return 0u;

    return brace_semantic_kind[open_i];
}

bool inside_enum_payload_parens(uint token_i)
{
    int paren_depth_before = block_prefix_paren[block_index_for_token(token_i)] +
        depth_paren_inblock[token_i];

    uint open_i;
    if (!nearest_paren_open_before(token_i, paren_depth_before, open_i))
        return false;
    if (open_i == 0u || token_words[open_i - 1u].kind != TK_IDENT)
        return false;

    return enclosing_semantic_brace_open_before(open_i) == TK_ENUM_LBRACE;
}

public struct AngleDepthTree : IRangeSearchTree<int>
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
        return angle_match_block_min[block];
    }

    public static int tree_value(uint node)
    {
        return angle_match_min_tree[node];
    }
}

public struct AngleDepthRows : IRangeSearchRows<int>
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
        return angle_match_depth[row];
    }
}

bool raw_angle_open_can_start_type_args(uint open_i)
{
    if (open_i == 0u || token_words[open_i].kind != TK_LT)
        return false;

    uint prev = token_words[open_i - 1u].kind;
    uint prev2 = open_i >= 2u ? token_words[open_i - 2u].kind : 0u;
    if (prev != TK_IDENT)
        return false;

    return prev2 == TK_COLON ||
           prev2 == TK_ARROW ||
           prev2 == TK_AMPERSAND ||
           prev2 == TK_LT ||
           prev2 == TK_COMMA ||
           prev2 == TK_LBRACKET;
}

bool inside_type_arg_angle(uint token_i)
{
    int angle_depth_before = block_prefix_angle[block_index_for_token(token_i)] +
        depth_angle_inblock[token_i];
    if (angle_depth_before <= 0)
        return false;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            AngleDepthTree,
            AngleDepthRows,
            DepthAtMost>(
            token_i,
            angle_depth_before - 1,
            open_i))
        return false;

    if (open_i >= active_token_count() ||
        token_words[open_i].kind != TK_LT ||
        angle_match_depth[open_i] != angle_depth_before - 1)
        return false;

    return raw_angle_open_can_start_type_args(open_i);
}

bool type_array_open_context(uint token_i, int bracket_depth_before)
{
    if (bracket_semantic_kind[token_i] == TK_TYPE_ARRAY_LBRACKET)
        return true;
    if (nearest_bracket_open_kind_before(
            token_i,
            bracket_depth_before,
            TK_TYPE_ARRAY_LBRACKET))
        return true;
    uint prev = token_i == 0u ? 0u : token_words[token_i - 1u].kind;
    if (inside_type_arg_angle(token_i) &&
        (prev == TK_LT || prev == TK_COMMA || prev == TK_AMPERSAND))
        return true;
    return inside_enum_payload_parens(token_i);
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
        return range_search_leaf_base_for_block_count(n_blocks);
    }

    public static int leaf_value(uint block)
    {
        return bracket_match_block_min[block];
    }

    public static int tree_value(uint node)
    {
        return bracket_match_min_tree[node];
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
        return bracket_match_depth[row];
    }
}

public struct ParenDepthTree : IRangeSearchTree<int>
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
        return paren_match_block_min[block];
    }

    public static int tree_value(uint node)
    {
        return paren_match_min_tree[node];
    }
}

public struct ParenDepthRows : IRangeSearchRows<int>
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
        return paren_match_depth[row];
    }
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

public struct DepthAtMost : IRangeSearchPredicate<int, int>
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
    int depth_before = block_prefix_bracket[block_index_for_token(token_i)] +
        depth_bracket_inblock[token_i];
    if (raw_kind == TK_LBRACKET)
    {
        uint prev = token_i == 0u ? 0u : token_words[token_i - 1u].kind;
        if (token_i > 0u && prev == TK_RBRACE &&
            brace_semantic_kind[token_i - 1u] == TK_STRUCT_LIT_RBRACE)
        {
            bracket_semantic_kind[token_i] = TK_INDEX_LBRACKET;
            return;
        }
        if (bracket_semantic_kind[token_i] == TK_TYPE_ARRAY_LBRACKET &&
            prev == TK_COLON &&
            enclosing_semantic_brace_open_before(token_i) == TK_STRUCT_LIT_LBRACE)
        {
            // The raw-colon seed cannot distinguish a declaration type from a
            // struct-literal field value. Semantic brace ownership can.
            bracket_semantic_kind[token_i] = TK_ARRAY_LBRACKET;
            return;
        }
        if (type_array_open_context(token_i, depth_before))
            bracket_semantic_kind[token_i] = TK_TYPE_ARRAY_LBRACKET;
        return;
    }

    if (raw_kind == TK_COMMA || raw_kind == TK_SEMICOLON)
    {
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

    int close_depth = bracket_match_depth[token_i];
    if (close_depth == INF)
        return;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BracketDepthTree,
            BracketDepthRows,
            DepthAtMost>(
            token_i,
            close_depth,
            open_i))
        return;

    if (open_i >= count || token_words[open_i].kind != TK_LBRACKET)
        return;

    bracket_semantic_kind[token_i] = close_kind_for_open_kind(bracket_semantic_kind[open_i]);
}
