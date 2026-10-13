// Every named value reader consumes the same complete relation: a bound
// variable's declaration, an expression-owned binding, or the resolver's
// typed value use (for example a unit variant). Scalar caches are not types.
// Including passes provide read-only or writable declaration columns.
bool named_expression_reference(uint token, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    if (token >= gParams.n_tokens) return false;
    uint declaration = visible_decl[token];
    if (declaration >= gParams.n_tokens) declaration = token;
    tag = decl_type_ref_tag[declaration]; payload = decl_type_ref_payload[declaration];
    if (tag == 0u && declaration != token)
    {
        tag = decl_type_ref_tag[token]; payload = decl_type_ref_payload[token];
    }
    if (tag == 0u)
    {
        tag = type_expr_ref_tag[token]; payload = type_expr_ref_payload[token];
    }
    return tag != 0u;
}
