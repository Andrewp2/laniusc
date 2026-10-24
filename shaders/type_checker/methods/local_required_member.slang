// Shared by bound-call routing and result inference. The caller supplies the
// declaration/contract tables, checked HIR, gParams and valid_hir(). Required
// trait members own signatures but deliberately have no implementation row.
uint required_member_trait(uint target)
{
    // The name marker is cleared every job and written only for methods.
    // Owner rows are sparse; an ordinary function must not read a stale one.
    if (target >= gParams.n_tokens || method_decl_name_token[target] != target ||
        method_decl_method_row[target] != INVALID) return INVALID;
    uint member = fn_hir_by_decl_token[target];
    if (!valid_hir(member)) return INVALID;
    uint trait = predicate_method_contract_owner_hir[member];
    return valid_hir(trait) && compact_hir_core[trait].kind == HIR_ITEM &&
        compact_hir_payload[trait].a == HIR_ITEM_KIND_TRAIT ? trait : INVALID;
}
