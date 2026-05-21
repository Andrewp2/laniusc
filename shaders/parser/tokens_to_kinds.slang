import atomics;
import segment_tree;
import token_features;

struct Params
{
    uint token_capacity;
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
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> brace_match_depth;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> brace_match_min_tree;

RWStructuredBuffer<uint> semantic_token_kinds;
RWStructuredBuffer<uint> parser_token_count;
RWStructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> brace_semantic_kind;
StructuredBuffer<uint> bracket_semantic_kind;
StructuredBuffer<uint> statement_context_kind;
groupshared uint group_feature_flags[256];

static const uint WG_SIZE = 256u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_PLUS = 6u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_MINUS = 27u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_DOT = 35u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_INC = 56u;
static const uint TK_DEC = 57u;
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_PUB = 66u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_WHERE = 104u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_DECL_ASSIGN = 106u;
static const uint TK_BOUND_COLON = 107u;
static const uint TK_TYPE_COLON = 108u;
static const uint TK_MEMBER_IDENT = 109u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
static const uint TK_CONST_ASSIGN = 111u;
static const uint TK_RETURN_ARROW = 112u;
static const uint TK_MATCH_ARROW = 113u;
static const uint TK_PATH_COLON = 114u;
static const uint TK_PREFIX_INC = 115u;
static const uint TK_POSTFIX_INC = 116u;
static const uint TK_PREFIX_DEC = 117u;
static const uint TK_POSTFIX_DEC = 118u;
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
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_TYPE_ARG_COMMA = 135u;
static const uint TK_GENERIC_PARAM_COMMA = 136u;
static const uint TK_ENUM_FIELD_COMMA = 137u;
static const uint TK_MATCH_ARM_COMMA = 138u;
static const uint TK_PATTERN_COMMA = 139u;
static const uint TK_PATTERN_LPAREN = 140u;
static const uint TK_PATTERN_RPAREN = 141u;
static const uint TK_ENUM_PAYLOAD_LPAREN = 142u;
static const uint TK_ENUM_PAYLOAD_RPAREN = 143u;
static const uint TK_TYPE_AMPERSAND = 144u;
static const uint TK_BOUND_PLUS = 145u;
static const uint TK_TRAIT_METHOD_SEMICOLON = 146u;
static const uint TK_IMPL_PUB = 147u;
static const uint TK_TRAIT_PUB = 148u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_FN_BLOCK_RBRACE = 150u;
static const uint TK_IMPL_FN_BLOCK_LBRACE = 151u;
static const uint TK_IMPL_FN_BLOCK_RBRACE = 152u;
static const uint TK_TYPE_ALIAS_NAME_IDENT = 153u;
static const uint TK_TRAIT_NAME_IDENT = 154u;
static const uint TK_GENERIC_PARAM_IDENT = 155u;
static const uint TK_WHERE_IDENT = 156u;
static const uint TK_WHERE_COMMA = 157u;
static const uint TK_ENUM_VARIANT_COMMA = 158u;
static const uint TK_STRUCT_FIELD_COMMA = 159u;
static const uint TK_STRUCT_LIT_COMMA = 160u;
static const uint TK_IMPORT_STRING = 161u;
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
static const uint TK_IMPL_FOR = 172u;
static const uint TK_PARAM_SELF_VALUE = 173u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_BOUND_TYPE_ARG_COMMA = 177u;
static const uint TK_PARAM_SELF_REF_VALUE = 178u;
static const uint TK_BOUND_TYPE_AMPERSAND = 179u;
static const uint TK_INHERENT_IMPL = 180u;
static const uint TK_TRAIT_IMPL = 181u;

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gParams.token_capacity == 0u ? 1u : (gParams.token_capacity + WG_SIZE - 1u) / WG_SIZE;
    }

    public static uint leaf_base()
    {
        uint n_blocks = gParams.token_capacity == 0u ? 1u : (gParams.token_capacity + WG_SIZE - 1u) / WG_SIZE;
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

public struct BraceDepthRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return gParams.token_capacity;
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

bool semantic_token_ends_primary(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_INT ||
           kind == TK_RPAREN ||
           kind == TK_RBRACKET ||
           kind == TK_GROUP_RPAREN ||
           kind == TK_CALL_RPAREN ||
           kind == TK_ARRAY_RBRACKET ||
           kind == TK_INDEX_RBRACKET ||
           kind == TK_TYPE_ARRAY_RBRACKET ||
           kind == TK_PATTERN_RPAREN ||
           kind == TK_ENUM_PAYLOAD_RPAREN ||
           kind == TK_STRING ||
           kind == TK_FLOAT ||
           kind == TK_CHAR ||
           kind == TK_TRUE ||
           kind == TK_FALSE ||
           kind == TK_SELF_VALUE;
}

bool is_lparen_kind(uint kind)
{
    return kind == TK_LPAREN ||
           kind == TK_GROUP_LPAREN ||
           kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN ||
           kind == TK_PATTERN_LPAREN ||
           kind == TK_ENUM_PAYLOAD_LPAREN;
}

bool is_rparen_kind(uint kind)
{
    return kind == TK_RPAREN ||
           kind == TK_GROUP_RPAREN ||
           kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN ||
           kind == TK_PATTERN_RPAREN ||
           kind == TK_ENUM_PAYLOAD_RPAREN;
}

uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

bool is_statement_boundary(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE || kind == 0u;
}

bool type_context_before(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_AMPERSAND;
}

bool in_pattern_context(uint parser_i, uint count);
bool top_level_match_arm_comma(uint parser_i, uint count);
bool in_enum_variant_context(uint parser_i, uint count);
uint semantic_prev_kind(uint parser_i, uint count);
uint semantic_brace_open_kind_for(uint parser_i, uint count);
uint enclosing_semantic_brace_open_before(uint parser_i, uint count);
bool enclosing_raw_brace_owner_is(uint parser_i, uint count, uint owner);
uint matching_semantic_brace_open_before(uint parser_i, uint count);
bool bound_colon_context(uint parser_i, uint count);
bool bound_plus_context(uint parser_i, uint count);
bool bound_type_context_before(uint parser_i, uint count);
bool impl_type_context_before(uint parser_i, uint count);

bool fn_param_lparen_context(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    if (prev2 == TK_FN && prev == TK_IDENT)
        return true;

    if (prev != TK_GT)
        return false;

    uint depth = 0u;
    uint j = parser_i - 1u;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        uint kind = raw_kind_at(j, count);
        if (kind == TK_GT)
        {
            depth += 1u;
        }
        else if (kind == TK_LT)
        {
            if (depth == 1u)
            {
                return semantic_lt_kind_for(j, count) == TK_GENERIC_PARAM_LT &&
                       raw_kind_at(j - 1u, count) == TK_IDENT &&
                       raw_kind_at(j - 2u, count) == TK_FN;
            }
            if (depth == 0u)
                return false;
            depth -= 1u;
        }
        j -= 1u;
    }
    return false;
}

uint semantic_open_kind_for(uint parser_i, uint count, uint raw_kind)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    bool prev_ends_primary = semantic_token_ends_primary(prev);

    if (raw_kind == TK_LPAREN)
    {
        if (in_pattern_context(parser_i, count))
            return TK_PATTERN_LPAREN;
        if (in_enum_variant_context(parser_i, count) && prev == TK_IDENT)
            return TK_ENUM_PAYLOAD_LPAREN;
        if (fn_param_lparen_context(parser_i, count))
            return TK_PARAM_LPAREN;
        return prev_ends_primary ? TK_CALL_LPAREN : TK_GROUP_LPAREN;
    }
    if (raw_kind == TK_LBRACKET)
    {
        uint recorded = bracket_semantic_kind[parser_i - 1u];
        return recorded != 0u ? recorded : TK_LBRACKET;
    }

    return raw_kind;
}

bool raw_kind_starts_item(uint kind)
{
    return kind == TK_FN || kind == TK_CONST || kind == TK_TYPE ||
           kind == TK_ENUM || kind == TK_STRUCT || kind == TK_IMPL ||
           kind == TK_TRAIT;
}

bool scan_context_before(
    uint parser_i,
    uint count,
    uint wanted,
    uint stop_a,
    uint stop_b,
    uint stop_c)
{
    uint j = parser_i;
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_RPAREN)
        {
            paren_depth += 1u;
            continue;
        }
        if (kind == TK_LPAREN && paren_depth > 0u)
        {
            paren_depth -= 1u;
            continue;
        }
        if (kind == TK_RBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACKET && bracket_depth > 0u)
        {
            bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_RBRACE)
        {
            brace_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACE && brace_depth > 0u)
        {
            brace_depth -= 1u;
            continue;
        }
        if (paren_depth != 0u || bracket_depth != 0u || brace_depth != 0u)
            continue;
        if (kind == wanted)
            return true;
        if (kind == stop_a || kind == stop_b || kind == stop_c || is_statement_boundary(kind))
            return false;
    }
    return false;
}

bool in_enum_variant_context(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count) == TK_ENUM_LBRACE;
}

bool in_pattern_context(uint parser_i, uint count)
{
    if (!enclosing_raw_brace_owner_is(parser_i, count, TK_MATCH))
        return false;

    uint j = parser_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_ARROW)
            return false;
        if (kind == TK_LBRACE || top_level_match_arm_comma(j, count))
            return true;
        if (kind == TK_SEMICOLON)
            return false;
    }
    return false;
}

bool top_level_match_arm_comma(uint parser_i, uint count)
{
    if (raw_kind_at(parser_i, count) != TK_COMMA)
        return false;

    uint j = parser_i;
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 1024u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_RPAREN)
        {
            paren_depth += 1u;
            continue;
        }
        if (kind == TK_LPAREN)
        {
            if (paren_depth == 0u)
                return false;
            paren_depth -= 1u;
            continue;
        }
        if (kind == TK_RBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACKET)
        {
            if (bracket_depth == 0u)
                return false;
            bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_RBRACE)
        {
            brace_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACE)
        {
            if (brace_depth > 0u)
            {
                brace_depth -= 1u;
                continue;
            }
            return scan_context_before(j, count, TK_MATCH, TK_SEMICOLON, TK_FN, TK_IMPL);
        }
    }
    return false;
}

bool enclosing_raw_brace_owner_is(uint parser_i, uint count, uint owner)
{
    uint open_kind = enclosing_semantic_brace_open_before(parser_i, count);
    if (owner == TK_MATCH)
        return open_kind == TK_MATCH_LBRACE;
    if (owner == TK_IMPL)
        return open_kind == TK_IMPL_LBRACE;
    if (owner == TK_TRAIT)
        return open_kind == TK_TRAIT_LBRACE;
    if (owner == TK_STRUCT)
        return open_kind == TK_STRUCT_DECL_LBRACE || open_kind == TK_STRUCT_LIT_LBRACE;
    if (owner == TK_ENUM)
        return open_kind == TK_ENUM_LBRACE;
    return false;
}

bool in_trait_body_context(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count) == TK_TRAIT_LBRACE;
}

uint matching_semantic_open_before(uint parser_i, uint count, uint raw_open, uint raw_close)
{
    uint depth = 0u;
    uint j = parser_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == raw_close)
        {
            depth += 1u;
            continue;
        }
        if (kind != raw_open)
            continue;
        if (depth == 0u)
            return semantic_open_kind_for(j, count, kind);
        depth -= 1u;
    }
    return 0u;
}

uint semantic_close_kind_for(uint parser_i, uint count, uint raw_kind)
{
    if (raw_kind == TK_RPAREN)
    {
        uint open_kind = matching_semantic_open_before(parser_i, count, TK_LPAREN, TK_RPAREN);
        if (open_kind == TK_PARAM_LPAREN)
            return TK_PARAM_RPAREN;
        if (open_kind == TK_CALL_LPAREN)
            return TK_CALL_RPAREN;
        if (open_kind == TK_GROUP_LPAREN)
            return TK_GROUP_RPAREN;
        if (open_kind == TK_PATTERN_LPAREN)
            return TK_PATTERN_RPAREN;
        if (open_kind == TK_ENUM_PAYLOAD_LPAREN)
            return TK_ENUM_PAYLOAD_RPAREN;
    }

    if (raw_kind == TK_RBRACKET)
    {
        uint recorded = bracket_semantic_kind[parser_i - 1u];
        if (recorded != 0u)
            return recorded;
        return TK_RBRACKET;
    }

    return raw_kind;
}

uint semantic_brace_open_kind_for(uint parser_i, uint count)
{
    uint recorded = brace_semantic_kind[parser_i - 1u];
    if (recorded != 0u)
        return recorded;

    // Brace classification is owned by tokens_delimiters_03_owner_local plus
    // tokens_brace_context. If no record exists, preserve the raw token rather
    // than rediscovering ownership with another local source-token walk.
    return TK_LBRACE;
}

uint matching_semantic_brace_open_before(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count);
}

uint semantic_brace_close_kind_for(uint parser_i, uint count)
{
    uint recorded = brace_semantic_kind[parser_i - 1u];
    if (recorded != 0u)
        return recorded;

    // Brace-close ownership is produced by the token brace PSE pairing passes.
    // Missing records remain raw instead of running a second per-token matching
    // search here.
    return TK_RBRACE;
}

int global_brace_depth_before(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0;
    uint token_i = parser_i - 1u;
    if (token_i >= gParams.token_capacity)
        return 0;
    uint block_i = token_i / WG_SIZE;
    return block_prefix_brace[block_i] + depth_brace_inblock[token_i];
}

uint enclosing_semantic_brace_open_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return 0u;
    uint token_i = parser_i - 1u;
    if (token_i >= count || token_i >= gParams.token_capacity)
        return 0u;

    int depth_before = global_brace_depth_before(parser_i, count);
    if (depth_before <= 0)
        return 0u;

    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            BraceDepthTree,
            BraceDepthRows,
            BraceDepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return 0u;

    if (open_i >= count || token_words[open_i].kind != TK_LBRACE)
        return 0u;

    uint semantic_kind = brace_semantic_kind[open_i];
    return semantic_kind != 0u ? semantic_kind : semantic_brace_open_kind_for(open_i + 1u, count);
}

bool bound_type_context_before(uint parser_i, uint count)
{
    uint j = parser_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_COLON && bound_colon_context(j, count))
            return true;
        if (kind == TK_PLUS && bound_plus_context(j, count))
            return true;
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE ||
            kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
            return false;
    }
    return false;
}

uint semantic_lt_kind_for(uint parser_i, uint count)
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
        (prev2_raw == TK_COLON || prev2_raw == TK_ARROW || prev2_raw == TK_AMPERSAND ||
         prev2_raw == TK_LT || prev2_raw == TK_COMMA || prev2_raw == TK_LBRACKET ||
         prev2_raw == TK_PATH_COLON || impl_type_context_before(parser_i, count)))
    {
        return TK_TYPE_ARG_LT;
    }
    return TK_LT;
}

bool impl_type_context_before(uint parser_i, uint count)
{
    uint j = parser_i;
    uint angle_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_GT)
        {
            angle_depth += 1u;
            continue;
        }
        if (kind == TK_LT && angle_depth > 0u)
        {
            angle_depth -= 1u;
            continue;
        }
        if (angle_depth != 0u)
            continue;

        if (kind == TK_IMPL)
            return true;
        if (kind == TK_FOR)
            return scan_context_before(j, count, TK_IMPL, TK_SEMICOLON, TK_LBRACE, TK_RBRACE);
        if (kind == TK_LBRACE || kind == TK_RBRACE || kind == TK_SEMICOLON || kind == TK_FN)
            return false;
    }
    return false;
}

uint matching_semantic_angle_open_before(uint parser_i, uint count)
{
    uint depth = 0u;
    uint j = parser_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_GT)
        {
            depth += 1u;
            continue;
        }
        if (kind != TK_LT)
            continue;
        if (depth == 0u)
            return semantic_lt_kind_for(j, count);
        depth -= 1u;
    }
    return 0u;
}

uint semantic_gt_kind_for(uint parser_i, uint count)
{
    uint open_kind = matching_semantic_angle_open_before(parser_i, count);
    if (open_kind == TK_TYPE_ARG_LT)
        return TK_TYPE_ARG_GT;
    if (open_kind == TK_GENERIC_PARAM_LT)
        return TK_GENERIC_PARAM_GT;
    if (open_kind == TK_BOUND_TYPE_ARG_LT)
        return TK_BOUND_TYPE_ARG_GT;
    return TK_GT;
}

uint semantic_comma_kind_for(uint parser_i, uint count)
{
    uint paren_open = matching_semantic_open_before(parser_i, count, TK_LPAREN, TK_RPAREN);
    uint angle_open = matching_semantic_angle_open_before(parser_i, count);
    if (angle_open == TK_TYPE_ARG_LT)
        return TK_TYPE_ARG_COMMA;
    if (angle_open == TK_GENERIC_PARAM_LT)
        return TK_GENERIC_PARAM_COMMA;
    if (angle_open == TK_BOUND_TYPE_ARG_LT)
        return TK_BOUND_TYPE_ARG_COMMA;
    if (paren_open == TK_PARAM_LPAREN)
        return TK_PARAM_COMMA;
    if (paren_open == TK_CALL_LPAREN)
        return TK_ARG_COMMA;
    if (paren_open == TK_PATTERN_LPAREN)
        return TK_PATTERN_COMMA;
    if (paren_open == TK_ENUM_PAYLOAD_LPAREN)
        return TK_ENUM_FIELD_COMMA;
    if (bracket_semantic_kind[parser_i - 1u] == TK_ARRAY_COMMA)
        return TK_ARRAY_COMMA;
    uint brace_open = matching_semantic_brace_open_before(parser_i, count);
    if (brace_open == TK_MATCH_LBRACE)
        return TK_MATCH_ARM_COMMA;
    if (brace_open == TK_ENUM_LBRACE)
        return TK_ENUM_VARIANT_COMMA;
    if (brace_open == TK_STRUCT_DECL_LBRACE)
        return TK_STRUCT_FIELD_COMMA;
    if (brace_open == TK_STRUCT_LIT_LBRACE)
        return TK_STRUCT_LIT_COMMA;
    if (scan_context_before(parser_i, count, TK_WHERE, TK_SEMICOLON, TK_LBRACE, TK_RBRACE))
        return TK_WHERE_COMMA;
    return TK_COMMA;
}

bool bound_colon_context(uint parser_i, uint count)
{
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    if (prev2 == TK_CONST)
        return false;

    uint j = parser_i;
    uint angle_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_GT)
        {
            angle_depth += 1u;
            continue;
        }
        if (kind == TK_LT && angle_depth > 0u)
        {
            angle_depth -= 1u;
            continue;
        }
        if (angle_depth > 0u)
            continue;
        if (kind == TK_WHERE || kind == TK_LT)
            return true;
        if (is_statement_boundary(kind) || kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
            return false;
    }
    return false;
}

uint semantic_colon_kind_for(uint parser_i, uint count)
{
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    uint next_raw = raw_kind_at(parser_i + 1u, count);
    if (prev_raw == TK_COLON || next_raw == TK_COLON)
        return TK_PATH_COLON;
    if (matching_semantic_brace_open_before(parser_i, count) == TK_STRUCT_LIT_LBRACE)
        return TK_COLON;
    if (bound_colon_context(parser_i, count))
        return TK_BOUND_COLON;
    return TK_TYPE_COLON;
}

uint semantic_assign_kind_for(uint parser_i, uint count)
{
    uint statement_context = parser_i == 0u ? 0u : statement_context_kind[parser_i - 1u];
    if (statement_context == TK_LET)
        return TK_LET_ASSIGN;
    if (statement_context == TK_TYPE)
        return TK_TYPE_ALIAS_ASSIGN;
    if (statement_context == TK_CONST)
        return TK_CONST_ASSIGN;
    return TK_ASSIGN;
}

uint semantic_arrow_kind_for(uint parser_i, uint count)
{
    if (matching_semantic_brace_open_before(parser_i, count) == TK_MATCH_LBRACE)
        return TK_MATCH_ARROW;
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    if (prev_raw == TK_RPAREN || prev_raw == TK_GT)
        return TK_RETURN_ARROW;
    return TK_MATCH_ARROW;
}

bool bound_plus_context(uint parser_i, uint count)
{
    uint j = parser_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_COLON)
            return true;
        if (kind == TK_ASSIGN)
            return false;
        if (is_statement_boundary(kind) || kind == TK_LPAREN)
            return false;
    }
    return false;
}

uint semantic_plus_kind_for(uint parser_i, uint count)
{
    if (bound_plus_context(parser_i, count))
        return TK_BOUND_PLUS;
    return semantic_token_ends_primary(raw_kind_at(parser_i - 1u, count))
        ? TK_INFIX_PLUS
        : TK_PREFIX_PLUS;
}

uint semantic_ampersand_kind_for(uint parser_i, uint count)
{
    if (bound_type_context_before(parser_i, count))
        return TK_BOUND_TYPE_AMPERSAND;
    return semantic_token_ends_primary(raw_kind_at(parser_i - 1u, count))
        ? TK_AMPERSAND
        : TK_TYPE_AMPERSAND;
}

uint semantic_inc_dec_kind_for(uint parser_i, uint raw_kind, uint count)
{
    bool postfix = semantic_token_ends_primary(raw_kind_at(parser_i - 1u, count));
    if (raw_kind == TK_INC)
        return postfix ? TK_POSTFIX_INC : TK_PREFIX_INC;
    return postfix ? TK_POSTFIX_DEC : TK_PREFIX_DEC;
}

uint semicolon_kind_for_statement_context(uint statement_kind)
{
    if (statement_kind == TK_IMPORT)
        return TK_IMPORT_SEMICOLON;
    if (statement_kind == TK_MODULE)
        return TK_MODULE_SEMICOLON;
    if (statement_kind == TK_EXTERN)
        return TK_EXTERN_SEMICOLON;
    if (statement_kind == TK_TYPE)
        return TK_TYPE_ALIAS_SEMICOLON;
    if (statement_kind == TK_CONST)
        return TK_CONST_SEMICOLON;
    if (statement_kind == TK_LET)
        return TK_LET_SEMICOLON;
    if (statement_kind == TK_RETURN)
        return TK_RETURN_SEMICOLON;
    if (statement_kind == TK_BREAK)
        return TK_BREAK_SEMICOLON;
    if (statement_kind == TK_CONTINUE)
        return TK_CONTINUE_SEMICOLON;
    return 0u;
}

uint semantic_semicolon_kind_for(uint parser_i, uint count)
{
    uint recorded = semicolon_kind_for_statement_context(statement_context_kind[parser_i - 1u]);
    if (recorded != 0u)
        return recorded;

    if (bracket_semantic_kind[parser_i - 1u] == TK_TYPE_SEMICOLON)
        return TK_TYPE_SEMICOLON;
    if (in_trait_body_context(parser_i, count))
        return TK_TRAIT_METHOD_SEMICOLON;

    return TK_EXPR_SEMICOLON;
}

uint semantic_impl_kind_for(uint parser_i, uint count)
{
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    uint angle_depth = 0u;
    [loop]
    for (uint guard = 1u; guard < 1024u && parser_i + guard <= count; guard += 1u)
    {
        uint kind = raw_kind_at(parser_i + guard, count);
        if (kind == TK_LPAREN)
            paren_depth += 1u;
        else if (kind == TK_RPAREN && paren_depth > 0u)
            paren_depth -= 1u;
        else if (kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if (kind == TK_RBRACKET && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (paren_depth == 0u && bracket_depth == 0u && angle_depth == 0u)
        {
            if (kind == TK_FOR)
                return TK_TRAIT_IMPL;
            if (kind == TK_LBRACE || kind == TK_SEMICOLON || kind == TK_RBRACE)
                return TK_INHERENT_IMPL;
        }
    }
    return TK_INHERENT_IMPL;
}

uint semantic_prev_kind(uint parser_i, uint count)
{
    uint raw = raw_kind_at(parser_i, count);
    if (raw == TK_LPAREN || raw == TK_LBRACKET)
        return semantic_open_kind_for(parser_i, count, raw);
    if (raw == TK_RPAREN || raw == TK_RBRACKET)
        return semantic_close_kind_for(parser_i, count, raw);
    if (raw == TK_LBRACE)
        return semantic_brace_open_kind_for(parser_i, count);
    if (raw == TK_RBRACE)
        return semantic_brace_close_kind_for(parser_i, count);
    if (raw == TK_COMMA)
        return semantic_comma_kind_for(parser_i, count);
    if (raw == TK_COLON)
        return semantic_colon_kind_for(parser_i, count);
    if (raw == TK_LT)
        return semantic_lt_kind_for(parser_i, count);
    if (raw == TK_GT)
        return semantic_gt_kind_for(parser_i, count);
    if (raw == TK_ARROW)
        return semantic_arrow_kind_for(parser_i, count);
    if (raw == TK_ASSIGN)
        return semantic_assign_kind_for(parser_i, count);
    if (raw == TK_PLUS)
        return semantic_plus_kind_for(parser_i, count);
    if (raw == TK_AMPERSAND)
        return semantic_ampersand_kind_for(parser_i, count);
    if (raw == TK_INC || raw == TK_DEC)
        return semantic_inc_dec_kind_for(parser_i, raw, count);
    if (raw == TK_SEMICOLON)
        return semantic_semicolon_kind_for(parser_i, count);
    return raw;
}

uint semantic_kind_for(uint parser_i, uint count, uint raw_kind)
{
    if (raw_kind == TK_IDENT)
    {
        uint prev_raw = raw_kind_at(parser_i - 1u, count);
        if (prev_raw == TK_DOT)
            return TK_MEMBER_IDENT;
        if (prev_raw == TK_LET)
            return TK_LET_IDENT;
        if (prev_raw == TK_TYPE)
            return TK_TYPE_ALIAS_NAME_IDENT;
        if (prev_raw == TK_TRAIT)
            return TK_TRAIT_NAME_IDENT;
        if (prev_raw == TK_WHERE)
            return TK_WHERE_IDENT;

        uint prev = semantic_prev_kind(parser_i - 1u, count);
        if (prev == TK_GENERIC_PARAM_LT || prev == TK_GENERIC_PARAM_COMMA)
            return TK_GENERIC_PARAM_IDENT;
        if (prev == TK_WHERE_COMMA)
            return TK_WHERE_IDENT;
        if (prev == TK_BOUND_COLON || prev == TK_BOUND_PLUS ||
            prev == TK_BOUND_TYPE_ARG_LT || prev == TK_BOUND_TYPE_ARG_COMMA)
            return TK_BOUND_TYPE_IDENT;
        if (prev_raw == TK_IMPL || prev_raw == TK_FOR ||
            prev == TK_GENERIC_PARAM_GT || impl_type_context_before(parser_i, count))
        {
            if (impl_type_context_before(parser_i, count))
                return TK_TYPE_IDENT;
        }
        if (prev == TK_PARAM_LPAREN || prev == TK_PARAM_COMMA)
            return TK_PARAM_IDENT;
        if (prev == TK_TYPE_ARRAY_LBRACKET)
            return TK_TYPE_IDENT;
        if (prev == TK_ENUM_PAYLOAD_LPAREN || prev == TK_ENUM_FIELD_COMMA)
            return TK_TYPE_IDENT;
        if (prev == TK_TYPE_COLON || prev == TK_BOUND_COLON || prev == TK_RETURN_ARROW ||
            prev == TK_TYPE_ALIAS_ASSIGN || prev == TK_TYPE_AMPERSAND ||
            prev == TK_TYPE_ARG_LT || prev == TK_TYPE_ARG_COMMA || prev == TK_GENERIC_PARAM_LT ||
            prev == TK_GENERIC_PARAM_COMMA || prev == TK_TYPE_ARRAY_LBRACKET)
            return TK_TYPE_IDENT;
        return TK_IDENT;
    }

    if (raw_kind == TK_SELF_VALUE)
    {
        uint prev = semantic_prev_kind(parser_i - 1u, count);
        if (prev == TK_TYPE_AMPERSAND)
            return TK_PARAM_SELF_REF_VALUE;
        if (prev == TK_PARAM_LPAREN || prev == TK_PARAM_COMMA)
            return TK_PARAM_SELF_VALUE;
        return TK_SELF_VALUE;
    }
    if (raw_kind == TK_IMPL)
        return semantic_impl_kind_for(parser_i, count);
    if (raw_kind == TK_FOR &&
        scan_context_before(parser_i, count, TK_IMPL, TK_SEMICOLON, TK_LBRACE, TK_RBRACE))
        return TK_IMPL_FOR;
    if (raw_kind == TK_PUB)
    {
        if (enclosing_raw_brace_owner_is(parser_i, count, TK_IMPL))
            return TK_IMPL_PUB;
        if (in_trait_body_context(parser_i, count))
            return TK_TRAIT_PUB;
        return TK_PUB;
    }
    if (raw_kind == TK_STRING && statement_context_kind[parser_i - 1u] == TK_IMPORT)
        return TK_IMPORT_STRING;
    if (raw_kind == TK_LPAREN || raw_kind == TK_LBRACKET)
        return semantic_open_kind_for(parser_i, count, raw_kind);
    if (raw_kind == TK_RPAREN || raw_kind == TK_RBRACKET)
        return semantic_close_kind_for(parser_i, count, raw_kind);
    if (raw_kind == TK_LBRACE)
        return semantic_brace_open_kind_for(parser_i, count);
    if (raw_kind == TK_RBRACE)
        return semantic_brace_close_kind_for(parser_i, count);
    if (raw_kind == TK_COMMA)
        return semantic_comma_kind_for(parser_i, count);
    if (raw_kind == TK_COLON)
        return semantic_colon_kind_for(parser_i, count);
    if (raw_kind == TK_LT)
        return semantic_lt_kind_for(parser_i, count);
    if (raw_kind == TK_GT)
        return semantic_gt_kind_for(parser_i, count);
    if (raw_kind == TK_SEMICOLON)
        return semantic_semicolon_kind_for(parser_i, count);
    if (raw_kind == TK_ASSIGN)
        return semantic_assign_kind_for(parser_i, count);
    if (raw_kind == TK_ARROW)
        return semantic_arrow_kind_for(parser_i, count);
    if (raw_kind == TK_AMPERSAND)
        return semantic_ampersand_kind_for(parser_i, count);
    if (raw_kind == TK_INC || raw_kind == TK_DEC)
        return semantic_inc_dec_kind_for(parser_i, raw_kind, count);
    if (raw_kind == TK_PLUS)
        return semantic_plus_kind_for(parser_i, count);
    if (raw_kind == TK_MINUS)
        return semantic_token_ends_primary(raw_kind_at(parser_i - 1u, count)) ? TK_INFIX_MINUS : TK_PREFIX_MINUS;

    return raw_kind;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint i = tid.x;
    uint lane = ltid.x;
    uint count = min(lexer_token_count[0], gParams.token_capacity);
    uint out_count = count + 2u;
    uint feature_flags = 0u;

    if (i < gParams.token_capacity + 2u && (i == 0u || i == count + 1u))
    {
        semantic_token_kinds[i] = 0u;
    }
    else if (i < out_count)
    {
        uint raw_kind = token_words[i - 1u].kind;
        uint semantic_kind = semantic_kind_for(i, count, raw_kind);
        semantic_token_kinds[i] = semantic_kind;
        feature_flags = parser_feature_flags_for_token(raw_kind, semantic_kind);
    }
    else if (i < gParams.token_capacity + 2u)
    {
        semantic_token_kinds[i] = 0u;
    }

    group_feature_flags[lane] = feature_flags;
    GroupMemoryBarrierWithGroupSync();
    [unroll]
    for (uint step = 128u; step > 0u; step >>= 1u)
    {
        if (lane < step)
            group_feature_flags[lane] |= group_feature_flags[lane + step];
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane == 0u && group_feature_flags[0u] != 0u)
        atomic_u32_or(token_feature_flags, 0u, group_feature_flags[0u]);

    if (i == 0u)
        parser_token_count[0] = count;
}
