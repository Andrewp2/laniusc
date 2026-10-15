// Gives every raw `}` the semantic kind of the `{` it closes, and the
// statement kind that owns a braced right-hand side.
//
// A raw `}` has brace match depth equal to its depth before minus one, which
// is exactly the brace query that tokens_delimiter_match_03_enclosing_opens
// publishes, so token_enclosing_open[close].y is the opener it closes. No
// hierarchy search runs here.

struct Params
{
    uint n_tokens;
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
StructuredBuffer<uint4> token_enclosing_open;
StructuredBuffer<uint> statement_context_kind;

RWStructuredBuffer<uint> brace_semantic_kind;
RWStructuredBuffer<uint> braced_rhs_statement_kind;

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
static const uint TK_CONST = 92u;
static const uint TK_LET = 68u;
static const uint TK_TYPE = 103u;
static const uint STATEMENT_CONTEXT_CONST_RHS = 250u;
static const uint STATEMENT_CONTEXT_ASSIGN_RHS = 251u;
static const uint STATEMENT_CONTEXT_FOR_IN = 252u;
static const uint STATEMENT_CONTEXT_LET_RHS = 253u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

[ForceInline]
uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
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

uint statement_kind_for_context(uint context)
{
    uint kind = context & 0xffu;
    if (kind == STATEMENT_CONTEXT_CONST_RHS)
        return TK_CONST;
    if (kind == STATEMENT_CONTEXT_LET_RHS)
        return TK_LET;
    if (kind == STATEMENT_CONTEXT_TYPE_ALIAS_RHS)
        return TK_TYPE;
    if (kind == STATEMENT_CONTEXT_ASSIGN_RHS || kind == STATEMENT_CONTEXT_FOR_IN)
        return 0u;
    return kind;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint close_i = tid.x;
    if (close_i < gParams.n_tokens)
        braced_rhs_statement_kind[close_i] = 0u;
    uint count = active_token_count();
    if (close_i >= gParams.n_tokens || close_i >= count)
        return;
    if (token_words[close_i].kind != TK_RBRACE)
        return;

    uint open_i = token_enclosing_open[close_i].y;
    if (open_i >= count || token_words[open_i].kind != TK_LBRACE)
        return;

    brace_semantic_kind[close_i] = close_kind_for_open_kind(brace_semantic_kind[open_i]);
    uint context_i = open_i == 0u ? 0u : open_i - 1u;
    braced_rhs_statement_kind[close_i] =
        statement_kind_for_context(statement_context_kind[context_i]);
}
