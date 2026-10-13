// A type expression and a record constructor apply the last path segment.
// Associated value paths apply their receiver segment before the member name.
// Including passes own the compact/path buffers and bounds adapters.
static const uint HIR_RECORD_APPLICATION_OWNER = 28u;
uint instance_token_for_owner(uint owner)
{
    if (owner >= active_hir_count()) return INVALID;
    // A bound application is a predicate identity plus ordered operands, never
    // a nominal value root. Its compact argument rows remain authoritative;
    // each operand independently owns its checked type graph. Applying this
    // role check in both collection and argument scatter prevents a synthetic
    // trait instance from imposing a combined value-layout traversal limit.
    uint semantic_kind = compact_hir_semantic_facts[owner].semantic_kind;
    if (semantic_kind == HIR_SEMANTIC_BOUND_PATH ||
        semantic_kind == HIR_SEMANTIC_BOUND_REFERENCE) return INVALID;
    uint path = path_id_by_owner_hir[owner];
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return INVALID;
    uint count = path_segment_count[path];
    if (count == 0u) return INVALID;
    bool member = compact_hir_core[owner].kind == HIR_PATH_EXPR;
    if (member && count < 2u) return INVALID;
    uint row = path_segment_base[path] + count - (member ? 2u : 1u);
    return row < gParams.n_tokens ? path_segment_token[row] : INVALID;
}
