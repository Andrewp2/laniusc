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
