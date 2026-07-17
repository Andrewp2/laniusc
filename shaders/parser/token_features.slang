public static const uint PARSER_FEATURE_TYPE_ARGS = 0x00000001u;
public static const uint PARSER_FEATURE_ARRAYS = 0x00000002u;
public static const uint PARSER_FEATURE_ENUMS = 0x00000004u;
public static const uint PARSER_FEATURE_MATCHES = 0x00000008u;
public static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;
public static const uint PARSER_FEATURE_PREDICATES = 0x00000020u;
public static const uint PARSER_FEATURE_MEMBERS = 0x00000040u;
public static const uint PARSER_FEATURE_IMPORTS = 0x00000080u;
public static const uint PARSER_FEATURE_TYPE_ALIASES = 0x00000100u;
public static const uint PARSER_FEATURE_STRING_EXPRS = 0x00000200u;

static const uint FEATURE_TK_LBRACKET = 20u;
static const uint FEATURE_TK_RBRACKET = 21u;
static const uint FEATURE_TK_DOT = 35u;
static const uint FEATURE_TK_STRING = 32u;
static const uint FEATURE_TK_ENUM = 93u;
static const uint FEATURE_TK_STRUCT = 94u;
static const uint FEATURE_TK_MATCH = 95u;
static const uint FEATURE_TK_IMPORT = 96u;
static const uint FEATURE_TK_IMPL = 98u;
static const uint FEATURE_TK_TRAIT = 99u;
static const uint FEATURE_TK_WHERE = 104u;
static const uint FEATURE_TK_TYPE = 103u;
static const uint FEATURE_TK_BOUND_COLON = 107u;
static const uint FEATURE_TK_STRUCT_LIT_LBRACE = 125u;
static const uint FEATURE_TK_STRUCT_LIT_RBRACE = 126u;
static const uint FEATURE_TK_TYPE_ARG_LT = 131u;
static const uint FEATURE_TK_TYPE_ARG_GT = 132u;
static const uint FEATURE_TK_GENERIC_PARAM_LT = 133u;
static const uint FEATURE_TK_GENERIC_PARAM_GT = 134u;
static const uint FEATURE_TK_BOUND_TYPE_ARG_LT = 175u;
static const uint FEATURE_TK_BOUND_TYPE_ARG_GT = 176u;
static const uint FEATURE_TK_PATH_TYPE_ARG_LT = 184u;
static const uint FEATURE_TK_PATH_TYPE_ARG_GT = 185u;

public uint parser_feature_flags_for_token(uint raw_kind, uint semantic_kind)
{
    uint flags = 0u;
    if (semantic_kind == FEATURE_TK_TYPE_ARG_LT ||
        semantic_kind == FEATURE_TK_TYPE_ARG_GT ||
        semantic_kind == FEATURE_TK_GENERIC_PARAM_LT ||
        semantic_kind == FEATURE_TK_GENERIC_PARAM_GT ||
        semantic_kind == FEATURE_TK_BOUND_TYPE_ARG_LT ||
        semantic_kind == FEATURE_TK_BOUND_TYPE_ARG_GT ||
        semantic_kind == FEATURE_TK_PATH_TYPE_ARG_LT ||
        semantic_kind == FEATURE_TK_PATH_TYPE_ARG_GT)
    {
        flags |= PARSER_FEATURE_TYPE_ARGS;
    }
    if (raw_kind == FEATURE_TK_LBRACKET || raw_kind == FEATURE_TK_RBRACKET)
        flags |= PARSER_FEATURE_ARRAYS;
    if (raw_kind == FEATURE_TK_DOT)
        flags |= PARSER_FEATURE_MEMBERS;
    if (raw_kind == FEATURE_TK_ENUM)
        flags |= PARSER_FEATURE_ENUMS;
    if (raw_kind == FEATURE_TK_MATCH)
        flags |= PARSER_FEATURE_MATCHES;
    if (raw_kind == FEATURE_TK_IMPORT)
        flags |= PARSER_FEATURE_IMPORTS;
    if (raw_kind == FEATURE_TK_TYPE)
        flags |= PARSER_FEATURE_TYPE_ALIASES;
    if (semantic_kind == FEATURE_TK_STRING)
        flags |= PARSER_FEATURE_STRING_EXPRS;
    if (raw_kind == FEATURE_TK_IMPL || raw_kind == FEATURE_TK_TRAIT ||
        raw_kind == FEATURE_TK_WHERE || semantic_kind == FEATURE_TK_BOUND_COLON)
    {
        flags |= PARSER_FEATURE_PREDICATES;
    }
    if (raw_kind == FEATURE_TK_STRUCT ||
        semantic_kind == FEATURE_TK_STRUCT_LIT_LBRACE ||
        semantic_kind == FEATURE_TK_STRUCT_LIT_RBRACE)
    {
        flags |= PARSER_FEATURE_STRUCTS;
    }
    return flags;
}

public bool parser_feature_enabled(StructuredBuffer<uint> feature_flags, uint feature)
{
    return (feature_flags[0u] & feature) != 0u;
}
