// Header boundaries consume completed raw bracket depths. The semicolon in
// [T; N] belongs to the type and cannot terminate an impl header's context.
uint impl_event_for(uint token_i, uint kind)
{
    if (kind == TK_IMPL)
        return ((token_i + 1u) << 8u) | IMPL_HEADER_CONTEXT;
    int bracket_depth = block_prefix_bracket[token_i / WG_SIZE] +
        depth_bracket_inblock[token_i];
    if (kind == TK_LBRACE || kind == TK_RBRACE ||
        (kind == TK_SEMICOLON && bracket_depth == 0))
        return (token_i + 1u) << 8u;
    return 0u;
}
