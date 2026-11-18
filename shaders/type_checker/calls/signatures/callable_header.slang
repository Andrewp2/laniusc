// Callable target identity and generic-header ownership are distinct: a
// variant constructs its parent enum's application. Ordinary functions and
// methods retain their own header and the existing enclosing-impl relation.
StructuredBuffer<uint> fn_hir_by_decl_token;

uint callable_header_token(uint target)
{
    if (target >= gParams.n_tokens) return INVALID;
    uint owner = fn_hir_by_decl_token[target];
    if (owner < min(compact_hir_count[0u], gParams.n_hir_nodes) && compact_hir_core[owner].kind == 26u)
        return compact_hir_payload[owner].b;
    return target;
}
