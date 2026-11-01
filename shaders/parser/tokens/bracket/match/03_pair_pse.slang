// Classifies raw `[`, `]`, and the `,`/`;` they directly own: type array,
// index, or array literal.
//
// Every delimiter relation is read from token_enclosing_open (x paren, y
// brace, z bracket, w angle) and token_angle_close, published once per token
// by tokens_delimiter_match_03_enclosing_opens, so this pass does no
// hierarchy searches and keeps no per-thread arrays.
//
// For a token t with class depth D before it, token_enclosing_open[t] is the
// last earlier row whose match depth is at most D - 1. When that row is a raw
// opener of the class it encloses t at depth D - 1 (no row between them can
// reach depth D - 1 without lowering the match depth to it). A raw `]` has
// match depth D - 1, so its enclosing bracket row is the `[` it closes.

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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<uint4> token_enclosing_open;
StructuredBuffer<uint> token_angle_close;
StructuredBuffer<uint> brace_semantic_kind;
StructuredBuffer<uint> statement_context_kind;
StructuredBuffer<uint> token_impl_context_event;

RWStructuredBuffer<uint> bracket_semantic_kind;

static const uint WG_SIZE = 256u;
static const int INF = 2147483647;
static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_MUT = 203u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_SHR = 44u;
static const uint TK_ARROW = 75u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_ARRAY_SEMICOLON = 198u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

#include "../../impl/header/context.slang"

[ForceInline]
uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

int paren_depth_at(uint token_i)
{
    return block_prefix_paren[token_i / WG_SIZE] + depth_paren_inblock[token_i];
}

int brace_depth_at(uint token_i)
{
    return block_prefix_brace[token_i / WG_SIZE] + depth_brace_inblock[token_i];
}

int bracket_depth_at(uint token_i)
{
    return block_prefix_bracket[token_i / WG_SIZE] + depth_bracket_inblock[token_i];
}

int angle_depth_at(uint token_i)
{
    return block_prefix_angle[token_i / WG_SIZE] + depth_angle_inblock[token_i];
}

// The raw `[` enclosing token_i.
bool nearest_bracket_open_before(uint token_i, out uint open_i)
{
    open_i = token_enclosing_open[token_i].z;
    return bracket_depth_at(token_i) > 0 &&
           open_i < active_token_count() &&
           token_words[open_i].kind == TK_LBRACKET;
}

// The raw `(` enclosing token_i.
bool nearest_paren_open_before(uint token_i, out uint open_i)
{
    open_i = token_enclosing_open[token_i].x;
    return paren_depth_at(token_i) > 0 &&
           open_i < active_token_count() &&
           token_words[open_i].kind == TK_LPAREN;
}

// The recorded semantic kind of the raw `{` enclosing token_i, or 0.
uint enclosing_semantic_brace_open_before(uint token_i)
{
    if (brace_depth_at(token_i) <= 0)
        return 0u;
    uint open_i = token_enclosing_open[token_i].y;
    if (open_i >= active_token_count() || token_words[open_i].kind != TK_LBRACE)
        return 0u;
    return brace_semantic_kind[open_i];
}

bool inside_enum_payload_parens(uint token_i)
{
    uint open_i;
    if (!nearest_paren_open_before(token_i, open_i))
        return false;
    if (open_i == 0u || token_words[open_i - 1u].kind != TK_IDENT)
        return false;

    return enclosing_semantic_brace_open_before(open_i) == TK_ENUM_LBRACE;
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

// Raw token ids (generated_token_ids.slang).
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_OROR = 18u;
static const uint TK_NOT_EQUAL = 40u;

// Type and constant arguments hold no comparison or `||`, so in
// `a<b || c>(d)` both angles stay comparisons. `&&` can begin `&&T`. Long
// argument lists are scanned for their first 64 tokens.
bool value_path_arguments_are_operator_free(uint open_i, uint close_i)
{
    uint end = min(close_i, open_i + 64u);
    for (uint at = open_i + 1u; at < end; ++at)
    {
        uint kind = token_words[at].kind;
        if (kind == TK_OROR || kind == TK_EQEQ || kind == TK_NOT_EQUAL ||
            kind == TK_LE || kind == TK_GE) return false;
    }
    return true;
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
    return tail && value_path_arguments_share_container(open_i, close_i) &&
        value_path_arguments_are_operator_free(open_i, close_i);
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
           prev2 == TK_LBRACKET ||
           value_path_type_arguments_have_tail(open_i, active_token_count());
}

// Whether token_i sits directly in a raw `<` list that can hold type
// arguments. token_i is never a raw `>>`, so its published angle row is
// queried one level down.
bool inside_type_arg_angle(uint token_i)
{
    int angle_depth_before = angle_depth_at(token_i);
    if (angle_depth_before <= 0)
        return false;

    uint open_i = token_enclosing_open[token_i].w;
    if (open_i >= active_token_count() ||
        token_words[open_i].kind != TK_LT ||
        angle_match_depth[open_i] != angle_depth_before - 1)
        return false;

    return raw_angle_open_can_start_type_args(open_i);
}

bool type_array_open_context(uint token_i)
{
    // Nested openers, their separators, and their closers run in parallel.
    // Derive inherited type context from immutable tokens and delimiter
    // ownership instead of reading another lane's bracket-kind publication.
    uint count = active_token_count();
    if (token_is_in_impl_header(token_i, count)) return true;
    uint current = token_i;
    for (uint guard = 0u; guard < count; guard++)
    {
        uint prev = current == 0u ? 0u : token_words[current - 1u].kind;
        if (prev == TK_COLON || prev == TK_ARROW)
        {
            // Both punctuation forms introduce types elsewhere. Their brace
            // owner identifies field values and match results before semantic
            // retagging, including nested array literals in those expressions.
            uint owner = enclosing_semantic_brace_open_before(current);
            if ((prev == TK_COLON && owner == TK_STRUCT_LIT_LBRACE) ||
                (prev == TK_ARROW && owner == TK_MATCH_LBRACE)) return false;
        }
        if ((statement_context_kind[current] & 0xffu) == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ||
            prev == TK_COLON || prev == TK_ARROW || prev == TK_AMPERSAND || prev == TK_MUT)
            return true;
        if (inside_type_arg_angle(current) && (prev == TK_LT || prev == TK_COMMA))
            return true;
        if (inside_enum_payload_parens(current)) return true;
        uint outer;
        if (!nearest_bracket_open_before(current, outer) || outer >= current)
            return false;
        current = outer;
    }
    return false;
}

uint bracket_open_kind(uint token_i)
{
    uint prev = token_i == 0u ? 0u : token_words[token_i - 1u].kind;
    if (prev == TK_RBRACE && brace_semantic_kind[token_i - 1u] == TK_STRUCT_LIT_RBRACE)
        return TK_INDEX_LBRACKET;
    if (type_array_open_context(token_i)) return TK_TYPE_ARRAY_LBRACKET;
    bool ends_primary = prev == TK_IDENT || prev == TK_INT || prev == TK_RPAREN ||
        prev == TK_RBRACKET || prev == TK_STRING || prev == TK_FLOAT ||
        prev == TK_CHAR || prev == TK_TRUE || prev == TK_FALSE || prev == TK_SELF_VALUE;
    return ends_primary ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
}

bool nearest_bracket_open_kind_before(uint token_i, uint wanted_kind)
{
    uint open_i;
    return nearest_bracket_open_before(token_i, open_i) &&
        bracket_open_kind(open_i) == wanted_kind;
}

// A `;` whose innermost enclosing delimiter is an array literal's `[`
// separates the repeated value from the count in `[value; count]`. A `;` in
// a block or a parenthesis inside the brackets belongs to that block.
bool array_repeat_semicolon(uint token_i)
{
    uint open_i;
    if (!nearest_bracket_open_before(token_i, open_i) ||
        bracket_open_kind(open_i) != TK_ARRAY_LBRACKET)
        return false;
    uint count = active_token_count();
    uint4 enclosing = token_enclosing_open[token_i];
    if (paren_depth_at(token_i) > 0 && enclosing.x < count && enclosing.x > open_i)
        return false;
    if (brace_depth_at(token_i) > 0 && enclosing.y < count && enclosing.y > open_i)
        return false;
    return true;
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
    if (raw_kind == TK_LBRACKET)
    {
        bracket_semantic_kind[token_i] = bracket_open_kind(token_i);
        return;
    }

    if (raw_kind == TK_COMMA || raw_kind == TK_SEMICOLON)
    {
        if (raw_kind == TK_COMMA &&
            nearest_bracket_open_kind_before(token_i, TK_ARRAY_LBRACKET))
            bracket_semantic_kind[token_i] = TK_ARRAY_COMMA;
        if (raw_kind == TK_SEMICOLON &&
            nearest_bracket_open_kind_before(token_i, TK_TYPE_ARRAY_LBRACKET))
            bracket_semantic_kind[token_i] = TK_TYPE_SEMICOLON;
        if (raw_kind == TK_SEMICOLON && array_repeat_semicolon(token_i))
            bracket_semantic_kind[token_i] = TK_ARRAY_SEMICOLON;
        return;
    }

    if (raw_kind != TK_RBRACKET)
        return;

    // The closer's match depth is its depth before minus one, which is the
    // published bracket query, so its enclosing row is the opener it closes
    // (with no depth guard, as unbalanced input pairs the same way).
    uint open_i = token_enclosing_open[token_i].z;
    if (open_i >= count || token_words[open_i].kind != TK_LBRACKET)
        return;

    bracket_semantic_kind[token_i] = close_kind_for_open_kind(bracket_open_kind(open_i));
}
