// Classifies every raw `<` once, from its own context: generic parameter
// list, type arguments, bound type arguments, value-path type arguments, or a
// comparison. tokens_to_kinds combines this with the enclosing opener's
// classification, and every token that needs an angle opener's role (its
// closer, separators, signs, a following call) reads this table instead of
// re-deriving it.

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
StructuredBuffer<int> paren_match_depth;
StructuredBuffer<int> bracket_match_depth;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<uint4> token_enclosing_open;
StructuredBuffer<uint> token_angle_close;
StructuredBuffer<uint> brace_semantic_kind;
StructuredBuffer<uint> bracket_semantic_kind;
StructuredBuffer<uint> statement_context_kind;
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> token_where_context_event;

RWStructuredBuffer<uint> token_direct_lt_kind;

#include "token_relations.slang"

bool value_expression_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    uint raw_context = raw_statement_context_kind(token_i);
    if (raw_context == 0u)
    {
        // Statement context is intentionally absent inside brackets. The
        // bracket owner still distinguishes an array/slice type from a value
        // expression, including through nested arrays and qualified paths.
        uint bracket_owner;
        if (matching_raw_bracket_open_before(parser_i, count, bracket_owner) &&
            bracket_semantic_kind[bracket_owner] == TK_TYPE_ARRAY_LBRACKET)
            return false;
        // Declaration fields and enum payloads have no statement event. Their
        // qualified applications are type paths, just like local type names.
        uint owner = enclosing_semantic_brace_open_before(parser_i, count);
        if (owner == TK_STRUCT_DECL_LBRACE || owner == TK_ENUM_LBRACE)
            return false;
    }
    if (raw_context == 0u ||
        raw_context == STATEMENT_CONTEXT_CONST_RHS ||
        raw_context == STATEMENT_CONTEXT_ASSIGN_RHS ||
        raw_context == STATEMENT_CONTEXT_FOR_IN ||
        raw_context == STATEMENT_CONTEXT_LET_RHS)
    {
        return true;
    }

    uint statement_context = statement_context_token_kind(token_i);
    return statement_context == TK_RETURN ||
           statement_context == TK_IF ||
           statement_context == TK_WHILE ||
           statement_context == TK_FOR;
}

// Raw angles include comparison/shift operators. A candidate pair must stay
// inside the same statement and structural containers before its tail can
// establish a value-path application. Equal depths alone would accept
// separate sibling groups; equal enclosing rows for every container class
// mean no container closes between the pair.
bool value_path_arguments_share_container(uint open_i, uint close_i)
{
    if (statement_context_kind[open_i] != statement_context_kind[close_i]) return false;
    if (paren_depth_at(open_i) != paren_depth_at(close_i) ||
        bracket_depth_at(open_i) != bracket_depth_at(close_i) ||
        brace_depth_at(open_i) != brace_depth_at(close_i)) return false;
    uint3 open_owner = token_enclosing_open[open_i].xyz;
    uint3 close_owner = token_enclosing_open[close_i].xyz;
    return all(open_owner == close_owner);
}

bool value_path_type_arguments_have_tail(uint open_i, uint count)
{
    if (open_i == 0u || open_i >= count || token_words[open_i].kind != TK_LT ||
        token_words[open_i - 1u].kind != TK_IDENT) return false;
    int depth = angle_match_depth[open_i];
    uint close_i = token_angle_close[open_i];
    if (depth == INF || close_i >= count || angle_match_depth[close_i] != depth) return false;
    uint close = token_words[close_i].kind;
    if (close != TK_GT && close != TK_SHR) return false;
    uint next_i = close_i + 1u;
    if (next_i >= count) return false;
    uint next = token_words[next_i].kind;
    bool tail = next == TK_LPAREN ||
        (next == TK_COLON && next_i + 1u < count && token_words[next_i + 1u].kind == TK_COLON) ||
        (next == TK_LBRACE && brace_semantic_kind[next_i] == TK_STRUCT_LIT_LBRACE);
    return tail && value_path_arguments_share_container(open_i, close_i);
}

uint direct_semantic_lt_kind_for(uint parser_i, uint count)
{
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    uint prev2_raw = raw_kind_at(parser_i - 2u, count);
    if (bound_type_context_before(parser_i, count))
        return TK_BOUND_TYPE_ARG_LT;
    if (prev_raw == TK_IMPL || prev2_raw == TK_FN || prev2_raw == TK_STRUCT ||
        prev2_raw == TK_ENUM || prev2_raw == TK_TRAIT || prev2_raw == TK_TYPE)
    {
        return TK_GENERIC_PARAM_LT;
    }
    if (prev_raw == TK_IDENT &&
        prev2_raw == TK_COLON &&
        semantic_colon_kind_for(parser_i - 2u, count) == TK_TYPE_COLON)
    {
        return TK_TYPE_ARG_LT;
    }
    if (prev_raw == TK_IDENT && parser_i > 0u &&
        raw_statement_context_kind(parser_i - 1u) == STATEMENT_CONTEXT_TYPE_ALIAS_RHS)
    {
        return TK_TYPE_ARG_LT;
    }
    // An enum payload's first type follows its opening parenthesis. The
    // enclosing declaration owns that type role, just as an annotation colon
    // does for function parameters. A value call's parenthesis supplies no
    // such evidence and must retain comparison/application disambiguation.
    if (prev_raw == TK_IDENT && prev2_raw == TK_LPAREN &&
        in_enum_variant_context(parser_i - 2u, count))
    {
        return TK_TYPE_ARG_LT;
    }
    if (prev_raw == TK_IDENT && value_expression_context_before(parser_i, count) &&
        (prev2_raw == TK_COLON || prev2_raw == TK_PATH_COLON ||
         (parser_i != 0u && value_path_type_arguments_have_tail(parser_i - 1u, count))))
    {
        return TK_PATH_TYPE_ARG_LT;
    }
    if (prev_raw == TK_IDENT &&
        (prev2_raw == TK_COLON || prev2_raw == TK_ARROW || prev2_raw == TK_AMPERSAND ||
         prev2_raw == TK_LT || prev2_raw == TK_COMMA ||
         (prev2_raw == TK_LBRACKET && parser_i >= 3u &&
          bracket_semantic_kind[parser_i - 3u] == TK_TYPE_ARRAY_LBRACKET) ||
         prev2_raw == TK_PATH_COLON || impl_type_context_before(parser_i, count)))
    {
        return TK_TYPE_ARG_LT;
    }
    return TK_LT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = tid.x;
    if (token_i >= gParams.token_capacity)
        return;
    uint count = min(lexer_token_count[0], gParams.token_capacity);
    uint kind = 0u;
    if (token_i < count && token_words[token_i].kind == TK_LT)
        kind = direct_semantic_lt_kind_for(token_i + 1u, count);
    token_direct_lt_kind[token_i] = kind;
}
