// Match-pattern context block summaries for token retagging.
//
// This pass records the latest match-pattern phase event in each token block.
// The shared delimiter scan turns those block summaries into prefix context,
// and the apply pass publishes per-token rows consumed by tokens_to_kinds.

import prefix_scan;
import segment_tree;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
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
StructuredBuffer<uint> brace_semantic_kind;

RWStructuredBuffer<uint> statement_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_ARROW = 75u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint MATCH_PATTERN_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint encode_match_pattern_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

int global_paren_depth_before_token(uint token_i)
{
    uint block_idx = token_i / WG_SIZE;
    return block_prefix_paren[block_idx] + depth_paren_inblock[token_i];
}

int global_brace_depth_before_token(uint token_i)
{
    uint block_idx = token_i / WG_SIZE;
    return block_prefix_brace[block_idx] + depth_brace_inblock[token_i];
}

int global_bracket_depth_before_token(uint token_i)
{
    uint block_idx = token_i / WG_SIZE;
    return block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i];
}

int global_angle_depth_before_token(uint token_i)
{
    uint block_idx = token_i / WG_SIZE;
    return block_prefix_angle[block_idx] + depth_angle_inblock[token_i];
}

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gParams.n_blocks;
    }

    public static uint leaf_base()
    {
        return range_search_leaf_base_for_block_count(gParams.n_blocks);
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

bool enclosing_match_brace_before(uint token_i, out uint open_i)
{
    open_i = 0u;
    int depth_before = global_brace_depth_before_token(token_i);
    if (depth_before <= 0)
        return false;

    if (!range_search_tree_last_index_before<
            int,
            int,
            BraceDepthTree,
            BraceDepthRows,
            BraceDepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return false;

    return open_i < gParams.n_tokens &&
           token_words[open_i].kind == TK_LBRACE &&
           brace_semantic_kind[open_i] == TK_MATCH_LBRACE;
}

bool top_level_match_arm_comma(uint token_i)
{
    if (token_words[token_i].kind != TK_COMMA)
        return false;

    uint open_i;
    if (!enclosing_match_brace_before(token_i, open_i))
        return false;

    return global_paren_depth_before_token(token_i) == global_paren_depth_before_token(open_i) &&
           global_bracket_depth_before_token(token_i) == global_bracket_depth_before_token(open_i) &&
           global_angle_depth_before_token(token_i) == global_angle_depth_before_token(open_i);
}

uint match_pattern_event_for(uint token_i, uint kind)
{
    if (kind == TK_LBRACE)
    {
        uint payload = brace_semantic_kind[token_i] == TK_MATCH_LBRACE
            ? MATCH_PATTERN_CONTEXT
            : 0u;
        return encode_match_pattern_event(token_i, payload);
    }
    if (kind == TK_ARROW || kind == TK_RBRACE || kind == TK_SEMICOLON)
        return encode_match_pattern_event(token_i, 0u);
    if (kind == TK_COMMA && top_level_match_arm_comma(token_i))
        return encode_match_pattern_event(token_i, MATCH_PATTERN_CONTEXT);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();
    uint kind = token_i < count ? token_words[token_i].kind : 0u;
    uint event = token_i < count ? match_pattern_event_for(token_i, kind) : 0u;
    uint prefix = prefix_scan_u32_max_256(lane, event);
    if (lane + 1u == WG_SIZE)
        statement_event_block[block_idx] = prefix;
}
