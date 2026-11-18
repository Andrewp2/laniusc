// Read a constructor's checked source reference before contextual refinement.
// Both field context and expression projection consume this same identity.
bool checked_record_constructor_reference(uint node, out uint tag, out uint payload,
    out uint declaration)
{
    static const uint INVALID_CONSTRUCTOR = 0xffffffffu;
    tag = 0u; payload = INVALID_CONSTRUCTOR; declaration = INVALID_CONSTRUCTOR;
    uint constructor = compact_hir_core[node].token_start;
    if (constructor >= gParams.n_tokens) return false;
    // Constructor paths resolve in the type namespace. The value-name table
    // need not contain a declaration for a type occurrence.
    uint path = path_id_by_owner_hir[node];
    if (path < min(path_count_out[0u], gParams.n_hir_nodes))
    {
        uint resolved = resolved_type_decl[path];
        if (resolved < gParams.n_tokens)
            declaration = decl_name_token[resolved];
    }
    if (declaration >= gParams.n_tokens) declaration = visible_decl[constructor];
    tag = type_expr_ref_tag[constructor];
    payload = type_expr_ref_payload[constructor];
    if (tag == 0u && declaration < gParams.n_tokens)
    {
        tag = decl_type_ref_tag[declaration];
        payload = decl_type_ref_payload[declaration];
    }
    uint capacity; uint stride;
    type_instance_decl_token.GetDimensions(capacity, stride);
    if (tag == 3u && payload < capacity)
    {
        declaration = type_instance_decl_token[payload];
        return true;
    }
    // A bare generic declaration is not an instantiated value type. Its
    // arguments must come from an explicit application or checked context.
    if (tag != 1u || payload == 0u || payload == INVALID_CONSTRUCTOR ||
        declaration >= gParams.n_tokens ||
        type_decl_generic_param_count_by_owner_token[declaration] != 0u) return false;
    uint owner = type_decl_hir_node_by_token[declaration];
    return owner < gParams.n_hir_nodes && compact_hir_core[owner].kind == 27u;
}
