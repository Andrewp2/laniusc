// Retags raw lexer tokens into the parser's semantic token alphabet.
//
// Every structural question is a table read: delimiter ownership comes from
// token_enclosing_open (tokens_delimiter_match_03_enclosing_opens) and each raw
// `<`'s own role from token_direct_lt_kind (tokens_to_angle_kinds). A token
// whose role depends on an opener (closers, separators, signs, a call after a
// generic list) re-derives that opener's kind from the same tables.

import atomics;
import token_features;

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
StructuredBuffer<uint> token_direct_lt_kind;

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

#include "token_relations.slang"

static const uint TK_NOT = 19u;
static const uint TK_RETURN_NEVER = 197u;

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

// The semantic kind of the raw `<` at parser_i.
uint semantic_lt_kind_for(uint parser_i, uint count)
{
    uint kind = token_direct_lt_kind[parser_i - 1u];
    if (kind != TK_PATH_TYPE_ARG_LT && kind != TK_BOUND_TYPE_ARG_LT) return kind;
    uint parent;
    if (!matching_raw_angle_open_before(parser_i, count, parent)) return kind;
    uint parent_kind = token_direct_lt_kind[parent];
    // A qualified application inside a generic argument is a type path.
    // The outer application's value context cannot turn its children into
    // independent value applications. Raw angle ownership supplies this
    // evidence before contextual >> splitting and identifier retagging.
    if (kind == TK_BOUND_TYPE_ARG_LT && parent_kind == TK_GENERIC_PARAM_LT) return kind;
    if (parent_kind == TK_TYPE_ARG_LT || parent_kind == TK_PATH_TYPE_ARG_LT ||
        parent_kind == TK_GENERIC_PARAM_LT || parent_kind == TK_BOUND_TYPE_ARG_LT)
        return TK_TYPE_ARG_LT;
    return kind;
}

bool semantic_token_before_ends_primary(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint prev_parser_i = parser_i - 1u;
    uint prev_raw = raw_kind_at(prev_parser_i, count);
    if (semantic_token_ends_primary(prev_raw))
        return true;
    if (prev_raw == TK_GT || prev_raw == TK_SHR)
    {
        uint open_i;
        // A closed value application can be called. A comparison's `>`
        // retains its expression role; delimiter ownership supplies the head.
        return matching_raw_angle_open_for_close(prev_parser_i, count, open_i) &&
               semantic_lt_kind_for(open_i + 1u, count) == TK_PATH_TYPE_ARG_LT;
    }
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

bool in_pattern_context(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;

    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_match_pattern_context_event[token_i] & 0xffu) == MATCH_PATTERN_CONTEXT;
}

bool in_trait_body_context(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count) == TK_TRAIT_LBRACE;
}

bool fn_param_lparen_context(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint prev2 = raw_kind_at(parser_i - 2u, count);
    if (prev2 == TK_FN && prev == TK_IDENT)
        return true;

    if (prev != TK_GT)
        return false;

    uint open_i;
    if (!matching_raw_angle_open_for_close(parser_i - 1u, count, open_i))
        return false;
    uint open_parser_i = open_i + 1u;
    return raw_kind_at(open_parser_i - 1u, count) == TK_IDENT &&
           raw_kind_at(open_parser_i - 2u, count) == TK_FN;
}

// The semantic kind of the raw `(` at parser_i.
uint semantic_paren_open_kind_for(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    if (in_pattern_context(parser_i, count))
        return TK_PATTERN_LPAREN;
    if (in_enum_variant_context(parser_i, count) && prev == TK_IDENT)
        return TK_ENUM_PAYLOAD_LPAREN;
    if (fn_param_lparen_context(parser_i, count))
        return TK_PARAM_LPAREN;
    return semantic_token_before_ends_primary(parser_i, count) ? TK_CALL_LPAREN : TK_GROUP_LPAREN;
}

// The `)` closing a raw `(` of the given semantic kind (0 when unmatched).
uint semantic_rparen_kind_for(uint open_kind)
{
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
    return TK_RPAREN;
}

// Brace classification and close pairing are owned by
// tokens_delimiters_03_owner_local, tokens_brace_context and the brace PSE
// pairing pass. A missing record keeps the raw token.
uint semantic_brace_kind_for(uint parser_i, uint raw_kind)
{
    uint recorded = brace_semantic_kind[parser_i - 1u];
    return recorded != 0u ? recorded : raw_kind;
}

uint semantic_gt_kind_for(uint parser_i, uint count)
{
    uint open_i;
    if (!matching_raw_angle_open_before(parser_i, count, open_i))
        return TK_GT;
    uint open_kind = semantic_lt_kind_for(open_i + 1u, count);
    if (open_kind == TK_TYPE_ARG_LT)
        return TK_TYPE_ARG_GT;
    if (open_kind == TK_GENERIC_PARAM_LT)
        return TK_GENERIC_PARAM_GT;
    if (open_kind == TK_BOUND_TYPE_ARG_LT)
        return TK_BOUND_TYPE_ARG_GT;
    if (open_kind == TK_PATH_TYPE_ARG_LT)
    {
        if (open_i >= 2u && token_words[open_i - 2u].kind == TK_DOT)
            return TK_MEMBER_TYPE_ARG_GT;
        return TK_PATH_TYPE_ARG_GT;
    }
    return TK_GT;
}

// The raw `,` at parser_i takes the role of its innermost enclosing list. The
// caller supplies the classified raw `(` enclosing it, if any.
uint semantic_comma_kind_for(
    uint parser_i,
    uint count,
    bool has_paren_open,
    uint paren_open_i,
    uint paren_open)
{
    uint best_open_i = 0u;
    uint best_kind = 0u;
    uint open_i;

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

    if (has_paren_open)
    {
        open_i = paren_open_i;
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

    uint brace_open_i;
    uint brace_open;
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
    if (enclosing_semantic_brace_open_before(parser_i, count) == TK_MATCH_LBRACE)
        return TK_MATCH_ARROW;
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    if (prev_raw == TK_RPAREN || prev_raw == TK_GT)
        return TK_RETURN_ARROW;
    return TK_MATCH_ARROW;
}

// A signed scalar operand has its own syntactic role. This classification is
// derived from the already matched opener/comma or array-length separator;
// ordinary expression signs keep their existing prefix/infix roles. The caller
// supplies the kind of a preceding `,`.
bool constant_argument_sign_context(uint parser_i, uint count, uint prev_comma_kind)
{
    if (parser_i <= 1u) return false;
    uint before = parser_i - 1u;
    uint raw = raw_kind_at(before, count);
    if (raw == TK_LT)
    {
        uint kind = semantic_lt_kind_for(before, count);
        return kind == TK_TYPE_ARG_LT || kind == TK_PATH_TYPE_ARG_LT ||
            kind == TK_BOUND_TYPE_ARG_LT;
    }
    if (raw == TK_COMMA)
    {
        return prev_comma_kind == TK_TYPE_ARG_COMMA ||
            prev_comma_kind == TK_PATH_TYPE_ARG_COMMA ||
            prev_comma_kind == TK_BOUND_TYPE_ARG_COMMA;
    }
    return raw == TK_SEMICOLON && before - 1u < count &&
        bracket_semantic_kind[before - 1u] == TK_TYPE_SEMICOLON;
}

// A type `&` followed by `mut` opens `&mut T` or `&mut self`.
uint type_ampersand_kind(uint parser_i, uint count)
{
    return raw_kind_at(parser_i + 1u, count) == TK_MUT ? TK_TYPE_AMPERSAND_MUT : TK_TYPE_AMPERSAND;
}

// `+`, `-` and `&` after an operand are infix; otherwise their roles come
// from the sign, bound or type context.
uint semantic_operator_kind_for(uint parser_i, uint count, uint raw_kind, uint prev_comma_kind)
{
    bool infix = semantic_token_before_ends_primary(parser_i, count);
    if (raw_kind == TK_AMPERSAND)
    {
        if (bound_type_context_before(parser_i, count))
        {
            uint parent;
            if (matching_raw_angle_open_before(parser_i, count, parent))
            {
                uint parent_kind = token_direct_lt_kind[parent];
                if (parent_kind == TK_BOUND_TYPE_ARG_LT || parent_kind == TK_TYPE_ARG_LT ||
                    parent_kind == TK_PATH_TYPE_ARG_LT) return type_ampersand_kind(parser_i, count);
            }
            return TK_BOUND_TYPE_AMPERSAND;
        }
        return infix ? TK_AMPERSAND : type_ampersand_kind(parser_i, count);
    }

    bool plus = raw_kind == TK_PLUS;
    if (constant_argument_sign_context(parser_i, count, prev_comma_kind))
        return plus ? TK_CONSTANT_ARGUMENT_PLUS : TK_CONSTANT_ARGUMENT_MINUS;
    if (plus && bound_context(parser_i, count))
        return TK_BOUND_PLUS;
    if (plus)
        return infix ? TK_INFIX_PLUS : TK_PREFIX_PLUS;
    return infix ? TK_INFIX_MINUS : TK_PREFIX_MINUS;
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

uint semantic_semicolon_kind_for(uint parser_i, uint count)
{
    uint token_i = parser_i - 1u;
    if (bracket_semantic_kind[token_i] == TK_TYPE_SEMICOLON)
        return TK_TYPE_SEMICOLON;
    if (bracket_semantic_kind[token_i] == TK_ARRAY_SEMICOLON)
        return TK_ARRAY_SEMICOLON;
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
        uint owner = enclosing_semantic_brace_open_before(parser_i, count);
        if (owner == TK_IMPL_LBRACE)
            return TK_IMPL_PUB;
        if (owner == TK_TRAIT_LBRACE)
            return TK_TRAIT_PUB;
        return TK_PUB;
    }
    // The count of `[value; count]` is an integer literal with its own kind,
    // so the array's closing bracket after it has a unique predecessor pair.
    if (raw_kind == TK_INT && parser_i >= 2u && parser_i - 2u < count &&
        bracket_semantic_kind[parser_i - 2u] == TK_ARRAY_SEMICOLON)
        return TK_ARRAY_REPEAT_COUNT;
    if (raw_kind == TK_STRING && statement_context_token_kind(parser_i - 1u) == TK_IMPORT)
        return TK_IMPORT_STRING;
    if (raw_kind == TK_STRING && statement_context_token_kind(parser_i - 1u) == TK_EXTERN)
        return TK_EXTERN_ABI_STRING;
    if (raw_kind == TK_LBRACKET || raw_kind == TK_RBRACKET)
    {
        uint recorded = bracket_semantic_kind[parser_i - 1u];
        return recorded != 0u ? recorded : raw_kind;
    }
    if (raw_kind == TK_LBRACE || raw_kind == TK_RBRACE)
        return semantic_brace_kind_for(parser_i, raw_kind);
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
    // A `!` right after a return arrow is the never type, not logical not.
    // The arrow before a match arm's `!flag` is a match arrow, so arm bodies
    // keep their unary operator.
    if (raw_kind == TK_NOT && raw_kind_at(parser_i - 1u, count) == TK_ARROW &&
        semantic_arrow_kind_for(parser_i - 1u, count) == TK_RETURN_ARROW)
        return TK_RETURN_NEVER;
    bool sign =raw_kind == TK_PLUS || raw_kind == TK_MINUS;
    if (raw_kind != TK_LPAREN && raw_kind != TK_RPAREN && raw_kind != TK_COMMA && !sign &&
        raw_kind != TK_AMPERSAND)
        return raw_kind;

    // The rest take the role of a raw `(` (their own, the one they close, or
    // the one enclosing their list separator) and of a `,` (their own, or the
    // one a sign follows). A token needs at most one of each, so both are
    // classified at a single site.
    uint comma_parser_i = raw_kind == TK_COMMA ? parser_i : 0u;
    if (sign && raw_kind_at(parser_i - 1u, count) == TK_COMMA)
        comma_parser_i = parser_i - 1u;
    uint paren_open_i = parser_i - 1u;
    bool has_paren_open = raw_kind == TK_LPAREN;
    if (raw_kind == TK_RPAREN || comma_parser_i != 0u)
        has_paren_open = matching_raw_paren_open_before(
            raw_kind == TK_RPAREN ? parser_i : comma_parser_i,
            count,
            paren_open_i);
    uint paren_open = has_paren_open ? semantic_paren_open_kind_for(paren_open_i + 1u, count) : 0u;
    if (raw_kind == TK_LPAREN)
        return paren_open;
    if (raw_kind == TK_RPAREN)
        return semantic_rparen_kind_for(paren_open);

    uint comma_kind = comma_parser_i != 0u
        ? semantic_comma_kind_for(comma_parser_i, count, has_paren_open, paren_open_i, paren_open)
        : 0u;
    if (raw_kind == TK_COMMA)
        return comma_kind;
    return semantic_operator_kind_for(parser_i, count, raw_kind, comma_kind);
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
