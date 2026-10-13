import callable_identity;

// Canonical method rows are compacted in increasing dense HIR order.
// Binary lookup avoids scanning every method at each local function call.
uint method_row_for_function(uint hir, uint hir_count)
{
    uint count = min(compact_method_count[0u], hir_count);
    uint lo = 0u; uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_method_cores[mid].node < hir) lo = mid + 1u;
        else hi = mid;
    }
    return lo < count && compact_method_cores[lo].node == hir ? lo : 0xffffffffu;
}

uint public_impl_method_symbol(uint hir, uint hir_count)
{
    uint row = method_row_for_function(hir, hir_count);
    if (row == 0xffffffffu) return 0xffffffffu;
    HirMethodCore method = compact_method_cores[row];
    HirMethodSignature signature = compact_method_signatures[row];
    return method.impl_node != 0xffffffffu && (signature.metadata & 0xffffu) == 1u
        ? interface_method_symbol(hir) : 0xffffffffu;
}

uint local_function_symbol(uint hir, uint hir_count, uint public_declaration_index, uint token_start)
{
    // Public free functions need no method lookup, as in the original native
    // selection path. Keep the shared identity policy free of resource reads.
    if (public_declaration_index != 0xffffffffu)
        return local_callable_symbol(public_declaration_index, hir, false, token_start);
    return local_callable_symbol(public_declaration_index, hir,
        public_impl_method_symbol(hir, hir_count) != 0xffffffffu, token_start);
}
