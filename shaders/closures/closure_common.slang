// Shared layout of the closure rewrite. A closure `|x: T| body` becomes a
// struct literal at its site and a struct, a `borrow` impl and a trait impl
// appended to its file. The kernels work on raw lexer tokens.
module closure_common;

import generated_token_ids;

public static const uint CL_INVALID = 0xffffffffu;

// Words of one closure record.
public static const uint REC_WORDS = 12u;
public static const uint REC_START = 0u;
public static const uint REC_PARAM = 1u;
public static const uint REC_PTYPE_FIRST = 2u;
public static const uint REC_PTYPE_LAST = 3u;
public static const uint REC_RTYPE_FIRST = 4u;
public static const uint REC_RTYPE_LAST = 5u;
public static const uint REC_BODY_FIRST = 6u;
public static const uint REC_BODY_LAST = 7u;
public static const uint REC_FLAGS = 8u;
public static const uint REC_FILE = 9u;
public static const uint REC_CAP_FIRST = 10u;
public static const uint REC_CAP_COUNT = 11u;

public static const uint FLAG_BRACED = 1u;
public static const uint FLAG_NO_PARAM = 2u;
public static const uint FLAG_RTYPE = 4u;
public static const uint FLAG_MOVE = 8u;

// Binder roles of an identifier token.
public static const uint ROLE_LET = 1u;
public static const uint ROLE_TYPED = 2u;
public static const uint ROLE_FOR = 4u;
public static const uint ROLE_PARAM = 8u;

// Error codes. The status word holds the least `token << 4 | code`.
public static const uint ERR_PARAM_TYPE = 1u;
public static const uint ERR_HEADER = 2u;
public static const uint ERR_BODY = 3u;
public static const uint ERR_NESTED = 4u;
public static const uint ERR_SELF = 5u;
public static const uint ERR_CAPTURE_TYPE = 6u;
public static const uint ERR_RTYPE_BODY = 7u;

// Piece counts. A file has PIECES_PER_FILE pieces plus those of its closures
// and captures: the text before the import, the import, and the text after
// the last closure. A closure has one piece of text before it, its site and
// its appendix.
public static const uint PIECES_PER_FILE = 3u;
public static const uint SITE_FIXED = 4u;
public static const uint SITE_PER_CAPTURE = 4u;
public static const uint APPENDIX_FIXED = 25u;
public static const uint APPENDIX_PER_CAPTURE = 11u;
public static const uint PIECES_PER_CLOSURE = 30u;
public static const uint PIECES_PER_CAPTURE = 15u;

// Piece kinds.
public static const uint PIECE_COPY = 0u;
public static const uint PIECE_CONST = 1u;
public static const uint PIECE_ID = 2u;
public static const uint ID_DIGITS = 10u;

// Constant strings, in the order of the host table.
public static const uint C_NAME = 0u;
public static const uint C_LBRACE = 1u;
public static const uint C_COLON = 2u;
public static const uint C_COMMA = 3u;
public static const uint C_SITE_END = 4u;
public static const uint C_STRUCT = 5u;
public static const uint C_IMPL = 6u;
public static const uint C_BORROW = 7u;
public static const uint C_TRAIT_IMPL = 8u;
public static const uint C_GENERIC_R = 9u;
public static const uint C_MAPPER = 10u;
public static const uint C_PRODUCER = 11u;
public static const uint C_R = 12u;
public static const uint C_FOR = 13u;
public static const uint C_APPLY = 14u;
public static const uint C_PRODUCE = 15u;
public static const uint C_RET = 16u;
public static const uint C_LET = 17u;
public static const uint C_SELF = 18u;
public static const uint C_SEMI = 19u;
public static const uint C_RETURN = 20u;
public static const uint C_END_EXPR = 21u;
public static const uint C_END_BLOCK = 22u;
public static const uint C_IMPORT = 23u;
public static const uint C_SITE_END_OWNED = 24u;

public bool tk_paren_open(uint k)
{
    return k == TK_LPAREN || k == TK_CALL_LPAREN || k == TK_GROUP_LPAREN || k == TK_PARAM_LPAREN ||
           k == TK_PATTERN_LPAREN || k == TK_ENUM_PAYLOAD_LPAREN;
}

public bool tk_paren_close(uint k)
{
    return k == TK_RPAREN || k == TK_GROUP_RPAREN || k == TK_CALL_RPAREN || k == TK_PARAM_RPAREN ||
           k == TK_PATTERN_RPAREN || k == TK_ENUM_PAYLOAD_RPAREN;
}

public bool tk_bracket_open(uint k)
{
    return k == TK_LBRACKET || k == TK_INDEX_LBRACKET || k == TK_ARRAY_LBRACKET || k == TK_TYPE_ARRAY_LBRACKET;
}

public bool tk_bracket_close(uint k)
{
    return k == TK_RBRACKET || k == TK_ARRAY_RBRACKET || k == TK_INDEX_RBRACKET || k == TK_TYPE_ARRAY_RBRACKET;
}

public bool tk_brace_open(uint k)
{
    return k == TK_LBRACE || k == TK_IF_LBRACE || k == TK_MATCH_LBRACE || k == TK_IMPL_LBRACE ||
           k == TK_TRAIT_LBRACE || k == TK_STRUCT_LIT_LBRACE || k == TK_STRUCT_DECL_LBRACE ||
           k == TK_ENUM_LBRACE || k == TK_FN_BLOCK_LBRACE || k == TK_IMPL_FN_BLOCK_LBRACE;
}

public bool tk_brace_close(uint k)
{
    return k == TK_RBRACE || k == TK_IF_RBRACE || k == TK_MATCH_RBRACE || k == TK_IMPL_RBRACE ||
           k == TK_TRAIT_RBRACE || k == TK_STRUCT_LIT_RBRACE || k == TK_STRUCT_DECL_RBRACE ||
           k == TK_ENUM_RBRACE || k == TK_FN_BLOCK_RBRACE || k == TK_IMPL_FN_BLOCK_RBRACE;
}

public bool tk_open(uint k)
{
    return tk_paren_open(k) || tk_bracket_open(k) || tk_brace_open(k);
}

public bool tk_close(uint k)
{
    return tk_paren_close(k) || tk_bracket_close(k) || tk_brace_close(k);
}

// The nesting depth change of a token, as a two's complement word.
public uint tk_depth_delta(uint k)
{
    if (tk_open(k))
        return 1u;
    if (tk_close(k))
        return 0xffffffffu;
    return 0u;
}

public bool tk_semicolon(uint k)
{
    return k == TK_SEMICOLON || k == TK_MODULE_SEMICOLON || k == TK_LET_SEMICOLON ||
           k == TK_RETURN_SEMICOLON || k == TK_EXPR_SEMICOLON;
}

public bool tk_comma(uint k)
{
    return k == TK_COMMA || k == TK_ARG_COMMA || k == TK_PARAM_COMMA || k == TK_STRUCT_LIT_COMMA;
}

public bool tk_assign(uint k)
{
    return k == TK_ASSIGN || k == TK_LET_ASSIGN;
}

public void closure_error(RWStructuredBuffer<uint> status, uint token, uint code)
{
    uint prior = 0u;
    InterlockedMin(status[0], (token << 4u) | code, prior);
}
