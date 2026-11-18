// Read the prefix producer's immutable impl-header context. Including passes
// own the token_impl_context_event view and supply their active token bound.
bool token_is_in_impl_header(uint token, uint count)
{
    return token < count && (token_impl_context_event[token] & 0xffu) == 1u;
}
