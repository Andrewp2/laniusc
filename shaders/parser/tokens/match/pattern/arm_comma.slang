// Which raw commas separate match arms. Included by the match-pattern passes
// after their depth helpers and enclosing_match_brace_before.
//
// A comma inside an arm's parentheses or brackets is not an arm separator, and
// neither is one inside generic arguments. Raw angle depth cannot decide the
// last case: a comparison `<` never closes and a comparison `>` closes some
// earlier `<`, so raw depths drift across arms and across the whole file. A
// comma is inside generic arguments only when an enclosing raw `<` opened
// inside the match braces and is an application's or a cast's type argument
// list, by the same lookahead tokens_to_angle_kinds uses.

StructuredBuffer<int> angle_match_depth;
StructuredBuffer<uint4> token_enclosing_open;
StructuredBuffer<uint> token_angle_close;
StructuredBuffer<uint> statement_context_kind;

static const uint ARM_COMMA_INVALID = 0xffffffffu;
static const uint ARM_TK_IDENT = 1u;
static const uint ARM_TK_LPAREN = 4u;
static const uint ARM_TK_LT = 12u;
static const uint ARM_TK_GT = 13u;
static const uint ARM_TK_COLON = 38u;
static const uint ARM_TK_SHR = 44u;
static const uint ARM_TK_STRUCT_LIT_LBRACE = 125u;
static const uint ARM_TK_AS = 195u;

uint arm_raw_kind(uint token_i)
{
    return token_i < active_token_count() ? token_words[token_i].kind : 0u;
}

// The raw `<` enclosing the token at token_i, or ARM_COMMA_INVALID.
uint enclosing_raw_angle(uint token_i)
{
    uint count = active_token_count();
    int depth = global_angle_depth_before_token(token_i);
    uint open_i = token_enclosing_open[token_i].w;
    if (open_i < count && token_words[open_i].kind == ARM_TK_LT && angle_match_depth[open_i] == depth - 1)
        return open_i;
    return ARM_COMMA_INVALID;
}

bool angle_pair_shares_containers(uint open_i, uint close_i)
{
    if (statement_context_kind[open_i] != statement_context_kind[close_i]) return false;
    if (global_paren_depth_before_token(open_i) != global_paren_depth_before_token(close_i) ||
        global_bracket_depth_before_token(open_i) != global_bracket_depth_before_token(close_i) ||
        global_brace_depth_before_token(open_i) != global_brace_depth_before_token(close_i)) return false;
    return all(token_enclosing_open[open_i].xyz == token_enclosing_open[close_i].xyz);
}

// `ident < ... >` directly followed by `(`, `::` or a struct literal's `{`.
bool angle_opens_application_arguments(uint open_i)
{
    uint count = active_token_count();
    if (open_i == 0u || arm_raw_kind(open_i - 1u) != ARM_TK_IDENT) return false;
    uint close_i = token_angle_close[open_i];
    if (close_i >= count || angle_match_depth[close_i] != angle_match_depth[open_i]) return false;
    uint close = token_words[close_i].kind;
    if (close != ARM_TK_GT && close != ARM_TK_SHR) return false;
    uint next = arm_raw_kind(close_i + 1u);
    bool tail = next == ARM_TK_LPAREN ||
        (next == ARM_TK_COLON && arm_raw_kind(close_i + 2u) == ARM_TK_COLON) ||
        brace_semantic_kind[close_i + 1u < count ? close_i + 1u : close_i] == ARM_TK_STRUCT_LIT_LBRACE;
    return tail && angle_pair_shares_containers(open_i, close_i);
}

// `as a::b::T<`: the path before the `<` follows `as`.
bool angle_opens_cast_arguments(uint open_i)
{
    if (open_i == 0u || arm_raw_kind(open_i - 1u) != ARM_TK_IDENT) return false;
    uint at = open_i - 1u;
    for (uint hop = 0u; hop < 16u; ++hop)
    {
        if (at < 3u || arm_raw_kind(at - 1u) != ARM_TK_COLON || arm_raw_kind(at - 2u) != ARM_TK_COLON ||
            arm_raw_kind(at - 3u) != ARM_TK_IDENT) break;
        at -= 3u;
    }
    return at > 0u && arm_raw_kind(at - 1u) == ARM_TK_AS;
}

bool inside_arm_type_arguments(uint token_i, uint brace_open_i)
{
    uint at = enclosing_raw_angle(token_i);
    for (uint hop = 0u; hop < 32u; ++hop)
    {
        if (at == ARM_COMMA_INVALID || at <= brace_open_i) return false;
        if (angle_opens_application_arguments(at) || angle_opens_cast_arguments(at)) return true;
        at = enclosing_raw_angle(at);
    }
    return false;
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
           !inside_arm_type_arguments(token_i, open_i);
}
