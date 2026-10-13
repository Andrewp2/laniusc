import type_checker.dependencies.constant_view;
#define MATERIALIZE_NORMALIZE_ALIASES 1
#include "../type/instances/materialize_application_inputs.slang"
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint2> imported_type_alias_target;
#include "../type/instances/materialize_application.slang"

// Source rows and declaration targets are immutable for this dispatch. Each
// lane owns its generated nodes and publishes one complete reference. The next
// dispatch applies this relation to annotations and argument/element edges.
RWStructuredBuffer<uint2> type_alias_normalized_ref;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = dtid.x + dtid.y * 16776960u;
    if (root >= gParams.n_tokens) return;
    type_alias_normalized_ref[root] = uint2(0u, INVALID);
    if (type_instance_kind[root] == 0u || type_instance_state[root] != 1u) return;
    if (type_instance_kind[root] == 1u && type_instance_decl_token[root] == INVALID &&
        external_type_library_id[root] == INVALID) return;
    uint created[DEPTH_LIMIT]; uint count = 0u;
    uint2 result; uint failure;
    if (!materialize<MutableCheckedTypeGraph>(uint3(3u, root, INVALID), created, count,
        result, failure))
    {
        record_min_token_error(status, root, 6u, 0x414c0000u | failure);
        return;
    }
    type_alias_normalized_ref[root] = result;
}
