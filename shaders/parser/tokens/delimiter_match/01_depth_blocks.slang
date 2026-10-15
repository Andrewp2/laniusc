// Computes match depths, block minima and each block's local minimum heap
// for all four delimiter classes (x paren, y brace, z bracket, w angle). The
// heaps let 03_enclosing_opens search without scanning rows; see
// blocked_search_tree.slang for the layout.

import prefix_scan;
import blocked_search_tree;

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
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> block_prefix_angle;

RWStructuredBuffer<int> paren_match_depth;
RWStructuredBuffer<int> brace_match_depth;
RWStructuredBuffer<int> bracket_match_depth;
RWStructuredBuffer<int> angle_match_depth;
RWStructuredBuffer<int> paren_match_block_min;
RWStructuredBuffer<int> brace_match_block_min;
RWStructuredBuffer<int> bracket_match_block_min;
RWStructuredBuffer<int> angle_match_block_min;
RWStructuredBuffer<int4> delimiter_match_local_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int INF = 2147483647;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_SHR = 44u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_PATTERN_RPAREN = 141u;
static const uint TK_ENUM_PAYLOAD_RPAREN = 143u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
static const uint TK_MEMBER_TYPE_ARG_GT = 191u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

groupshared int4 local_heap[512];

struct PrefixScanI32x4Min : IPrefixScanOp<int4>
{
    static int4 identity()
    {
        return int4(INF, INF, INF, INF);
    }

    static int4 combine(int4 left, int4 right)
    {
        return min(left, right);
    }
};

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[ForceInline]
uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

bool is_paren_open(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_paren_close(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

bool is_angle_open(uint kind)
{
    return kind == TK_LT || kind == TK_TYPE_ARG_LT || kind == TK_GENERIC_PARAM_LT ||
           kind == TK_BOUND_TYPE_ARG_LT || kind == TK_PATH_TYPE_ARG_LT;
}

bool is_angle_close(uint kind)
{
    return kind == TK_GT || kind == TK_TYPE_ARG_GT || kind == TK_GENERIC_PARAM_GT ||
           kind == TK_BOUND_TYPE_ARG_GT || kind == TK_PATH_TYPE_ARG_GT ||
           kind == TK_MEMBER_TYPE_ARG_GT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint token_i = block_idx * WG_SIZE + ltid.x;
    uint count = active_token_count();
    int4 event_depth = PrefixScanI32x4Min.identity();

    if (token_i < gParams.n_tokens && token_i < count)
    {
        uint kind = token_words[token_i].kind;
        int4 depth_before = int4(
            block_prefix_paren[block_idx] + depth_paren_inblock[token_i],
            block_prefix_brace[block_idx] + depth_brace_inblock[token_i],
            block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i],
            block_prefix_angle[block_idx] + depth_angle_inblock[token_i]);

        if (is_paren_open(kind)) event_depth.x = depth_before.x;
        else if (is_paren_close(kind)) event_depth.x = depth_before.x - 1;
        if (kind == TK_LBRACE) event_depth.y = depth_before.y;
        else if (kind == TK_RBRACE) event_depth.y = depth_before.y - 1;
        if (kind == TK_LBRACKET)
        {
            event_depth.z = depth_before.z;
        }
        else if (kind == TK_RBRACKET) event_depth.z = depth_before.z - 1;
        if (is_angle_open(kind)) event_depth.w = depth_before.w;
        else if (is_angle_close(kind)) event_depth.w = depth_before.w - 1;
        else if (kind == TK_SHR) event_depth.w = depth_before.w - 2;
    }

    if (token_i < gParams.n_tokens)
    {
        paren_match_depth[token_i] = event_depth.x;
        brace_match_depth[token_i] = event_depth.y;
        bracket_match_depth[token_i] = event_depth.z;
        angle_match_depth[token_i] = event_depth.w;
    }

    blocked_local_heap_build<int4, PrefixScanI32x4Min>(ltid.x, event_depth, local_heap);
    delimiter_match_local_min[block_idx * WG_SIZE + ltid.x] = local_heap[max(ltid.x, 1u)];
    if (ltid.x == 0u)
    {
        int4 block_min = local_heap[1];
        paren_match_block_min[block_idx] = block_min.x;
        brace_match_block_min[block_idx] = block_min.y;
        bracket_match_block_min[block_idx] = block_min.z;
        angle_match_block_min[block_idx] = block_min.w;
    }
}
