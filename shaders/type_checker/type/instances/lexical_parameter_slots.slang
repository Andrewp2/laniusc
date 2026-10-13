#include "lexical_parameter_lookup.slang"

// Separate dense type and constant domains. Enclosing parameters precede a
// declaration's own parameters; declaration tokens remain their identities.
uint lexical_parameter_slot(uint row)
{
    uint count = min(generic_param_count_out[0u], gParams.n_tokens);
    uint hir_count = lexical_parameter_hir_count();
    if (row >= count) return 0xffffffffu;
    uint owner = compact_generic_params[row].owner;
    if (owner >= hir_count) return 0xffffffffu;
    HirRange range = compact_generic_param_ranges[owner];
    if (range.start == 0xffffffffu || row < range.start || row - range.start >= range.count)
        return 0xffffffffu;
    bool constant = generic_param_kind[row] == 2u;
    uint slot = constant
        ? generic_const_param_prefix[row] - generic_const_param_prefix[range.start]
        : generic_type_param_prefix[row] - generic_type_param_prefix[range.start];
    owner = lexical_parameter_parent(owner);
    for (uint depth = 0u; depth < hir_count && owner < hir_count; depth++)
    {
        uint token = lexical_parameter_owner_token(owner);
        if (token >= gParams.n_tokens) return 0xffffffffu;
        slot += constant ? type_decl_const_param_count_by_owner_token[token]
                         : type_decl_generic_param_count_by_owner_token[token];
        uint parent = lexical_parameter_parent(owner);
        if (parent == owner) return 0xffffffffu;
        owner = parent;
    }
    return slot;
}
