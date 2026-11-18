// Unit-local callable identities shared by native definitions, deferred calls,
// and portable implementation evidence. The enclosing library/unit identity
// is supplied at the object or interface boundary.
public uint interface_method_symbol(uint method_hir)
{
    // Required trait methods use this identity even when the requirement is
    // private. An implementation's native callable can have a different symbol.
    return 0x80000000u | method_hir;
}

public uint local_callable_symbol(
    uint public_declaration_index,
    uint method_hir,
    bool public_impl_method,
    uint token_start)
{
    if (public_declaration_index != 0xffffffffu) return public_declaration_index;
    if (public_impl_method) return interface_method_symbol(method_hir);
    return 0x40000000u | token_start;
}
