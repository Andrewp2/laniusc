public static const uint PARSER_FEATURE_TYPE_ARGS = 0x00000001u;
public static const uint PARSER_FEATURE_ARRAYS = 0x00000002u;
public static const uint PARSER_FEATURE_ENUMS = 0x00000004u;
public static const uint PARSER_FEATURE_MATCHES = 0x00000008u;
public static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;
// High bits are status flags, not syntax feature claims. They make parser
// retagging limits externally visible while those contexts are still being
// promoted to first-class relation rows.
public static const uint PARSER_STATUS_CONTEXT_SCAN_LIMIT = 0x80000000u;

static const uint FEATURE_TK_LT = 12u;
static const uint FEATURE_TK_GT = 13u;
static const uint FEATURE_TK_LBRACKET = 20u;
static const uint FEATURE_TK_RBRACKET = 21u;
static const uint FEATURE_TK_ENUM = 93u;
static const uint FEATURE_TK_STRUCT = 94u;
static const uint FEATURE_TK_MATCH = 95u;
static const uint FEATURE_TK_STRUCT_LIT_LBRACE = 125u;
static const uint FEATURE_TK_STRUCT_LIT_RBRACE = 126u;

public uint parser_feature_flags_for_token(uint raw_kind, uint semantic_kind)
{
    uint flags = 0u;
    if (raw_kind == FEATURE_TK_LT || raw_kind == FEATURE_TK_GT)
        flags |= PARSER_FEATURE_TYPE_ARGS;
    if (raw_kind == FEATURE_TK_LBRACKET || raw_kind == FEATURE_TK_RBRACKET)
        flags |= PARSER_FEATURE_ARRAYS;
    if (raw_kind == FEATURE_TK_ENUM)
        flags |= PARSER_FEATURE_ENUMS;
    if (raw_kind == FEATURE_TK_MATCH)
        flags |= PARSER_FEATURE_MATCHES;
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
