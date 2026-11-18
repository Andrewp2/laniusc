// Declaration-owned counts remain immutable. Local callable requirements
// compose a method's own constant domain with its enclosing impl domain,
// using the same compact method identity as receiver and type-slot metadata.
#include "callable_header.slang"
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;

uint required_callable_constant_count(uint function_token)
{
    if (!valid_token(function_token)) return 0u;
    uint header = callable_header_token(function_token);
    uint count = valid_token(header) ? type_decl_const_param_count_by_owner_token[header] : 0u;
    uint method = method_decl_method_row[function_token];
    if (method >= min(gParams.n_hir_nodes, compact_method_count[0u])) return count;
    uint impl_node = compact_method_cores[method].impl_node;
    if (!valid_node(impl_node)) return count;
    uint impl_token = hir_generic_owner_token(compact_hir_core[impl_node],
        compact_hir_payload[impl_node], gParams.n_tokens);
    return count + (valid_token(impl_token)
        ? type_decl_const_param_count_by_owner_token[impl_token] : 0u);
}
