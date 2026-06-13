import segment_tree;
import status;

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
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> token_file_id;

// [0] ok, [1] first error token, [2] error code, [3] detail
RWStructuredBuffer<uint> status;
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> depth_angle_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> block_prefix_angle;
StructuredBuffer<int> paren_match_depth;
StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> paren_match_min_tree;
StructuredBuffer<int> angle_match_depth;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> angle_match_min_tree;
StructuredBuffer<uint> statement_context_kind;
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> trait_context_event;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint ERR_UNEXPECTED_TOKEN = 1u;
static const uint ERR_EXPECTED_TOKEN = 2u;
static const uint ERR_MISSING_SEMICOLON = 3u;
static const uint ERR_STMT_OVERLAP = 4u;
static const uint ERR_UNBALANCED_DELIMITER = 5u;

static const uint IMPL_HEADER_CONTEXT = 1u;
static const uint TRAIT_BODY_CONTEXT = 1u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_PLUS = 6u;
static const uint TK_STAR = 7u;
static const uint TK_ASSIGN = 8u;
static const uint TK_SLASH = 9u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_NOT = 19u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_PIPE = 26u;
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
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PERCENT = 41u;
static const uint TK_CARET = 42u;
static const uint TK_SHL = 43u;
static const uint TK_SHR = 44u;
static const uint TK_TILDE = 45u;
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
static const uint TK_PUB = 66u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
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
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
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
static const uint TK_IN = 101u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_WHERE = 104u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
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
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_BOUND_TYPE_ARG_COMMA = 177u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
static const uint TK_PATH_TYPE_ARG_COMMA = 186u;
static const uint TK_PATH_GENERIC_IDENT = 187u;
static const uint TK_EXTERN_ABI_STRING = 188u;
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

static const uint STATEMENT_CONTEXT_CONST_RHS = 250u;
static const uint STATEMENT_CONTEXT_ASSIGN_RHS = 251u;
static const uint STATEMENT_CONTEXT_FOR_IN = 252u;
static const uint STATEMENT_CONTEXT_LET_RHS = 253u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint token_kind(uint i)
{
    uint n_active = active_token_count();
    return i < n_active ? token_words[i].kind : 0u;
}

uint token_file(uint i)
{
    uint n_active = active_token_count();
    return i < n_active ? token_file_id[i] : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_stmt_keyword(uint kind)
{
    return kind == TK_LET || kind == TK_RETURN || kind == TK_IF || kind == TK_ELSE ||
           kind == TK_WHILE || kind == TK_FOR ||
           kind == TK_BREAK || kind == TK_CONTINUE || kind == TK_FN || kind == TK_CONST ||
           kind == TK_TYPE ||
           kind == TK_ENUM || kind == TK_STRUCT || kind == TK_IMPORT || kind == TK_MODULE ||
           kind == TK_IMPL || kind == TK_TRAIT || kind == TK_EXTERN;
}

bool is_stmt_boundary(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_TYPE_SEMICOLON ||
           kind == TK_TRAIT_METHOD_SEMICOLON || kind == TK_MODULE_SEMICOLON ||
           kind == TK_EXTERN_SEMICOLON || kind == TK_TYPE_ALIAS_SEMICOLON ||
           kind == TK_CONST_SEMICOLON || kind == TK_LET_SEMICOLON ||
           kind == TK_RETURN_SEMICOLON || kind == TK_EXPR_SEMICOLON ||
           kind == TK_BREAK_SEMICOLON || kind == TK_CONTINUE_SEMICOLON ||
           kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_ELSE ||
           is_stmt_keyword(kind);
}

bool is_type_start(uint kind)
{
    return kind == TK_TYPE_IDENT || kind == TK_IDENT || kind == TK_TYPE_ARRAY_LBRACKET ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET || kind == TK_AMPERSAND;
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

bool is_binary_operator(uint kind)
{
    return kind == TK_INFIX_PLUS || kind == TK_INFIX_MINUS || kind == TK_STAR ||
           kind == TK_SLASH || kind == TK_PERCENT || kind == TK_LT || kind == TK_GT ||
           kind == TK_LE || kind == TK_GE || kind == TK_EQEQ || kind == TK_NOT_EQUAL ||
           kind == TK_ANDAND || kind == TK_OROR || kind == TK_AMPERSAND || kind == TK_PIPE ||
           kind == TK_CARET || kind == TK_SHL || kind == TK_SHR;
}

bool is_semicolon_kind(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_TYPE_SEMICOLON ||
           kind == TK_TRAIT_METHOD_SEMICOLON || kind == TK_IMPORT_SEMICOLON ||
           kind == TK_MODULE_SEMICOLON || kind == TK_EXTERN_SEMICOLON ||
           kind == TK_TYPE_ALIAS_SEMICOLON || kind == TK_CONST_SEMICOLON ||
           kind == TK_LET_SEMICOLON || kind == TK_RETURN_SEMICOLON ||
           kind == TK_EXPR_SEMICOLON || kind == TK_BREAK_SEMICOLON ||
           kind == TK_CONTINUE_SEMICOLON;
}

bool is_statement_semicolon_kind(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_TRAIT_METHOD_SEMICOLON ||
           kind == TK_IMPORT_SEMICOLON || kind == TK_MODULE_SEMICOLON ||
           kind == TK_EXTERN_SEMICOLON || kind == TK_TYPE_ALIAS_SEMICOLON ||
           kind == TK_CONST_SEMICOLON || kind == TK_LET_SEMICOLON ||
           kind == TK_RETURN_SEMICOLON || kind == TK_EXPR_SEMICOLON ||
           kind == TK_BREAK_SEMICOLON || kind == TK_CONTINUE_SEMICOLON;
}

bool is_lbrace_kind(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_FN_BLOCK_LBRACE ||
           kind == TK_IMPL_FN_BLOCK_LBRACE || kind == TK_MATCH_LBRACE ||
           kind == TK_IMPL_LBRACE || kind == TK_TRAIT_LBRACE ||
           kind == TK_STRUCT_LIT_LBRACE || kind == TK_STRUCT_DECL_LBRACE ||
           kind == TK_ENUM_LBRACE;
}

bool is_rbrace_kind(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_FN_BLOCK_RBRACE ||
           kind == TK_IMPL_FN_BLOCK_RBRACE || kind == TK_MATCH_RBRACE ||
           kind == TK_IMPL_RBRACE || kind == TK_TRAIT_RBRACE ||
           kind == TK_STRUCT_LIT_RBRACE || kind == TK_STRUCT_DECL_RBRACE ||
           kind == TK_ENUM_RBRACE;
}

bool is_generic_lt_kind(uint kind)
{
    return kind == TK_LT || kind == TK_TYPE_ARG_LT || kind == TK_GENERIC_PARAM_LT ||
           kind == TK_BOUND_TYPE_ARG_LT || kind == TK_PATH_TYPE_ARG_LT;
}

bool is_generic_gt_kind(uint kind)
{
    return kind == TK_GT || kind == TK_TYPE_ARG_GT || kind == TK_GENERIC_PARAM_GT ||
           kind == TK_BOUND_TYPE_ARG_GT || kind == TK_PATH_TYPE_ARG_GT;
}

bool is_generic_comma_kind(uint kind)
{
    return kind == TK_COMMA || kind == TK_ARG_COMMA || kind == TK_PARAM_COMMA ||
           kind == TK_TYPE_ARG_COMMA || kind == TK_GENERIC_PARAM_COMMA ||
           kind == TK_BOUND_TYPE_ARG_COMMA || kind == TK_PATH_TYPE_ARG_COMMA;
}

bool is_self_receiver_ref_amp(uint i)
{
    if (token_kind(i) != TK_AMPERSAND || token_kind(i + 1u) != TK_SELF_VALUE || i == 0u)
        return false;
    uint prev = token_kind(i - 1u);
    return prev == TK_PARAM_LPAREN || prev == TK_LPAREN || prev == TK_PARAM_COMMA ||
           prev == TK_COMMA;
}

bool is_expr_start(uint kind)
{
    return kind == TK_IDENT || kind == TK_PATH_GENERIC_IDENT ||
           kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE || kind == TK_SELF_VALUE ||
           kind == TK_CHAR || kind == TK_GROUP_LPAREN || kind == TK_LPAREN ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET || kind == TK_PREFIX_PLUS ||
           kind == TK_PREFIX_MINUS || kind == TK_NOT || kind == TK_MATCH;
}

bool is_expr_end(uint kind)
{
    return kind == TK_IDENT || kind == TK_PATH_GENERIC_IDENT ||
           kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE || kind == TK_SELF_VALUE ||
           kind == TK_CHAR || kind == TK_GROUP_RPAREN || kind == TK_RPAREN ||
           kind == TK_CALL_RPAREN || kind == TK_INDEX_RBRACKET || kind == TK_ARRAY_RBRACKET ||
           kind == TK_RBRACKET;
}

int paren_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_paren[block_idx] + depth_paren_inblock[i];
}

int bracket_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_bracket[block_idx] + depth_bracket_inblock[i];
}

int brace_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_brace[block_idx] + depth_brace_inblock[i];
}

int angle_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_angle[block_idx] + depth_angle_inblock[i];
}

bool same_delimiter_depth_before(uint a, uint b)
{
    return paren_depth_before(a) == paren_depth_before(b) &&
           bracket_depth_before(a) == bracket_depth_before(b) &&
           brace_depth_before(a) == brace_depth_before(b);
}

bool is_impl_trait_for(uint i)
{
    return token_kind(i) == TK_FOR &&
           is_type_start(token_kind(i + 1u)) &&
           i < gParams.n_tokens &&
           (token_impl_context_event[i] & 0xffu) == IMPL_HEADER_CONTEXT;
}

bool is_generic_name_kind(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_TYPE_IDENT ||
           kind == TK_PARAM_IDENT ||
           kind == TK_PATH_GENERIC_IDENT;
}

bool can_start_generic_angle_list(uint lt_i)
{
    if (!is_generic_lt_kind(token_kind(lt_i)) || lt_i == 0u)
        return false;

    uint prev = token_kind(lt_i - 1u);
    if (!is_generic_name_kind(prev))
        return false;

    uint before = lt_i > 1u ? token_kind(lt_i - 2u) : 0u;
    return before == TK_FN || before == TK_ENUM || before == TK_STRUCT || before == TK_TYPE ||
           before == TK_IMPL || before == TK_TRAIT || before == TK_COLON || before == TK_ARROW ||
           is_generic_comma_kind(before) || is_generic_lt_kind(before) ||
           before == TK_PLUS || before == TK_PREFIX_PLUS || before == TK_INFIX_PLUS ||
           before == TK_LPAREN || before == TK_GROUP_LPAREN || before == TK_CALL_LPAREN ||
           before == TK_PARAM_LPAREN || before == TK_TYPE_ARRAY_LBRACKET ||
           before == TK_ARRAY_LBRACKET || before == TK_AMPERSAND || before == TK_WHERE;
}

bool is_generic_angle_boundary(uint kind)
{
    return is_semicolon_kind(kind) || is_lbrace_kind(kind) ||
           kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_FN ||
           kind == TK_LET || kind == TK_RETURN || kind == TK_IF || kind == TK_ELSE ||
           kind == TK_WHILE || kind == TK_FOR ||
           kind == TK_BREAK || kind == TK_CONTINUE || kind == TK_ENUM ||
           kind == TK_STRUCT || kind == TK_TYPE || kind == TK_IMPORT || kind == TK_MODULE ||
           kind == TK_IMPL || kind == TK_TRAIT || kind == TK_EXTERN || kind == TK_WHERE;
}

uint generic_angle_list_end(uint open_i)
{
    uint close_i = matching_close_angle_after(open_i);
    return close_i == INVALID ? INVALID : close_i + 1u;
}

bool token_in_generic_angle_list(uint token_i)
{
    if (is_generic_lt_kind(token_kind(token_i)) && can_start_generic_angle_list(token_i))
    {
        uint close = generic_angle_list_end(token_i);
        return close != INVALID && token_i < close;
    }

    uint open_i = matching_open_angle_before(token_i);
    if (open_i == INVALID)
        return false;
    uint close = generic_angle_list_end(open_i);
    return close != INVALID && token_i < close;
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

uint assignment_event_before_semicolon(uint semi, uint rhs_context)
{
    if (semi >= gParams.n_tokens)
        return INVALID;
    uint event = statement_context_kind[semi];
    if ((event & 0xffu) != rhs_context)
        return INVALID;
    uint encoded_token = event >> 8u;
    return encoded_token == 0u ? INVALID : encoded_token - 1u;
}

uint statement_event_token(uint event)
{
    uint encoded_token = event >> 8u;
    return encoded_token == 0u ? INVALID : encoded_token - 1u;
}

uint owner_statement_before_rhs_event(uint rhs_i, uint owner_kind)
{
    if (rhs_i >= gParams.n_tokens)
        return INVALID;
    uint owner_event = statement_context_kind[rhs_i];
    if (statement_context_token_kind(owner_event) != owner_kind)
        return INVALID;
    return statement_event_token(owner_event);
}

uint statement_context_owner_token(uint event)
{
    uint context = event & 0xffu;
    uint event_i = statement_event_token(event);
    if (event_i == INVALID)
        return INVALID;
    if (context == STATEMENT_CONTEXT_LET_RHS)
        return owner_statement_before_rhs_event(event_i, TK_LET);
    if (context == STATEMENT_CONTEXT_CONST_RHS)
        return owner_statement_before_rhs_event(event_i, TK_CONST);
    if (context == STATEMENT_CONTEXT_TYPE_ALIAS_RHS)
        return owner_statement_before_rhs_event(event_i, TK_TYPE);
    if (context == STATEMENT_CONTEXT_FOR_IN)
        return owner_statement_before_rhs_event(event_i, TK_FOR);
    return event_i;
}

bool latest_statement_keyword_overlaps(uint semi, uint statement_i)
{
    if (semi >= gParams.n_tokens)
        return false;
    uint event = statement_context_kind[semi];
    uint event_i = statement_event_token(event);
    if (event_i == INVALID || event_i <= statement_i)
        return false;
    return same_delimiter_depth_before(statement_i, event_i) && is_stmt_keyword(event & 0xffu);
}

uint for_in_event_before_or_at(uint token_i, uint for_i)
{
    if (token_i >= min(active_token_count(), gParams.n_tokens))
        return INVALID;

    uint event = statement_context_kind[token_i];
    if ((event & 0xffu) == STATEMENT_CONTEXT_FOR_IN)
    {
        uint event_i = statement_event_token(event);
        return event_i != INVALID &&
               event_i > for_i + 1u &&
               same_delimiter_depth_before(for_i, event_i)
            ? event_i
            : INVALID;
    }

    return token_kind(token_i) == TK_IN &&
           (statement_context_kind[token_i] & 0xffu) == TK_FOR &&
           token_i > for_i + 1u &&
           same_delimiter_depth_before(for_i, token_i)
        ? token_i
        : INVALID;
}

bool fn_allows_semicolon(uint fn_i)
{
    return (fn_i > 0u && token_kind(fn_i - 1u) == TK_EXTERN) ||
           (fn_i > 1u &&
            (token_kind(fn_i - 1u) == TK_STRING ||
             token_kind(fn_i - 1u) == TK_EXTERN_ABI_STRING) &&
            token_kind(fn_i - 2u) == TK_EXTERN) ||
           (fn_i < active_token_count() &&
            fn_i < gParams.n_tokens &&
            brace_depth_before(fn_i) == 1 &&
            (trait_context_event[fn_i] & 0xffu) == TRAIT_BODY_CONTEXT);
}

bool context_requires_semicolon(uint context)
{
    return context == STATEMENT_CONTEXT_ASSIGN_RHS ||
           context == STATEMENT_CONTEXT_CONST_RHS ||
           context == STATEMENT_CONTEXT_LET_RHS ||
           context == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ||
           context == TK_LET || context == TK_RETURN || context == TK_BREAK ||
           context == TK_CONTINUE || context == TK_CONST || context == TK_TYPE ||
           context == TK_IMPORT || context == TK_MODULE;
}

bool context_requires_body(uint context)
{
    return context == TK_FN || context == TK_ENUM || context == TK_STRUCT ||
           context == TK_FOR || context == STATEMENT_CONTEXT_FOR_IN;
}

uint diagnostic_token_for_context(uint event)
{
    uint owner = statement_context_owner_token(event);
    return owner == INVALID ? statement_event_token(event) : owner;
}

void record_pending_missing_semicolon(uint event)
{
    uint token_i = diagnostic_token_for_context(event);
    if (token_i != INVALID)
        record_error(token_i, ERR_MISSING_SEMICOLON, 0u);
}

void record_pending_expected_lbrace(uint event)
{
    uint token_i = diagnostic_token_for_context(event);
    if (token_i != INVALID)
        record_error(token_i, ERR_EXPECTED_TOKEN, TK_LBRACE);
}

void validate_type_alias_boundary(uint event, uint boundary_i, bool has_semicolon)
{
    uint context = event & 0xffu;
    uint type_i = diagnostic_token_for_context(event);
    if (type_i == INVALID)
        return;
    if (!has_semicolon)
    {
        record_error(type_i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if (context == TK_TYPE)
    {
        record_error(type_i, ERR_EXPECTED_TOKEN, TK_ASSIGN);
        return;
    }
    uint assign_i = statement_event_token(event);
    if (assign_i == INVALID || assign_i + 1u >= boundary_i ||
        !is_type_start(token_kind(assign_i + 1u)))
        record_error(assign_i == INVALID ? type_i : assign_i + 1u, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
}

void validate_let_boundary(uint event, uint boundary_i, bool has_semicolon)
{
    uint let_i = diagnostic_token_for_context(event);
    if (let_i == INVALID)
        return;
    if (!has_semicolon)
    {
        record_error(let_i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if ((event & 0xffu) == STATEMENT_CONTEXT_LET_RHS)
    {
        uint assign_i = statement_event_token(event);
        if (assign_i != INVALID && assign_i + 1u >= boundary_i)
            record_error(assign_i, ERR_EXPECTED_TOKEN, TK_IDENT);
    }
}

void validate_assignment_boundary(uint event, uint boundary_i, bool has_semicolon)
{
    uint assign_i = statement_event_token(event);
    if (assign_i == INVALID)
        return;
    if (!has_semicolon)
    {
        record_error(assign_i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if (assign_i + 1u >= boundary_i)
        record_error(assign_i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void validate_for_boundary(uint event, uint boundary_i, bool has_body)
{
    uint context = event & 0xffu;
    uint for_i = context == STATEMENT_CONTEXT_FOR_IN
        ? owner_statement_before_rhs_event(statement_event_token(event), TK_FOR)
        : statement_event_token(event);
    if (for_i == INVALID || is_impl_trait_for(for_i))
        return;

    uint in_i = context == STATEMENT_CONTEXT_FOR_IN
        ? statement_event_token(event)
        : for_in_event_before_or_at(boundary_i, for_i);
    if (in_i == INVALID || in_i <= for_i + 1u)
    {
        record_error(for_i + 1u, ERR_EXPECTED_TOKEN, TK_IN);
        return;
    }
    if (!is_expr_start(token_kind(in_i + 1u)) || in_i + 1u >= boundary_i)
    {
        record_error(in_i + 1u, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    if (!has_body)
        record_error(in_i + 1u, ERR_EXPECTED_TOKEN, TK_LBRACE);
}

void validate_pending_statement_at_boundary(uint boundary_i, bool has_semicolon, bool has_body)
{
    uint event = statement_context_kind[boundary_i];
    uint context = event & 0xffu;
    if (context == 0u)
        return;

    uint owner_i = diagnostic_token_for_context(event);
    if (owner_i == INVALID || !same_delimiter_depth_before(owner_i, boundary_i))
        return;

    if (context == TK_EXTERN)
        return;
    if (context == TK_FN)
    {
        if (has_semicolon && fn_allows_semicolon(owner_i))
            return;
        if (!has_body)
            record_pending_expected_lbrace(event);
        return;
    }
    if (context == TK_ENUM || context == TK_STRUCT)
    {
        if (!has_body)
            record_pending_expected_lbrace(event);
        return;
    }
    if (context == TK_FOR || context == STATEMENT_CONTEXT_FOR_IN)
    {
        validate_for_boundary(event, boundary_i, has_body);
        return;
    }
    if (context == TK_TYPE || context == STATEMENT_CONTEXT_TYPE_ALIAS_RHS)
    {
        validate_type_alias_boundary(event, boundary_i, has_semicolon);
        return;
    }
    if (context == TK_LET || context == STATEMENT_CONTEXT_LET_RHS)
    {
        validate_let_boundary(event, boundary_i, has_semicolon);
        return;
    }
    if (context == STATEMENT_CONTEXT_ASSIGN_RHS)
    {
        validate_assignment_boundary(event, boundary_i, has_semicolon);
        return;
    }
    if (context_requires_semicolon(context) && !has_semicolon)
        record_pending_missing_semicolon(event);
}

void validate_pending_before_statement_starter(uint i)
{
    uint event = statement_context_kind[i];
    uint context = event & 0xffu;
    if (context == 0u || context == TK_EXTERN)
        return;
    uint owner_i = diagnostic_token_for_context(event);
    if (owner_i == INVALID || owner_i >= i || !same_delimiter_depth_before(owner_i, i))
        return;
    if (context_requires_body(context))
        record_pending_expected_lbrace(event);
    else if (context_requires_semicolon(context))
        record_pending_missing_semicolon(event);
}

void validate_pending_at_end(uint i)
{
    uint n_active = active_token_count();
    if (n_active == 0u || i + 1u != n_active)
        return;
    uint kind = token_kind(i);
    if (is_statement_semicolon_kind(kind) || is_lbrace_kind(kind) || is_rbrace_kind(kind))
        return;
    validate_pending_statement_at_boundary(i, false, false);
}

uint find_condition_close(uint start_i)
{
    uint close_i = matching_close_paren_after(start_i);
    return close_i != INVALID &&
           bracket_depth_before(close_i) == bracket_depth_before(start_i) &&
           brace_depth_before(close_i) == brace_depth_before(start_i)
        ? close_i
        : INVALID;
}

uint find_fn_param_open(uint fn_i)
{
    if (token_kind(fn_i + 2u) == TK_PARAM_LPAREN)
        return fn_i + 2u;

    if (token_kind(fn_i + 2u) != TK_LT || !can_start_generic_angle_list(fn_i + 2u))
        return INVALID;

    uint generic_end = generic_angle_list_end(fn_i + 2u);
    return generic_end != INVALID && token_kind(generic_end) == TK_PARAM_LPAREN ?
        generic_end :
        INVALID;
}

bool is_trait_method_fn(uint fn_i)
{
    return fn_i < active_token_count() &&
           fn_i < gParams.n_tokens &&
           brace_depth_before(fn_i) == 1 &&
           (trait_context_event[fn_i] & 0xffu) == TRAIT_BODY_CONTEXT;
}

uint delimiter_class(uint kind)
{
    if (kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
        kind == TK_PARAM_LPAREN || kind == TK_RPAREN || kind == TK_GROUP_RPAREN ||
        kind == TK_CALL_RPAREN || kind == TK_PARAM_RPAREN)
        return 1u;
    if (kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_ARRAY_LBRACKET ||
        kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET ||
        kind == TK_ARRAY_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET)
        return 2u;
    if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_RBRACE || kind == TK_IF_RBRACE)
        return 3u;
    return 0u;
}

bool is_close_delimiter(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN || kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_ARRAY_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_RBRACE ||
           kind == TK_IF_RBRACE;
}

bool delimiter_prefix_underflows(uint close_i)
{
    uint close_kind = token_kind(close_i);
    uint class_id = delimiter_class(close_kind);
    if (class_id == 0u || !is_close_delimiter(close_kind))
        return false;

    uint block_idx = close_i / WG_SIZE;
    int depth = 0;
    if (class_id == 1u)
        depth = block_prefix_paren[block_idx] + depth_paren_inblock[close_i];
    else if (class_id == 2u)
        depth = block_prefix_bracket[block_idx] + depth_bracket_inblock[close_i];
    else
        depth = block_prefix_brace[block_idx] + depth_brace_inblock[close_i];
    return depth <= 0;
}

void check_fn(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint params_open_i = find_fn_param_open(i);
    if (params_open_i == INVALID)
    {
        record_error(i + 2u, ERR_EXPECTED_TOKEN, TK_LPAREN);
        return;
    }
}

void check_extern(uint i)
{
    uint next = token_kind(i + 1u);
    if (next == TK_FN)
        return;
    if ((next == TK_STRING || next == TK_EXTERN_ABI_STRING) && token_kind(i + 2u) == TK_FN)
        return;
    record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_FN);
}

void check_enum(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
}

void check_struct(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
}

void check_type_alias(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
}

void check_let(uint i)
{
    uint ident_kind = token_kind(i + 1u);
    if (ident_kind != TK_LET_IDENT && ident_kind != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    if (token_kind(i + 2u) == TK_COLON && !is_type_start(token_kind(i + 3u)))
    {
        record_error(i + 3u, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
        return;
    }
}

void check_return_like(uint i)
{
}

void check_condition_stmt(uint i, uint brace_kind)
{
    uint open_kind = token_kind(i + 1u);
    if (open_kind != TK_GROUP_LPAREN && open_kind != TK_LPAREN)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_LPAREN);
        return;
    }
    uint close = find_condition_close(i + 1u);
    if (close == INVALID || close <= i + 2u)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_GROUP_RPAREN);
        return;
    }
    uint actual_brace = token_kind(close + 1u);
    if (actual_brace != brace_kind && actual_brace != TK_LBRACE)
        record_error(close + 1u, ERR_EXPECTED_TOKEN, brace_kind);
}

void check_for_stmt(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
}

void check_assignment(uint i)
{
    if (!is_expr_start(token_kind(i + 1u)))
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_arg_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_CALL_LPAREN || prev == TK_ARG_COMMA || next == TK_ARG_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_array_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARRAY_COMMA ||
        prev == TK_COMMA || next == TK_ARRAY_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

bool is_open_paren_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_close_paren_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

uint paren_match_n_blocks()
{
    return gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
}

uint paren_match_leaf_base()
{
    uint n_blocks = paren_match_n_blocks();
    uint base = max(n_blocks, 1u) - 1u;
    base |= base >> 1u;
    base |= base >> 2u;
    base |= base >> 4u;
    base |= base >> 8u;
    base |= base >> 16u;
    return base + 1u;
}

public struct SyntaxParenDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return paren_match_n_blocks();
    }

    public static uint leaf_base()
    {
        return paren_match_leaf_base();
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

public struct SyntaxParenDepthRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return min(active_token_count(), gParams.n_tokens);
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

public struct SyntaxParenDepthAtMost : IRangeSearchPredicate<int, int>
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

uint angle_match_n_blocks()
{
    return gParams.n_tokens == 0u ? 1u : (gParams.n_tokens + WG_SIZE - 1u) / WG_SIZE;
}

uint angle_match_leaf_base()
{
    uint n_blocks = angle_match_n_blocks();
    uint base = max(n_blocks, 1u) - 1u;
    base |= base >> 1u;
    base |= base >> 2u;
    base |= base >> 4u;
    base |= base >> 8u;
    base |= base >> 16u;
    return base + 1u;
}

public struct SyntaxAngleDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return angle_match_n_blocks();
    }

    public static uint leaf_base()
    {
        return angle_match_leaf_base();
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

public struct SyntaxAngleDepthRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return min(active_token_count(), gParams.n_tokens);
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

uint matching_open_paren_before(uint close_i)
{
    uint n_active = active_token_count();
    if (close_i == 0u || close_i >= n_active || close_i >= gParams.n_tokens ||
        !is_close_paren_kind(token_kind(close_i)))
        return INVALID;

    int depth_before = paren_depth_before(close_i);
    int open_depth = depth_before - 1;
    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            SyntaxParenDepthTree,
            SyntaxParenDepthRows,
            SyntaxParenDepthAtMost>(
            close_i,
            open_depth,
            open_i))
        return INVALID;

    return is_open_paren_kind(token_kind(open_i)) && paren_match_depth[open_i] == open_depth ?
        open_i :
        INVALID;
}

uint matching_open_angle_before(uint token_i)
{
    uint n_active = active_token_count();
    if (token_i == 0u || token_i >= n_active || token_i >= gParams.n_tokens)
        return INVALID;

    int depth_before = angle_depth_before(token_i);
    uint open_i;
    if (!range_search_tree_last_index_before<
            int,
            int,
            SyntaxAngleDepthTree,
            SyntaxAngleDepthRows,
            SyntaxParenDepthAtMost>(
            token_i,
            depth_before - 1,
            open_i))
        return INVALID;

    return open_i < n_active &&
           is_generic_lt_kind(token_kind(open_i)) &&
           can_start_generic_angle_list(open_i) &&
           angle_match_depth[open_i] == depth_before - 1
        ? open_i
        : INVALID;
}

uint matching_close_angle_after(uint open_i)
{
    uint n_active = active_token_count();
    if (open_i >= n_active || open_i >= gParams.n_tokens ||
        !is_generic_lt_kind(token_kind(open_i)) || !can_start_generic_angle_list(open_i))
        return INVALID;

    int open_depth = angle_depth_before(open_i);
    uint close_i;
    if (!range_search_tree_first_index_at_or_after<
            int,
            int,
            SyntaxAngleDepthTree,
            SyntaxAngleDepthRows,
            SyntaxParenDepthAtMost>(
            open_i + 1u,
            open_depth,
            close_i))
        return INVALID;

    return close_i > open_i &&
           close_i < n_active &&
           is_generic_gt_kind(token_kind(close_i)) &&
           angle_match_depth[close_i] == open_depth
        ? close_i
        : INVALID;
}

uint matching_close_paren_after(uint open_i)
{
    uint n_active = active_token_count();
    if (open_i >= n_active || open_i >= gParams.n_tokens ||
        !is_open_paren_kind(token_kind(open_i)))
        return INVALID;

    int open_depth = paren_depth_before(open_i);
    uint after_close_i;
    if (!range_search_tree_first_index_at_or_after<
            int,
            int,
            SyntaxParenDepthTree,
            SyntaxParenDepthRows,
            SyntaxParenDepthAtMost>(
            open_i + 1u,
            open_depth,
            after_close_i))
    {
        uint last_i = n_active - 1u;
        return last_i > open_i &&
               is_close_paren_kind(token_kind(last_i)) &&
               paren_depth_before(last_i) == open_depth + 1
            ? last_i
            : INVALID;
    }

    if (after_close_i == 0u)
        return INVALID;

    uint close_i = after_close_i - 1u;
    return close_i > open_i &&
           close_i < n_active &&
           is_close_paren_kind(token_kind(close_i)) &&
           paren_depth_before(close_i) == open_depth + 1
        ? close_i
        : INVALID;
}

bool is_trailing_param_comma(uint i)
{
    uint next = token_kind(i + 1u);
    if (next != TK_RPAREN && next != TK_PARAM_RPAREN)
        return false;
    if (token_kind(i) == TK_PARAM_COMMA)
        return true;

    uint open_i = matching_open_paren_before(i + 1u);
    return open_i != INVALID && token_kind(open_i) == TK_PARAM_LPAREN;
}

bool is_allowed_trailing_list_comma(uint i)
{
    uint kind = token_kind(i);
    uint next = token_kind(i + 1u);
    if (is_trailing_param_comma(i))
        return true;
    if (kind == TK_ARG_COMMA)
        return next == TK_CALL_RPAREN || next == TK_RPAREN;
    if (kind == TK_ARRAY_COMMA)
        return next == TK_ARRAY_RBRACKET || next == TK_RBRACKET;
    if (kind != TK_COMMA)
        return false;
    return next == TK_RBRACE || next == TK_IF_RBRACE || next == TK_RPAREN ||
           next == TK_GROUP_RPAREN || next == TK_CALL_RPAREN || next == TK_PARAM_RPAREN ||
           next == TK_RBRACKET || next == TK_ARRAY_RBRACKET || next == TK_INDEX_RBRACKET;
}

void check_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (is_allowed_trailing_list_comma(i))
        return;
    if (prev == TK_LPAREN || prev == TK_CALL_LPAREN || prev == TK_GROUP_LPAREN ||
        prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARG_COMMA ||
        prev == TK_ARRAY_COMMA || prev == TK_PARAM_COMMA || prev == TK_COMMA ||
        next == TK_RPAREN || next == TK_CALL_RPAREN || next == TK_GROUP_RPAREN ||
        next == TK_ARRAY_RBRACKET || next == TK_RBRACKET || next == TK_ARG_COMMA ||
        next == TK_ARRAY_COMMA || next == TK_PARAM_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT || kind == TK_PATH_GENERIC_IDENT;
}

bool is_module_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT;
}

bool same_token_file(uint a, uint b)
{
    uint file = token_file(a);
    return file != INVALID && file == token_file(b);
}

bool is_file_first_token(uint i)
{
    uint file = token_file(i);
    if (file == INVALID)
        return false;
    return i == 0u || token_file(i - 1u) != file;
}

bool token_in_leading_module_decl(uint i)
{
    return i < active_token_count() &&
           i < gParams.n_tokens &&
           token_file(i) != INVALID &&
           (statement_context_kind[i] & 0xffu) == TK_MODULE;
}

bool is_leading_import_decl(uint import_i)
{
    if (token_file(import_i) == INVALID || token_kind(import_i) != TK_IMPORT)
        return false;
    if (is_file_first_token(import_i))
        return true;
    if (token_kind(import_i - 1u) != TK_SEMICOLON || !same_token_file(import_i - 1u, import_i))
        return false;
    uint previous_context = statement_context_kind[import_i - 1u] & 0xffu;
    return previous_context == TK_MODULE || previous_context == TK_IMPORT;
}

bool token_may_be_in_import_decl(uint i)
{
    return i < active_token_count() &&
           i < gParams.n_tokens &&
           token_file(i) != INVALID &&
           (statement_context_kind[i] & 0xffu) == TK_IMPORT;
}

bool token_in_leading_import_decl(uint i)
{
    return token_may_be_in_import_decl(i);
}

bool is_qualified_type_context(uint prev)
{
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_PARAM_COMMA;
}

bool is_qualified_path_colon_pair(uint first_colon_i)
{
    if (first_colon_i == 0u || token_kind(first_colon_i + 1u) != TK_COLON)
        return false;
    return is_path_segment(token_kind(first_colon_i - 1u)) &&
           is_path_segment(token_kind(first_colon_i + 2u));
}

void check_qualified_path_colon(uint i)
{
    if (token_kind(i + 1u) != TK_COLON)
        return;
    if (token_in_leading_module_decl(i))
        return;
    if (token_in_leading_import_decl(i))
        return;
    uint prev = i > 1u ? token_kind(i - 2u) : 0u;
    if (!is_qualified_type_context(prev) && !is_qualified_path_colon_pair(i))
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_COLON);
}

void check_module_decl(uint i)
{
    if (!is_file_first_token(i))
    {
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_MODULE);
        return;
    }

    uint n = active_token_count();
    if (i + 1u >= n || !same_token_file(i + 1u, i))
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    if (!is_module_path_segment(token_kind(i + 1u)))
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_import_decl(uint i)
{
    if (!is_leading_import_decl(i))
    {
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_IMPORT);
        return;
    }

    if (token_kind(i + 1u) == TK_STRING)
    {
        if (token_kind(i + 2u) != TK_SEMICOLON)
            record_error(i + 2u, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
        return;
    }

    if (!is_module_path_segment(token_kind(i + 1u)))
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_binary_operator(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (!is_expr_end(prev) || !is_expr_start(next))
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_raw_plus_minus(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    bool infix = is_expr_end(prev);
    bool prefix = is_expr_start(next);
    if (infix && !prefix)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
    else if (!infix && !prefix)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_expr_end(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_FN || prev == TK_DOT)
        return;
    if (next == TK_LPAREN || next == TK_CALL_LPAREN || next == TK_PARAM_LPAREN ||
        next == TK_COLON)
        return;
    if (next == TK_INDEX_LBRACKET || next == TK_LBRACKET)
        return;
    if (is_expr_start(next))
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
}

void check_group_lparen(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_IF || prev == TK_WHILE || prev == TK_MATCH)
        return;
    if (prev == TK_GT)
        return;
    if (prev == TK_IDENT)
        return;
    uint next = token_kind(i + 1u);
    if (next == TK_GROUP_RPAREN || next == TK_RPAREN)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_index_lbracket(uint i)
{
    if (!is_expr_start(token_kind(i + 1u)))
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(tid);
    if (i >= active_token_count())
        return;

    uint kind = token_kind(i);

    if (token_file(i) == INVALID)
        record_error(i, ERR_UNEXPECTED_TOKEN, kind);

    if (delimiter_prefix_underflows(i))
        record_error(i, ERR_UNBALANCED_DELIMITER, kind);

    if (is_stmt_keyword(kind))
        validate_pending_before_statement_starter(i);
    if (is_statement_semicolon_kind(kind))
        validate_pending_statement_at_boundary(i, true, false);
    else if (is_lbrace_kind(kind))
        validate_pending_statement_at_boundary(i, false, true);
    else if (is_rbrace_kind(kind))
        validate_pending_statement_at_boundary(i, false, false);
    validate_pending_at_end(i);

    if (token_in_generic_angle_list(i))
        return;
    if (kind != TK_IMPORT && token_may_be_in_import_decl(i) && token_in_leading_import_decl(i))
        return;

    if (kind == TK_PUB && token_kind(i + 1u) != TK_FN && token_kind(i + 1u) != TK_CONST &&
        token_kind(i + 1u) != TK_ENUM && token_kind(i + 1u) != TK_STRUCT &&
        token_kind(i + 1u) != TK_IMPL && token_kind(i + 1u) != TK_TRAIT &&
        token_kind(i + 1u) != TK_EXTERN && token_kind(i + 1u) != TK_TYPE)
        record_error(i, ERR_EXPECTED_TOKEN, TK_FN);
    else if (kind == TK_FN)
        check_fn(i);
    else if (kind == TK_ENUM)
        check_enum(i);
    else if (kind == TK_STRUCT)
        check_struct(i);
    else if (kind == TK_TYPE)
        check_type_alias(i);
    else if (kind == TK_IMPORT)
        check_import_decl(i);
    else if (kind == TK_MODULE)
        check_module_decl(i);
    else if (kind == TK_EXTERN)
        check_extern(i);
    else if (kind == TK_PARAM_IDENT && (token_kind(i + 1u) != TK_COLON || !is_type_start(token_kind(i + 2u))))
        record_error(i, ERR_EXPECTED_TOKEN, TK_COLON);
    else if (kind == TK_PARAM_COMMA &&
             token_kind(i + 1u) != TK_PARAM_IDENT && token_kind(i + 1u) != TK_IDENT &&
             token_kind(i + 1u) != TK_SELF_VALUE && token_kind(i + 1u) != TK_AMPERSAND &&
             token_kind(i + 1u) != TK_PARAM_RPAREN)
        record_error(i, ERR_EXPECTED_TOKEN, TK_PARAM_IDENT);
    else if (kind == TK_ARROW && !is_type_start(token_kind(i + 1u)) &&
             !is_expr_start(token_kind(i + 1u)))
        record_error(i, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
    else if (kind == TK_ARG_COMMA)
        check_arg_comma(i);
    else if (kind == TK_ARRAY_COMMA)
        check_array_comma(i);
    else if (kind == TK_COMMA)
        check_comma(i);
    else if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
        check_group_lparen(i);
    else if (kind == TK_INDEX_LBRACKET ||
             (kind == TK_LBRACKET && i > 0u && is_expr_end(token_kind(i - 1u))))
        check_index_lbracket(i);
    else if (kind == TK_TYPE_ARRAY_LBRACKET &&
             (!is_type_start(token_kind(i + 1u)) || token_kind(i + 2u) != TK_TYPE_SEMICOLON))
        record_error(i, ERR_EXPECTED_TOKEN, TK_TYPE_SEMICOLON);
    else if (kind == TK_COLON)
        check_qualified_path_colon(i);
    else if (kind == TK_LET)
        check_let(i);
    else if (kind == TK_RETURN || kind == TK_BREAK || kind == TK_CONTINUE)
        check_return_like(i);
    else if (kind == TK_IF)
        check_condition_stmt(i, TK_IF_LBRACE);
    else if (kind == TK_WHILE)
        check_condition_stmt(i, TK_LBRACE);
    else if (kind == TK_FOR)
    {
        if (!is_impl_trait_for(i))
            check_for_stmt(i);
    }
    else if (is_assignment_operator(kind))
        check_assignment(i);
    else if (kind == TK_PLUS || kind == TK_MINUS)
        check_raw_plus_minus(i);
    else if (is_self_receiver_ref_amp(i))
    {
    }
    else if (is_binary_operator(kind))
        check_binary_operator(i);
    else if (is_expr_end(kind))
        check_expr_end(i);
    else if (kind == TK_ELSE)
    {
        if (i == 0u || (token_kind(i - 1u) != TK_IF_RBRACE && token_kind(i - 1u) != TK_RBRACE))
            record_error(i, ERR_EXPECTED_TOKEN, TK_IF);
        else if (token_kind(i + 1u) != TK_LBRACE)
            record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
    }
}
