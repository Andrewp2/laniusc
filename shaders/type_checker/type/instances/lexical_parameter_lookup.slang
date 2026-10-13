#ifndef LEXICAL_HIR_CAPACITY
#define LEXICAL_HIR_CAPACITY gParams.n_hir_nodes
#define LEXICAL_TOKEN_CAPACITY gParams.n_tokens
#endif
// Included by declaration-use and body-replay consumers. The nearest generic
// owner is a declaration identity; its parent's owner is the enclosing scope.
uint lexical_parameter_hir_count()
{
    return min(LEXICAL_HIR_CAPACITY, compact_hir_count[0u]);
}

uint lexical_parameter_owner_token(uint owner)
{
    if (owner >= lexical_parameter_hir_count()) return 0xffffffffu;
    return hir_generic_owner_token(compact_hir_core[owner], compact_hir_payload[owner],
        LEXICAL_TOKEN_CAPACITY);
}

uint lexical_parameter_parent(uint owner)
{
    if (owner >= lexical_parameter_hir_count()) return 0xffffffffu;
    uint parent = compact_hir_core[owner].parent;
    return parent < lexical_parameter_hir_count()
        ? generic_decl_owner_by_node_a[parent] : 0xffffffffu;
}

uint lexical_parameter_row(uint node, uint name_token, uint kind)
{
    uint hir_count = lexical_parameter_hir_count();
    if (node >= hir_count || name_token >= LEXICAL_TOKEN_CAPACITY) return 0xffffffffu;
    uint name = name_id_by_token[name_token];
    uint count = min(generic_param_count_out[0u], LEXICAL_TOKEN_CAPACITY);
    uint owner = generic_decl_owner_by_node_a[node];
    for (uint depth = 0u; depth < hir_count && owner < hir_count; depth++)
    {
        uint row = generic_param_lookup_find(lexical_parameter_owner_token(owner), name,
            count, LEXICAL_TOKEN_CAPACITY, generic_param_owner_token, generic_param_name_id,
            generic_param_lookup_state);
        // A name in the nearer scope shadows the enclosing name, including
        // when its parameter kind differs from the requested kind.
        if (row < count) return generic_param_kind[row] == kind ? row : 0xffffffffu;
        uint parent = lexical_parameter_parent(owner);
        if (parent == owner) break;
        owner = parent;
    }
    return 0xffffffffu;
}
