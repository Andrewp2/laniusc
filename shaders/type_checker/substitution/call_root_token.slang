// The call token whose expansion word a call root carries (04 and list_call_field_closure_roots).
// Included by kernels that bind compact_hir_count, compact_hir_core and
// compact_hir_payload and define hir_count() and INVALID.
uint call_token(uint call)
{
    if (call >= hir_count()) return INVALID;
    if (compact_hir_core[call].kind == 28u || compact_hir_core[call].kind == 33u)
        return compact_hir_core[call].token_start;
    if (compact_hir_core[call].kind != 19u) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return INVALID;
    uint kind = compact_hir_core[callee].kind;
    if (kind != 21u && kind != 22u && kind != 33u) return INVALID;
    uint token = kind == 21u ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < gParams.n_tokens ? token : compact_hir_core[callee].token_start;
}
