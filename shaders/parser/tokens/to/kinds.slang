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
StructuredBuffer<int> paren_match_depth;
StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> paren_match_min_tree;
StructuredBuffer<int> bracket_match_depth;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> bracket_match_min_tree;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> angle_match_min_tree;

RWStructuredBuffer<uint> semantic_token_kinds;
RWStructuredBuffer<uint> parser_token_count;
RWStructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> brace_semantic_kind;
StructuredBuffer<uint> braced_rhs_statement_kind;
StructuredBuffer<uint> bracket_semantic_kind;
StructuredBuffer<uint> statement_context_kind;
StructuredBuffer<uint> token_impl_header_kind;
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> token_where_context_event;
StructuredBuffer<uint> token_match_pattern_context_event;
groupshared uint group_feature_flags[256];

static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const int INF = 2147483647;

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
static const uint TK_DOT_DOT_EQUAL = 189u;
static const uint TK_RANGE_INCLUSIVE_ASSIGN = 190u;
static const uint TK_INHERENT_IMPL = 180u;
static const uint TK_TRAIT_IMPL = 181u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
static const uint TK_PATH_TYPE_ARG_COMMA = 186u;
static const uint TK_EXTERN_ABI_STRING = 188u;
static const uint STATEMENT_CONTEXT_CONST_RHS = 250u;
static const uint STATEMENT_CONTEXT_ASSIGN_RHS = 251u;
static const uint STATEMENT_CONTEXT_FOR_IN = 252u;
static const uint STATEMENT_CONTEXT_LET_RHS = 253u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;
static const uint IMPL_HEADER_CONTEXT = 1u;
static const uint WHERE_CLAUSE_CONTEXT = 1u;
static const uint MATCH_PATTERN_CONTEXT = 1u;
static const uint DEPTH_MODE_BRACE = 0u;
static const uint DEPTH_MODE_PAREN = 1u;
static const uint DEPTH_MODE_BRACKET = 2u;
static const uint DEPTH_MODE_ANGLE = 3u;

uint depth_search_n_blocks()
{
    return gParams.token_capacity == 0u ? 1u : (gParams.token_capacity + WG_SIZE - 1u) / WG_SIZE;
}

uint depth_search_leaf_base()
{
    uint n_blocks = depth_search_n_blocks();
    uint base = max(n_blocks, 1u) - 1u;
    base |= base >> 1u;
    base |= base >> 2u;
    base |= base >> 4u;
    base |= base >> 8u;
    base |= base >> 16u;
    return base + 1u;
}

public struct BraceDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return depth_search_n_blocks();
    }

    public static uint leaf_base()
    {
        return depth_search_leaf_base();
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

public struct ParenDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return depth_search_n_blocks();
    }

    public static uint leaf_base()
    {
        return depth_search_leaf_base();
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

public struct BracketDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return depth_search_n_blocks();
    }

    public static uint leaf_base()
    {
        return depth_search_leaf_base();
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

public struct AngleDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return depth_search_n_blocks();
    }

    public static uint leaf_base()
    {
        return depth_search_leaf_base();
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

public struct ParenDepthRows : IRangeSearchRows<int>
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
        return paren_match_depth[row];
    }
}

public struct BracketDepthRows : IRangeSearchRows<int>
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
        return bracket_match_depth[row];
    }
}

public struct AngleDepthRows : IRangeSearchRows<int>
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
        return angle_match_depth[row];
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

bool depth_search_last_index_before(uint mode, uint hi_index, int query, out uint index)
{
    if (mode == DEPTH_MODE_PAREN)
        return range_search_tree_last_index_before<
            int,
            int,
            ParenDepthTree,
            ParenDepthRows,
            DepthAtMost>(
            hi_index,
            query,
            index);
    if (mode == DEPTH_MODE_BRACKET)
        return range_search_tree_last_index_before<
            int,
            int,
            BracketDepthTree,
            BracketDepthRows,
            DepthAtMost>(
            hi_index,
            query,
            index);
    if (mode == DEPTH_MODE_ANGLE)
        return range_search_tree_last_index_before<
            int,
            int,
            AngleDepthTree,
            AngleDepthRows,
            DepthAtMost>(
            hi_index,
            query,
            index);
    return range_search_tree_last_index_before<
        int,
        int,
        BraceDepthTree,
        BraceDepthRows,
        DepthAtMost>(
        hi_index,
        query,
        index);
}

bool angle_depth_search_first_index_at_or_after(uint lo_index, int query, out uint index)
{
    return range_search_tree_first_index_at_or_after<
        int,
        int,
        AngleDepthTree,
        AngleDepthRows,
        DepthAtMost>(
        lo_index,
        query,
        index);
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

uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

bool semantic_token_before_ends_primary(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint prev_parser_i = parser_i - 1u;
    uint prev_raw = raw_kind_at(prev_parser_i, count);
    if (semantic_token_ends_primary(prev_raw))
        return true;
    if (prev_raw != TK_RBRACE || prev_parser_i == 0u)
        return false;

    uint prev_token_i = prev_parser_i - 1u;
    return prev_token_i < gParams.token_capacity &&
           brace_semantic_kind[prev_token_i] == TK_STRUCT_LIT_RBRACE;
}

uint raw_token_kind(uint token_i)
{
    if (token_i >= min(gParams.token_capacity, lexer_token_count[0]))
        return 0u;
    return token_words[token_i].kind;
}

uint statement_event_token_at(uint token_i)
{
    if (token_i >= gParams.token_capacity)
        return INVALID;
    uint encoded = statement_context_kind[token_i] >> 8u;
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint statement_context_token_kind(uint token_i)
{
    if (token_i >= gParams.token_capacity)
        return 0u;
    uint kind = statement_context_kind[token_i] & 0xffu;
    if (kind == STATEMENT_CONTEXT_CONST_RHS)
        return TK_CONST;
    if (kind == STATEMENT_CONTEXT_LET_RHS)
        return TK_LET;
    return kind == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ? TK_TYPE : kind;
}

uint raw_statement_context_kind(uint token_i)
{
    return token_i < gParams.token_capacity ? (statement_context_kind[token_i] & 0xffu) : 0u;
}

bool value_expression_context_before(uint parser_i)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    uint raw_context = raw_statement_context_kind(token_i);
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

bool in_pattern_context(uint parser_i, uint count);
bool top_level_match_arm_comma(uint parser_i, uint count);
bool in_enum_variant_context(uint parser_i, uint count);
uint semantic_brace_open_kind_for(uint parser_i, uint count);
uint enclosing_semantic_brace_open_before(uint parser_i, uint count);
bool enclosing_semantic_brace_open_before_with_index(
    uint parser_i,
    uint count,
    out uint open_i,
    out uint semantic_kind);
bool enclosing_raw_brace_owner_is(uint parser_i, uint count, uint owner);
uint matching_semantic_brace_open_before(uint parser_i, uint count);
int global_paren_depth_before(uint parser_i, uint count);
int global_bracket_depth_before(uint parser_i, uint count);
int global_angle_depth_before(uint parser_i, uint count);
bool bound_colon_context(uint parser_i, uint count);
bool bound_plus_context(uint parser_i, uint count);
bool bound_type_context_before(uint parser_i, uint count);
bool impl_type_context_before(uint parser_i, uint count);
bool where_clause_context_before(uint parser_i, uint count);
bool path_type_arg_open_has_value_path_tail(uint open_parser_i, uint count);
uint semantic_colon_kind_for(uint parser_i, uint count);
bool matching_raw_paren_open_before(uint parser_i, uint count, out uint open_i);
bool matching_raw_bracket_open_before(uint parser_i, uint count, out uint open_i);
uint matching_semantic_paren_open_before(uint parser_i, uint count);
bool matching_raw_angle_open_for_close(uint close_parser_i, uint count, out uint open_i);

bool fn_param_lparen_context(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    if (prev2 == TK_FN && prev == TK_IDENT)
        return true;

    if (prev != TK_GT)
        return false;

    uint open_i = 0u;
    if (!matching_raw_angle_open_for_close(parser_i - 1u, count, open_i))
        return false;
    uint open_parser_i = open_i + 1u;
    return raw_kind_at(open_parser_i - 1u, count) == TK_IDENT &&
           raw_kind_at(open_parser_i - 2u, count) == TK_FN;
}

uint semantic_open_kind_for(uint parser_i, uint count, uint raw_kind)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    bool prev_ends_primary = semantic_token_before_ends_primary(parser_i, count);

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

bool in_enum_variant_context(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count) == TK_ENUM_LBRACE;
}

bool in_pattern_context(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;

    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_match_pattern_context_event[token_i] & 0xffu) == MATCH_PATTERN_CONTEXT;
}

bool top_level_match_arm_comma(uint parser_i, uint count)
{
    if (raw_kind_at(parser_i, count) != TK_COMMA)
        return false;

    uint open_i = 0u;
    uint open_kind = 0u;
    if (!enclosing_semantic_brace_open_before_with_index(parser_i, count, open_i, open_kind) ||
        open_kind != TK_MATCH_LBRACE)
        return false;

    uint open_parser_i = open_i + 1u;
    return global_paren_depth_before(parser_i, count) ==
               global_paren_depth_before(open_parser_i, count) &&
           global_bracket_depth_before(parser_i, count) ==
               global_bracket_depth_before(open_parser_i, count) &&
           global_angle_depth_before(parser_i, count) ==
               global_angle_depth_before(open_parser_i, count);
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

uint semantic_close_kind_for(uint parser_i, uint count, uint raw_kind)
{
    if (raw_kind == TK_RPAREN)
    {
        uint open_kind = matching_semantic_paren_open_before(parser_i, count);
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

int global_paren_depth_before(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0;
    uint token_i = parser_i - 1u;
    if (token_i >= gParams.token_capacity)
        return 0;
    uint block_i = token_i / WG_SIZE;
    return block_prefix_paren[block_i] + depth_paren_inblock[token_i];
}

int global_bracket_depth_before(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0;
    uint token_i = parser_i - 1u;
    if (token_i >= gParams.token_capacity)
        return 0;
    uint block_i = token_i / WG_SIZE;
    return block_prefix_bracket[block_i] + depth_bracket_inblock[token_i];
}

int global_angle_depth_before(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0;
    uint token_i = parser_i - 1u;
    if (token_i >= gParams.token_capacity)
        return 0;
    uint block_i = token_i / WG_SIZE;
    return block_prefix_angle[block_i] + depth_angle_inblock[token_i];
}

bool matching_raw_paren_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = 0u;
    if (parser_i == 0u)
        return false;

    uint token_i = parser_i - 1u;
    if (token_i >= count || token_i >= gParams.token_capacity)
        return false;

    int depth_before = global_paren_depth_before(parser_i, count);
    if (depth_before <= 0)
        return false;

    if (!depth_search_last_index_before(
            DEPTH_MODE_PAREN,
            token_i,
            depth_before - 1,
            open_i))
        return false;

    return open_i < count &&
           token_words[open_i].kind == TK_LPAREN &&
           paren_match_depth[open_i] == depth_before - 1;
}

bool matching_raw_bracket_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = 0u;
    if (parser_i == 0u)
        return false;

    uint token_i = parser_i - 1u;
    if (token_i >= count || token_i >= gParams.token_capacity)
        return false;

    int depth_before = global_bracket_depth_before(parser_i, count);
    if (depth_before <= 0)
        return false;

    if (!depth_search_last_index_before(
            DEPTH_MODE_BRACKET,
            token_i,
            depth_before - 1,
            open_i))
        return false;

    return open_i < count &&
           token_words[open_i].kind == TK_LBRACKET &&
           bracket_match_depth[open_i] == depth_before - 1;
}

uint matching_semantic_paren_open_before(uint parser_i, uint count)
{
    uint open_i = 0u;
    if (!matching_raw_paren_open_before(parser_i, count, open_i))
        return 0u;

    return semantic_open_kind_for(open_i + 1u, count, TK_LPAREN);
}

uint enclosing_semantic_brace_open_before(uint parser_i, uint count)
{
    uint open_i = 0u;
    uint semantic_kind = 0u;
    return enclosing_semantic_brace_open_before_with_index(
        parser_i,
        count,
        open_i,
        semantic_kind)
        ? semantic_kind
        : 0u;
}

bool enclosing_semantic_brace_open_before_with_index(
    uint parser_i,
    uint count,
    out uint open_i,
    out uint semantic_kind)
{
    if (parser_i == 0u)
    {
        open_i = 0u;
        semantic_kind = 0u;
        return false;
    }
    uint token_i = parser_i - 1u;
    if (token_i >= count || token_i >= gParams.token_capacity)
    {
        open_i = 0u;
        semantic_kind = 0u;
        return false;
    }

    int depth_before = global_brace_depth_before(parser_i, count);
    if (depth_before <= 0)
    {
        open_i = 0u;
        semantic_kind = 0u;
        return false;
    }

    if (!depth_search_last_index_before(
            DEPTH_MODE_BRACE,
            token_i,
            depth_before - 1,
            open_i))
    {
        open_i = 0u;
        semantic_kind = 0u;
        return false;
    }

    if (open_i >= count || token_words[open_i].kind != TK_LBRACE)
    {
        open_i = 0u;
        semantic_kind = 0u;
        return false;
    }

    semantic_kind = brace_semantic_kind[open_i];
    if (semantic_kind == 0u)
        semantic_kind = semantic_brace_open_kind_for(open_i + 1u, count);
    return semantic_kind != 0u;
}

bool bound_type_context_before(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    if (prev == TK_COLON)
        return bound_colon_context(parser_i - 1u, count);
    if (prev == TK_PLUS)
        return bound_plus_context(parser_i - 1u, count);
    if (where_clause_context_before(parser_i, count) &&
        (prev == TK_LT || prev == TK_COMMA || prev == TK_AMPERSAND))
    {
        return true;
    }
    if (prev != TK_IDENT)
        return false;
    if (where_clause_context_before(parser_i, count))
        return true;

    uint prefix_i = parser_i - 2u;
    uint kind = raw_kind_at(prefix_i, count);
    if (kind == TK_COLON)
    {
        if (raw_kind_at(prefix_i - 1u, count) == TK_COLON ||
            raw_kind_at(prefix_i + 1u, count) == TK_COLON)
        {
            return false;
        }
        return bound_colon_context(prefix_i, count);
    }
    if (kind == TK_PLUS)
        return bound_plus_context(prefix_i, count);
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
    if (prev_raw == TK_IDENT &&
        value_expression_context_before(parser_i) &&
        (prev2_raw == TK_COLON || prev2_raw == TK_PATH_COLON))
    {
        return TK_PATH_TYPE_ARG_LT;
    }
    if (prev_raw == TK_IDENT &&
        value_expression_context_before(parser_i) &&
        path_type_arg_open_has_value_path_tail(parser_i, count))
    {
        return TK_PATH_TYPE_ARG_LT;
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
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_impl_context_event[token_i] & 0xffu) == IMPL_HEADER_CONTEXT;
}

bool where_clause_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_where_context_event[token_i] & 0xffu) == WHERE_CLAUSE_CONTEXT;
}

bool path_type_arg_open_has_value_path_tail(uint open_parser_i, uint count)
{
    if (open_parser_i == 0u)
        return false;

    uint open_i = open_parser_i - 1u;
    if (open_i >= count || open_i >= gParams.token_capacity ||
        raw_token_kind(open_i) != TK_LT)
        return false;

    int open_depth = angle_match_depth[open_i];
    uint close_i = 0u;
    if (open_depth == INF ||
        !angle_depth_search_first_index_at_or_after(open_i + 1u, open_depth, close_i) ||
        close_i >= count || raw_token_kind(close_i) != TK_GT ||
        angle_match_depth[close_i] != open_depth)
        return false;

    uint next = raw_kind_at(close_i + 2u, count);
    uint next2 = raw_kind_at(close_i + 3u, count);
    return next == TK_LPAREN || (next == TK_COLON && next2 == TK_COLON);
}

bool matching_raw_angle_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = 0u;
    if (parser_i == 0u)
        return false;

    uint token_i = parser_i - 1u;
    if (token_i >= count || token_i >= gParams.token_capacity)
        return false;

    int depth_before = global_angle_depth_before(parser_i, count);
    if (!depth_search_last_index_before(
            DEPTH_MODE_ANGLE,
            token_i,
            depth_before - 1,
            open_i))
        return false;

    if (open_i < count &&
        token_words[open_i].kind == TK_LT &&
        angle_match_depth[open_i] == depth_before - 1)
        return true;
    return false;
}

bool raw_angle_open_can_contain_bound_colon(uint open_parser_i, uint count)
{
    uint prev_raw = raw_kind_at(open_parser_i - 1u, count);
    uint prev2_raw = raw_kind_at(open_parser_i - 2u, count);
    if (prev_raw == TK_IMPL || prev2_raw == TK_FN || prev2_raw == TK_STRUCT ||
        prev2_raw == TK_ENUM || prev2_raw == TK_TRAIT || prev2_raw == TK_TYPE)
    {
        return true;
    }

    return prev_raw == TK_IDENT &&
           (prev2_raw == TK_COLON || prev2_raw == TK_ARROW || prev2_raw == TK_AMPERSAND ||
            prev2_raw == TK_LT || prev2_raw == TK_COMMA || prev2_raw == TK_LBRACKET ||
            impl_type_context_before(open_parser_i, count) ||
            where_clause_context_before(open_parser_i, count));
}

uint matching_semantic_angle_open_before(uint parser_i, uint count)
{
    uint open_i = 0u;
    if (!matching_raw_angle_open_before(parser_i, count, open_i))
        return 0u;

    return semantic_lt_kind_for(open_i + 1u, count);
}

bool matching_raw_angle_open_for_close(uint close_parser_i, uint count, out uint open_i)
{
    open_i = 0u;
    if (close_parser_i == 0u || raw_kind_at(close_parser_i, count) != TK_GT)
        return false;

    uint close_i = close_parser_i - 1u;
    if (close_i >= count || close_i >= gParams.token_capacity)
        return false;

    int depth_before = global_angle_depth_before(close_parser_i, count);
    if (!depth_search_last_index_before(
            DEPTH_MODE_ANGLE,
            close_i,
            depth_before - 1,
            open_i))
        return false;

    if (open_i < count &&
        token_words[open_i].kind == TK_LT &&
        angle_match_depth[open_i] == depth_before - 1)
        return true;
    return false;
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
    if (open_kind == TK_PATH_TYPE_ARG_LT)
        return TK_PATH_TYPE_ARG_GT;
    return TK_GT;
}

uint semantic_comma_kind_for(uint parser_i, uint count)
{
    uint best_open_i = 0u;
    uint best_kind = 0u;
    uint open_i = 0u;

    if (matching_raw_angle_open_before(parser_i, count, open_i))
    {
        uint angle_open = semantic_lt_kind_for(open_i + 1u, count);
        uint angle_comma = 0u;
        if (angle_open == TK_TYPE_ARG_LT)
            angle_comma = TK_TYPE_ARG_COMMA;
        else if (angle_open == TK_GENERIC_PARAM_LT)
            angle_comma = TK_GENERIC_PARAM_COMMA;
        else if (angle_open == TK_BOUND_TYPE_ARG_LT)
            angle_comma = TK_BOUND_TYPE_ARG_COMMA;
        else if (angle_open == TK_PATH_TYPE_ARG_LT)
            angle_comma = TK_PATH_TYPE_ARG_COMMA;

        if (angle_comma != 0u)
        {
            best_open_i = open_i;
            best_kind = angle_comma;
        }
    }

    if (matching_raw_paren_open_before(parser_i, count, open_i))
    {
        uint paren_open = semantic_open_kind_for(open_i + 1u, count, TK_LPAREN);
        uint paren_comma = 0u;
        if (paren_open == TK_PARAM_LPAREN)
            paren_comma = TK_PARAM_COMMA;
        else if (paren_open == TK_CALL_LPAREN)
            paren_comma = TK_ARG_COMMA;
        else if (paren_open == TK_PATTERN_LPAREN)
            paren_comma = TK_PATTERN_COMMA;
        else if (paren_open == TK_ENUM_PAYLOAD_LPAREN)
            paren_comma = TK_ENUM_FIELD_COMMA;

        if (paren_comma != 0u && (best_kind == 0u || open_i > best_open_i))
        {
            best_open_i = open_i;
            best_kind = paren_comma;
        }
    }

    if (matching_raw_bracket_open_before(parser_i, count, open_i))
    {
        uint bracket_open = bracket_semantic_kind[open_i];
        uint bracket_comma = bracket_open == TK_ARRAY_LBRACKET ? TK_ARRAY_COMMA : 0u;
        if (bracket_comma != 0u && (best_kind == 0u || open_i > best_open_i))
        {
            best_open_i = open_i;
            best_kind = bracket_comma;
        }
    }

    uint brace_open_i = 0u;
    uint brace_open = 0u;
    if (enclosing_semantic_brace_open_before_with_index(
            parser_i,
            count,
            brace_open_i,
            brace_open))
    {
        uint brace_comma = 0u;
        if (brace_open == TK_MATCH_LBRACE)
            brace_comma = TK_MATCH_ARM_COMMA;
        else if (brace_open == TK_ENUM_LBRACE)
            brace_comma = TK_ENUM_VARIANT_COMMA;
        else if (brace_open == TK_STRUCT_DECL_LBRACE)
            brace_comma = TK_STRUCT_FIELD_COMMA;
        else if (brace_open == TK_STRUCT_LIT_LBRACE)
            brace_comma = TK_STRUCT_LIT_COMMA;

        if (brace_comma != 0u && (best_kind == 0u || brace_open_i > best_open_i))
        {
            best_open_i = brace_open_i;
            best_kind = brace_comma;
        }
    }

    if (best_kind != 0u)
        return best_kind;
    if (where_clause_context_before(parser_i, count))
        return TK_WHERE_COMMA;
    return TK_COMMA;
}

bool bound_colon_context(uint parser_i, uint count)
{
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    if (prev2 == TK_CONST)
        return false;

    if (where_clause_context_before(parser_i, count))
        return true;

    uint open_i = 0u;
    if (!matching_raw_angle_open_before(parser_i, count, open_i))
        return false;

    return raw_angle_open_can_contain_bound_colon(open_i + 1u, count);
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
    if (raw_kind_at(parser_i - 1u, count) == TK_DOT_DOT_EQUAL)
        return TK_RANGE_INCLUSIVE_ASSIGN;

    uint statement_context = parser_i == 0u ? 0u : statement_context_token_kind(parser_i - 1u);
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

bool raw_kind_can_end_bound_plus_lhs(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_GT ||
           kind == TK_SELF_VALUE;
}

bool bound_plus_context(uint parser_i, uint count)
{
    if (!raw_kind_can_end_bound_plus_lhs(raw_kind_at(parser_i - 1u, count)))
        return false;

    if (where_clause_context_before(parser_i, count))
        return true;

    uint open_i = 0u;
    if (!matching_raw_angle_open_before(parser_i, count, open_i))
        return false;

    return raw_angle_open_can_contain_bound_colon(open_i + 1u, count);
}

uint semantic_plus_kind_for(uint parser_i, uint count)
{
    if (bound_plus_context(parser_i, count))
        return TK_BOUND_PLUS;
    return semantic_token_before_ends_primary(parser_i, count)
        ? TK_INFIX_PLUS
        : TK_PREFIX_PLUS;
}

uint semantic_ampersand_kind_for(uint parser_i, uint count)
{
    if (bound_type_context_before(parser_i, count))
        return TK_BOUND_TYPE_AMPERSAND;
    return semantic_token_before_ends_primary(parser_i, count)
        ? TK_AMPERSAND
        : TK_TYPE_AMPERSAND;
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

bool extern_fn_signature_context_before(uint token_i)
{
    if (statement_context_token_kind(token_i) != TK_FN)
        return false;

    uint fn_i = statement_event_token_at(token_i);
    if (fn_i == INVALID)
        return false;

    if (fn_i > 0u && raw_token_kind(fn_i - 1u) == TK_EXTERN)
        return true;

    return fn_i > 1u &&
           raw_token_kind(fn_i - 1u) == TK_STRING &&
           raw_token_kind(fn_i - 2u) == TK_EXTERN;
}

bool extern_abi_string_context_before(uint token_i)
{
    return statement_context_token_kind(token_i) == TK_EXTERN;
}

uint semantic_semicolon_kind_for(uint parser_i, uint count)
{
    uint token_i = parser_i - 1u;
    if (bracket_semantic_kind[token_i] == TK_TYPE_SEMICOLON)
        return TK_TYPE_SEMICOLON;
    if (in_trait_body_context(parser_i, count))
        return TK_TRAIT_METHOD_SEMICOLON;
    if (extern_fn_signature_context_before(token_i))
        return TK_EXTERN_SEMICOLON;

    uint recorded = semicolon_kind_for_statement_context(statement_context_token_kind(token_i));
    if (recorded != 0u)
        return recorded;
    if (token_i > 0u && raw_token_kind(token_i - 1u) == TK_RBRACE)
    {
        uint braced = semicolon_kind_for_statement_context(
            braced_rhs_statement_kind[token_i - 1u]);
        if (braced != 0u)
            return braced;
    }
    return TK_EXPR_SEMICOLON;
}

uint semantic_impl_kind_for(uint parser_i, uint count)
{
    uint token_i = parser_i - 1u;
    if (token_i < count &&
        token_i < gParams.token_capacity &&
        token_impl_header_kind[token_i] == TK_TRAIT_IMPL)
        return TK_TRAIT_IMPL;
    return TK_INHERENT_IMPL;
}

uint semantic_kind_for(uint parser_i, uint count, uint raw_kind)
{
    if (raw_kind == TK_IDENT)
        return TK_IDENT;

    if (raw_kind == TK_SELF_VALUE)
        return TK_SELF_VALUE;
    if (raw_kind == TK_IMPL)
        return semantic_impl_kind_for(parser_i, count);
    if (raw_kind == TK_FOR && impl_type_context_before(parser_i, count))
        return TK_IMPL_FOR;
    if (raw_kind == TK_PUB)
    {
        if (enclosing_raw_brace_owner_is(parser_i, count, TK_IMPL))
            return TK_IMPL_PUB;
        if (in_trait_body_context(parser_i, count))
            return TK_TRAIT_PUB;
        return TK_PUB;
    }
    if (raw_kind == TK_STRING && statement_context_token_kind(parser_i - 1u) == TK_IMPORT)
        return TK_IMPORT_STRING;
    if (raw_kind == TK_STRING && extern_abi_string_context_before(parser_i - 1u))
        return TK_EXTERN_ABI_STRING;
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
    if (raw_kind == TK_PLUS)
        return semantic_plus_kind_for(parser_i, count);
    if (raw_kind == TK_MINUS)
        return semantic_token_before_ends_primary(parser_i, count) ? TK_INFIX_MINUS : TK_PREFIX_MINUS;

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
    for (uint width = WG_SIZE / 2u; width > 0u; width >>= 1u)
    {
        if (lane < width)
            group_feature_flags[lane] |= group_feature_flags[lane + width];
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane == 0u && group_feature_flags[0u] != 0u)
        atomic_u32_or(token_feature_flags, 0u, group_feature_flags[0u]);

    if (i == 0u)
        parser_token_count[0] = count;
}
