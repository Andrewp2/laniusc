import hir_records;

// Validate compact parameter rows after method-level validation has published
// one stable row per dense method HIR id.

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
    uint parameter_row = linear_thread_id(dtid);
    if (!method_param_lookup_row_valid(parameter_row)) return;
    HirParam parameter = compact_params[parameter_row];
    uint impl_method = parameter.owner;
    uint owner = predicate_method_contract_owner_hir[impl_method];
    if (!trait_impl_owner_hir(owner) ||
        predicate_method_validation_status[impl_method] != PREDICATE_STATUS_OK)
        return;

    uint name_id = method_contract_name_id(impl_method);
    uint trait_hir = trait_decl_for_impl(owner);
    uint trait_method = valid_hir(trait_hir)
        ? first_method_contract_for_owner_name(trait_hir, name_id)
        : INVALID;
    if (!method_contract_lookup_row_valid(trait_method) ||
        method_unsupported_contract_status(trait_method) != PREDICATE_STATUS_OK ||
        method_param_count(trait_method) != method_param_count(impl_method) ||
        parameter.ordinal >= method_param_count(impl_method))
        return;

    uint trait_parameter = method_param_for_ordinal(trait_method, parameter.ordinal);
    if (!method_param_lookup_row_valid(trait_parameter)) return;
    uint impl_type = method_param_type(parameter_row);
    uint trait_type = method_param_type(trait_parameter);
    if (valid_hir(impl_type) && valid_hir(trait_type))
    {
        predicate_method_validation_owner_node[impl_type] = owner;
        predicate_method_validation_peer_node[impl_type] = trait_type;
        predicate_method_validation_status[impl_type] = PREDICATE_STATUS_OK;
        predicate_method_validation_detail_token[impl_type] =
            method_contract_diagnostic_token(impl_method);
    }

    if (!method_param_signature_definitely_mismatches(
            trait_method, impl_method, owner, parameter.ordinal))
        return;

    // Every mismatching parameter of one method publishes the same semantic
    // status and diagnostic token, so concurrent stores are deterministic.
    predicate_method_validation_owner_node[impl_method] = owner;
    predicate_method_validation_peer_node[impl_method] = trait_method;
    predicate_method_validation_status[impl_method] =
        PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH;
    predicate_method_validation_detail_token[impl_method] =
        method_contract_diagnostic_token(impl_method);
}
