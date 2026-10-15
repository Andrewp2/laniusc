// Included after compact_hir_core and compact_hir_payload, with the HIR
// constants of codegen.lir.semantic.common.
//
// The checked call names the receiver as written. Parentheses around it are
// forwarding wrappers that own no LIR rows, so `(w).get()` and
// `(make()).get()` adjust, borrow or store the expression inside them.
// Returns LIR_INVALID for an invalid node or a wrapper chain deeper than 64.
uint receiver_source_hir(uint node, uint hir_count)
{
    for (uint depth = 0u; depth < 64u && node < hir_count; depth++)
    {
        uint kind = compact_hir_core[node].kind;
        HirPayload payload = compact_hir_payload[node];
        bool forward = (kind == HIR_EXPR || kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR) &&
            payload.a == HIR_EXPR_FORWARD;
        if (!forward) return node;
        node = payload.b;
    }
    return LIR_INVALID;
}

// The expression under a receiver's field projections and parentheses: `w`
// in `w.inner.get()`, `make()` in `make().inner.get()`. When it is not a
// place, the call stores it (receiver_temporary.slang). One loop handles
// both steps; a nested walk would risk the Slang loop-merge miscompile.
uint receiver_projection_root(uint node, uint hir_count)
{
    for (uint depth = 0u; depth < 128u && node < hir_count; depth++)
    {
        uint kind = compact_hir_core[node].kind;
        HirPayload payload = compact_hir_payload[node];
        bool forward = (kind == HIR_EXPR || kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR) &&
            payload.a == HIR_EXPR_FORWARD;
        if (!forward && kind != HIR_MEMBER_EXPR) return node;
        node = payload.b;
    }
    return LIR_INVALID;
}
