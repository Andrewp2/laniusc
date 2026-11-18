// A type expression and a record constructor apply the last path segment.
// Associated value paths apply their receiver segment before the member name.
// Including passes own the compact/path buffers and bounds adapters.
static const uint HIR_RECORD_APPLICATION_OWNER = 28u;
uint instance_token_for_owner(uint owner)
{
    if (owner >= active_hir_count()) return INVALID;
    // Canonical predicate compaction publishes this owner only on the bound
    // application, for both generic bounds and trait impl headers. Operands
    // and impl receivers retain their ordinary type roles. A bound application
    // is a predicate identity plus ordered operands, never a nominal value
    // root: each operand independently owns its checked type graph. Sharing
    // this role check between collection and argument scatter avoids imposing
    // a combined value-layout traversal limit on a predicate's operand list.
    if (compact_hir_semantic_facts[owner].predicate_owner < active_hir_count())
        return INVALID;
    uint path = path_id_by_owner_hir[owner];
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return INVALID;
    uint count = path_segment_count[path];
    if (count == 0u) return INVALID;
    bool member = compact_hir_core[owner].kind == HIR_PATH_EXPR;
    if (member && count < 2u) return INVALID;
    uint row = path_segment_base[path] + count - (member ? 2u : 1u);
    return row < gParams.n_tokens ? path_segment_token[row] : INVALID;
}
