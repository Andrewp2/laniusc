// Apply prefix-scanned statement phase rows.

import prefix_scan;

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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<uint> statement_context_kind;

groupshared uint statement_phase_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_PLUS_ASSIGN = 46u;
static const uint TK_MINUS_ASSIGN = 47u;
static const uint TK_STAR_ASSIGN = 48u;
static const uint TK_SLASH_ASSIGN = 49u;
static const uint TK_PERCENT_ASSIGN = 50u;
static const uint TK_CARET_ASSIGN = 51u;
static const uint TK_SHL_ASSIGN = 52u;
static const uint TK_SHR_ASSIGN = 53u;
static const uint TK_AMP_ASSIGN = 54u;
static const uint TK_PIPE_ASSIGN = 55u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_IN = 101u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
static const uint TK_CONST_ASSIGN = 111u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_MATCH_RBRACE = 120u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_IMPL_RBRACE = 122u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_TRAIT_RBRACE = 124u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_STRUCT_DECL_RBRACE = 128u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_ENUM_RBRACE = 130u;
static const uint TK_TRAIT_METHOD_SEMICOLON = 146u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_FN_BLOCK_RBRACE = 150u;
static const uint TK_IMPL_FN_BLOCK_LBRACE = 151u;
static const uint TK_IMPL_FN_BLOCK_RBRACE = 152u;
static const uint TK_IMPORT_SEMICOLON = 162u;
static const uint TK_MODULE_SEMICOLON = 163u;
static const uint TK_EXTERN_SEMICOLON = 164u;
static const uint TK_TYPE_ALIAS_SEMICOLON = 165u;
static const uint TK_CONST_SEMICOLON = 166u;
static const uint TK_LET_SEMICOLON = 167u;
static const uint TK_RETURN_SEMICOLON = 168u;
static const uint TK_EXPR_SEMICOLON = 169u;
static const uint TK_BREAK_SEMICOLON = 170u;
static const uint TK_CONTINUE_SEMICOLON = 171u;
static const uint TK_CONST = 92u;

static const uint STATEMENT_CONTEXT_CONST_RHS = 250u;
static const uint STATEMENT_CONTEXT_ASSIGN_RHS = 251u;
static const uint STATEMENT_CONTEXT_FOR_IN = 252u;
static const uint STATEMENT_CONTEXT_LET_RHS = 253u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

bool is_statement_starter(uint kind)
{
    return kind == TK_IMPORT ||
           kind == TK_MODULE ||
           kind == TK_EXTERN ||
           kind == TK_TYPE ||
           kind == TK_CONST ||
           kind == TK_LET ||
           kind == TK_RETURN ||
           kind == TK_IF ||
           kind == TK_ELSE ||
           kind == TK_WHILE ||
           kind == TK_FOR ||
           kind == TK_BREAK ||
           kind == TK_CONTINUE ||
           kind == TK_FN ||
           kind == TK_ENUM ||
           kind == TK_STRUCT ||
           kind == TK_IMPL ||
           kind == TK_TRAIT;
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

bool is_statement_semicolon(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_TRAIT_METHOD_SEMICOLON ||
           kind == TK_IMPORT_SEMICOLON || kind == TK_MODULE_SEMICOLON ||
           kind == TK_EXTERN_SEMICOLON || kind == TK_TYPE_ALIAS_SEMICOLON ||
           kind == TK_CONST_SEMICOLON || kind == TK_LET_SEMICOLON ||
           kind == TK_RETURN_SEMICOLON || kind == TK_EXPR_SEMICOLON ||
           kind == TK_BREAK_SEMICOLON || kind == TK_CONTINUE_SEMICOLON;
}

bool is_statement_lbrace(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_FN_BLOCK_LBRACE ||
           kind == TK_IMPL_FN_BLOCK_LBRACE || kind == TK_MATCH_LBRACE ||
           kind == TK_IMPL_LBRACE || kind == TK_TRAIT_LBRACE ||
           kind == TK_STRUCT_LIT_LBRACE || kind == TK_STRUCT_DECL_LBRACE ||
           kind == TK_ENUM_LBRACE;
}

bool is_statement_rbrace(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_FN_BLOCK_RBRACE ||
           kind == TK_IMPL_FN_BLOCK_RBRACE || kind == TK_MATCH_RBRACE ||
           kind == TK_IMPL_RBRACE || kind == TK_TRAIT_RBRACE ||
           kind == TK_STRUCT_LIT_RBRACE || kind == TK_STRUCT_DECL_RBRACE ||
           kind == TK_ENUM_RBRACE;
}

bool is_statement_reset_boundary(uint kind)
{
    return is_statement_semicolon(kind) || is_statement_lbrace(kind) || is_statement_rbrace(kind);
}

uint statement_context_token_kind(uint context)
{
    uint kind = context & 0xffu;
    if (kind == STATEMENT_CONTEXT_ASSIGN_RHS)
        return 0u;
    if (kind == STATEMENT_CONTEXT_FOR_IN)
        return TK_FOR;
    if (kind == STATEMENT_CONTEXT_CONST_RHS)
        return TK_CONST;
    if (kind == STATEMENT_CONTEXT_LET_RHS)
        return TK_LET;
    return kind == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ? TK_TYPE : kind;
}

uint encode_statement_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

uint statement_phase_event_for(uint token_i, uint kind, int bracket_depth_before)
{
    if (bracket_depth_before != 0)
        return 0u;
    if (is_statement_starter(kind))
        return encode_statement_event(token_i, kind);
    if (is_statement_reset_boundary(kind))
        return encode_statement_event(token_i, 0u);
    if (kind == TK_LET_ASSIGN)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_LET_RHS);
    if (kind == TK_TYPE_ALIAS_ASSIGN)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_TYPE_ALIAS_RHS);
    if (kind == TK_CONST_ASSIGN)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_CONST_RHS);
    uint context_kind = statement_context_token_kind(statement_context_kind[token_i]);
    if (kind == TK_IN && context_kind == TK_FOR)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_FOR_IN);
    if (kind == TK_ASSIGN && context_kind == TK_LET)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_LET_RHS);
    if (kind == TK_ASSIGN && context_kind == TK_TYPE)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_TYPE_ALIAS_RHS);
    if (kind == TK_ASSIGN && context_kind == TK_CONST)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_CONST_RHS);
    if (is_assignment_operator(kind))
        return encode_statement_event(token_i, STATEMENT_CONTEXT_ASSIGN_RHS);
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
    int bracket_depth_before = token_i < gParams.n_tokens
        ? block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i]
        : 0;

    uint event = token_i < count
        ? statement_phase_event_for(token_i, kind, bracket_depth_before)
        : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        event,
        statement_phase_prefix_values);
    uint local_before = lane == 0u ? 0u : statement_phase_prefix_values[lane - 1u];
    uint before = max(statement_event_block_prefix[block_idx], local_before);
    uint context = bracket_depth_before == 0 ? before : 0u;
    if (token_i < gParams.n_tokens)
        statement_context_kind[token_i] = context;
}
