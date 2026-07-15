// Validate generic-bound argument rows after declaration resolution.
//
// The preceding collector owns bound syntax, generic subjects, and trait-path
// resolution. This pass consumes those records and independently validates the
// argument types and the resolved trait's generic arity.

#define PREDICATE_BOUND_DECL_RESOLUTION 0
#include "collect_common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || node_kind[node] != PROD_BOUND_TYPE_IDENT)
        return;

    uint owner_decl = predicate_owner_node[node];
    uint trait_decl_i = predicate_bound_decl_id[node];
    if (!valid_node(owner_decl) || trait_decl_i == INVALID)
        return;

    uint arg_count;
    uint first_arg_token;
    uint second_arg_token;
    uint arg_status = validate_bound_type_args(
        owner_decl,
        node,
        arg_count,
        first_arg_token,
        second_arg_token);
    predicate_bound_arg_count[node] = arg_count;
    predicate_bound_first_arg_token[node] = first_arg_token;
    predicate_bound_second_arg_token[node] = second_arg_token;
    if (arg_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = arg_status;
        return;
    }

    uint trait_param_count = trait_decl_generic_param_count(trait_decl_i);
    predicate_status[node] = trait_param_count != INVALID && arg_count == trait_param_count
        ? PREDICATE_STATUS_OK
        : PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
}
