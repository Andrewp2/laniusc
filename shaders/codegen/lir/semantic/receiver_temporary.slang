// Included by local_mark, place_mark and count after compact_hir_core and
// compact_hir_payload.
//
// An auto-referenced (`&self`) receiver that is not a place, such as a call
// result or a literal, has no storage to borrow. Lowering stores it in a
// compiler-generated local, as `let` would, and the method borrows that
// local. The call owns the local, which is keyed by the method name token at
// the call site: every call has its own, and it never names a declaration.
// Returns LIR_INVALID when the receiver is a place or the call borrows none.
uint receiver_temporary_token(uint call, CheckedCallArtifact checked, uint hir_count)
{
    if (call >= hir_count || compact_hir_core[call].kind != HIR_CALL_EXPR ||
        checked.receiver_hir >= hir_count || checked.receiver_adjustment_kind != 2u ||
        checked.receiver_deref_count != 0u)
        return LIR_INVALID;
    uint member = compact_hir_payload[call].a;
    if (member >= hir_count || compact_hir_core[member].kind != HIR_MEMBER_EXPR)
        return LIR_INVALID;
    uint kind = compact_hir_core[checked.receiver_hir].kind;
    uint form = compact_hir_payload[checked.receiver_hir].a;
    // Names and projections keep their own storage. A parenthesized
    // receiver still borrows through its wrapper as before.
    bool wrapper = (kind == HIR_EXPR || kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR) &&
        (form == HIR_EXPR_FORWARD || form == HIR_EXPR_NAME);
    bool place = kind == HIR_MEMBER_EXPR || kind == HIR_INDEX_EXPR ||
        kind == HIR_NAME_EXPR || kind == HIR_PATH_EXPR || wrapper;
    return place ? LIR_INVALID : compact_hir_payload[member].c;
}
