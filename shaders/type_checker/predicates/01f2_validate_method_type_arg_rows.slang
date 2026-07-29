// Validate arbitrary-width top-level generic arguments through compact type
// argument rows and dense type-peer relations.

#include "method_validation_common.slang"

RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_type_arg_count()) return;
    HirTypeArg impl_argument = compact_type_args[row];
    uint impl_type = impl_argument.owner;
    if (!valid_hir(impl_type) || !valid_hir(impl_argument.value))
        return;

    uint impl_root = compact_type_root_owner[impl_argument.value];
    if (!valid_hir(impl_root)) impl_root = impl_type;
    if (predicate_method_validation_status[impl_root] != PREDICATE_STATUS_OK)
        return;
    uint trait_root = predicate_method_validation_peer_node[impl_root];
    uint impl_owner = predicate_method_validation_owner_node[impl_root];
    if (!valid_hir(trait_root) || !valid_hir(impl_owner) ||
        impl_argument.value < impl_root)
        return;
    uint trait_argument = trait_root + (impl_argument.value - impl_root);
    if (!valid_hir(trait_argument) ||
        trait_argument >= compact_hir_links[trait_root].subtree_end)
        return;

    predicate_method_validation_owner_node[impl_argument.value] = impl_owner;
    predicate_method_validation_peer_node[impl_argument.value] = trait_argument;
    predicate_method_validation_status[impl_argument.value] = PREDICATE_STATUS_OK;
    predicate_method_validation_detail_token[impl_argument.value] =
        predicate_method_validation_detail_token[impl_root];

    if (!flat_type_forms_definitely_mismatch(
            trait_argument, impl_argument.value, impl_owner))
        return;

    predicate_method_validation_status[impl_argument.value] =
        PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH;
}
