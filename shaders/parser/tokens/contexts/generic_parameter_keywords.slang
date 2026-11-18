// The grammar admits a const parameter immediately after the opening angle
// or a parameter-list comma. These keywords belong to the enclosing generic
// header and must not replace its statement owner (notably `type ... = ...`).
// `const` cannot start a statement after either separator. This local FIRST
// distinction works across scan blocks without walking a header backwards.
public bool statement_keyword_is_const_parameter(uint kind, uint previous)
{
    static const uint TK_CONST = 92u;
    static const uint TK_LT = 12u;
    static const uint TK_COMMA = 36u;
    static const uint TK_GENERIC_PARAM_LT = 133u;
    static const uint TK_GENERIC_PARAM_COMMA = 136u;
    return kind == TK_CONST && (previous == TK_LT || previous == TK_COMMA ||
        previous == TK_GENERIC_PARAM_LT || previous == TK_GENERIC_PARAM_COMMA);
}

// The keywords that begin a statement or an item.
public bool statement_keyword_starts_statement(uint kind)
{
    static const uint TK_FN = 67u;
    static const uint TK_LET = 68u;
    static const uint TK_RETURN = 69u;
    static const uint TK_IF = 70u;
    static const uint TK_ELSE = 71u;
    static const uint TK_WHILE = 72u;
    static const uint TK_BREAK = 73u;
    static const uint TK_CONTINUE = 74u;
    static const uint TK_CONST = 92u;
    static const uint TK_ENUM = 93u;
    static const uint TK_STRUCT = 94u;
    static const uint TK_IMPORT = 96u;
    static const uint TK_MODULE = 97u;
    static const uint TK_IMPL = 98u;
    static const uint TK_TRAIT = 99u;
    static const uint TK_FOR = 100u;
    static const uint TK_EXTERN = 102u;
    static const uint TK_TYPE = 103u;
    static const uint TK_MACHINE = 205u;
    return kind == TK_IMPORT || kind == TK_MODULE || kind == TK_EXTERN || kind == TK_TYPE ||
           kind == TK_CONST || kind == TK_LET || kind == TK_RETURN || kind == TK_IF ||
           kind == TK_ELSE || kind == TK_WHILE || kind == TK_FOR || kind == TK_BREAK ||
           kind == TK_CONTINUE || kind == TK_FN || kind == TK_ENUM || kind == TK_STRUCT ||
           kind == TK_IMPL || kind == TK_TRAIT || kind == TK_MACHINE;
}
