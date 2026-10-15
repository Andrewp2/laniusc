import type_checker.dependencies.constant_view;
#include "materialize_application_inputs.slang"
#define MATERIALIZE_ROOT_CANDIDATES 1
#include "materialize_application.slang"
#include "expand_materialized_instance.slang"
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = dtid.x + dtid.y * 16776960u;
    if (root >= gParams.n_tokens || type_instance_kind[root] != 1u) return;
    uint declaration = type_instance_decl_token[root];
    if (declaration < gParams.n_tokens && type_instance_arg_count[root] !=
        (type_decl_generic_param_count_by_owner_token[declaration] +
         type_decl_const_param_count_by_owner_token[declaration])) return;
    uint hash;
    if (!scoped_type_ref_hash<MutableCheckedTypeGraph>(3u, root, INVALID,
        mutable_type_capacity(), gParams.n_tokens, hash)) return;
    uint created[DEPTH_LIMIT]; uint created_count = 0u;
    uint failure;
    if (!expand_materialized_instance<MutableCheckedTypeGraph>(root, created, created_count, failure))
        record_min_token_error(status, root, 6u, 0x474e0000u | failure);
}
