// Included by local_mark and place_mark after compact_hir_core,
// compact_hir_payload, semantic_expr_ref_tag, semantic_expr_ref_payload and
// type_instance_kind.
#include "receiver_source.slang"
//
// An auto-referenced (`&self`) receiver that is not a place, such as a call
// result or a literal, has no storage to borrow. Lowering stores it in a
// compiler-generated local, as `let` would, and the method borrows that
// local. The call owns the local, which is keyed by the method name token at
// the call site: every call has its own, and it never names a declaration.
//
// A field of such a value (`make().inner.get()`) is borrowed the same way:
// the call stores the aggregate under the projection, its holder, and the
// method borrows the field inside the stored copy. place_mark records the
// holder in semantic_receiver_call_by_hir (receiver_words.slang), so later
// passes need not repeat this walk.

// A projected holder must be a struct, enum or array value. A reference
// result already names storage, and the projection dereferences it.
bool receiver_temporary_aggregate(uint node)
{
    uint tag = semantic_expr_ref_tag[node];
    uint payload = semantic_expr_ref_payload[node];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    uint kind = tag == 3u && payload < capacity ? type_instance_kind[payload] : 0u;
    return kind == 1u || kind == 2u || (tag == 1u && payload >= 128u);
}

// Returns LIR_INVALID when the receiver is a place, or a field of one, or
// the call borrows none. Otherwise returns the token and sets `holder`.
uint receiver_temporary_token(uint call, CheckedCallArtifact checked, uint hir_count,
                              out uint holder)
{
    holder = LIR_INVALID;
    if (call >= hir_count || compact_hir_core[call].kind != HIR_CALL_EXPR ||
        checked.receiver_hir >= hir_count || checked.receiver_adjustment_kind != 2u ||
        checked.receiver_deref_count != 0u)
        return LIR_INVALID;
    uint member = compact_hir_payload[call].a;
    if (member >= hir_count || compact_hir_core[member].kind != HIR_MEMBER_EXPR)
        return LIR_INVALID;
    uint source = receiver_source_hir(checked.receiver_hir, hir_count);
    uint root = receiver_projection_root(checked.receiver_hir, hir_count);
    if (source >= hir_count || root >= hir_count) return LIR_INVALID;
    uint kind = compact_hir_core[root].kind;
    uint form = compact_hir_payload[root].a;
    // Names and indexes keep their own storage, inside parentheses too.
    bool name = (kind == HIR_EXPR || kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR) &&
        form == HIR_EXPR_NAME;
    bool place = kind == HIR_INDEX_EXPR || kind == HIR_NAME_EXPR || kind == HIR_PATH_EXPR || name;
    if (place || (root != source && !receiver_temporary_aggregate(root))) return LIR_INVALID;
    holder = root;
    return compact_hir_payload[member].c;
}
