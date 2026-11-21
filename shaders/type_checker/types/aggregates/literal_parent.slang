// The nearest struct-literal ancestor of `node` (INVALID: none).
uint literal_parent(uint node, uint count)
{
    uint ancestor = compact_hir_core[node].parent;
    for (uint steps = 0u; ancestor < count && steps < count; steps++)
    {
        if (compact_hir_core[ancestor].kind == HIR_STRUCT_LITERAL) return ancestor;
        ancestor = compact_hir_core[ancestor].parent;
    }
    return INVALID;
}
