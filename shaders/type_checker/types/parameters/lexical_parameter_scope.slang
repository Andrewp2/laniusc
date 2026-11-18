#include "lexical_parameter_lookup.slang"

// Whether parameter `parameter` belongs to a binder in scope at HIR row
// `row`: the nearest generic owner and its enclosing owners (an impl's
// parameters in its methods), or the implicit `Self` of an enclosing trait.
// This reference is already resolved. A nearer parameter with the same name
// must not hide an inherited identity, e.g. keep(self.field) in a method
// whose T shadows the impl's T. Validate each owner by exact parameter token.
bool lexical_parameter_reference_in_scope(uint row, uint parameter)
{
    uint hir_count = lexical_parameter_hir_count();
    if (row >= hir_count || parameter >= gParams.n_tokens) return false;
    uint count = min(generic_param_count_out[0u], gParams.n_tokens);
    uint name = name_id_by_token[parameter];
    uint owner = generic_decl_owner_by_node_a[row];
    for (uint depth = 0u; depth < hir_count && owner < hir_count; depth++)
    {
        uint owner_token = lexical_parameter_owner_token(owner);
        // resolve_generic_parameter_use_slots keys only a trait's implicit Self by its name.
        if (compact_hir_core[owner].kind == 2u && compact_hir_payload[owner].a == 10u &&
            owner_token == parameter) return true;
        uint found = generic_param_lookup_find(owner_token, name, count, gParams.n_tokens,
            generic_param_owner_token, generic_param_name_id, generic_param_lookup_state);
        if (found < count && generic_param_kind[found] == 1u &&
            generic_param_token[found] == parameter) return true;
        uint parent = lexical_parameter_parent(owner);
        if (parent == owner) break;
        owner = parent;
    }
    return false;
}

