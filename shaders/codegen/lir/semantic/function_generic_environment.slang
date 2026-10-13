// One decision for omission and direct-call eligibility. A callable captures
// parameters from every lexical ancestor, even when it declares none itself.
// Invalid ancestry is never classified as an ordinary direct-call target.
bool function_has_generic_environment(uint function_hir, uint hir_count)
{
    if (function_hir >= hir_count) return true;
    uint owner = function_hir;
    for (uint depth = 0u; depth < hir_count; depth++)
    {
        if (compact_generic_param_ranges[owner].count != 0u) return true;
        uint parent = compact_hir_core[owner].parent;
        if (parent == 0xffffffffu) return false;
        // Canonical accepted HIR parents precede their children.
        if (parent >= owner) return true;
        owner = parent;
    }
    return true;
}
