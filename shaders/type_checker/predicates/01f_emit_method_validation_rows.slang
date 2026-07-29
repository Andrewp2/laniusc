// Emit dense-HIR method and impl-owner validation rows from compact contracts.

#include "method_validation_common.slang"

RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_INVALID_TARGET = 5u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_IMPL_TARGET_DECL_KIND = 31u;
static const uint PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE = 14u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

void publish_validation(uint row, uint owner, uint peer, uint status, uint detail)
{
    if (!valid_hir(row)) return;
    predicate_method_validation_owner_node[row] = owner;
    predicate_method_validation_peer_node[row] = peer;
    predicate_method_validation_status[row] = status;
    predicate_method_validation_detail_token[row] = detail;
}

void publish_type_peer(uint impl_type, uint trait_type, uint owner, uint method)
{
    if (!valid_hir(impl_type) || !valid_hir(trait_type) || !valid_hir(owner)) return;
    publish_validation(
        impl_type,
        owner,
        trait_type,
        PREDICATE_STATUS_OK,
        method_contract_diagnostic_token(method));
}

void validate_impl_owner_method_counts(uint owner)
{
    uint owner_status = predicate_method_validation_status[owner];
    if (owner_status != INVALID && owner_status != PREDICATE_STATUS_OK) return;
    uint trait_hir = trait_decl_for_impl(owner);
    if (!valid_hir(trait_hir)) return;
    QueryRange trait_methods = method_contract_range_for_owner(trait_hir);
    QueryRange impl_methods = method_contract_range_for_owner(owner);
    if (!method_contract_range_matches_owner(trait_hir, trait_methods) ||
        !method_contract_range_matches_owner(owner, impl_methods)) return;
    uint trait_count = trait_methods.end - trait_methods.begin;
    uint impl_count = impl_methods.end - impl_methods.begin;
    if (trait_count <= impl_count) return;
    uint token = compact_hir_core[owner].token_start;
    publish_validation(
        owner,
        owner,
        trait_hir,
        PREDICATE_STATUS_MISSING_METHOD,
        valid_token(token) ? token : INVALID);
}

void validate_trait_impl_target(uint owner)
{
    uint target = compact_hir_payload[owner].c;
    if (!valid_hir(target)) return;
    uint token = compact_hir_core[owner].token_start;
    if (type_node_form(target) != HIR_TYPE_FORM_PATH)
    {
        publish_validation(
            owner,
            owner,
            INVALID,
            PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE,
            valid_token(token) ? token : INVALID);
        return;
    }

    uint path = path_id_by_owner_hir[target];
    if (path < gParams.n_hir_nodes && resolved_type_status[path] == 0u)
        return;
    uint tag;
    uint payload;
    if (type_node_ref(target, tag, payload) && tag == TYPE_REF_SCALAR)
        return;
    publish_validation(
        owner,
        owner,
        INVALID,
        PREDICATE_STATUS_INVALID_TARGET,
        valid_token(token) ? token : INVALID);
}

void validate_inherent_impl_owner(uint owner)
{
    uint target = compact_hir_payload[owner].c;
    if (!valid_hir(target)) return;
    uint path = path_id_by_owner_hir[target];
    uint decl_count = min(decl_count_out[0u], gParams.n_tokens);
    if (path >= gParams.n_hir_nodes || resolved_type_status[path] != 0u) return;
    uint decl = resolved_type_decl[path];
    uint target_hir = decl < decl_count ? decl_hir_node[decl] : INVALID;
    if (!trait_owner_hir(target_hir)) return;
    uint token = compact_hir_core[owner].token_start;
    publish_validation(
        owner,
        owner,
        target_hir,
        PREDICATE_STATUS_IMPL_TARGET_DECL_KIND,
        valid_token(token) ? token : INVALID);
}

void validate_trait_method(uint method, uint owner, uint name_id, uint detail)
{
    if (duplicate_method_contract_for_owner_name(owner, name_id))
    {
        uint first = first_method_contract_for_owner_name(owner, name_id);
        if (first != method)
        {
            publish_validation(
                method, owner, first, PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD, detail);
            return;
        }
    }
    publish_validation(
        method,
        owner,
        INVALID,
        method_unsupported_contract_status(method),
        detail);
}

void validate_trait_impl_method(uint method, uint owner, uint name_id, uint detail)
{
    uint trait_hir = trait_decl_for_impl(owner);
    uint trait_method = valid_hir(trait_hir)
        ? first_method_contract_for_owner_name(trait_hir, name_id)
        : INVALID;
    uint status = method_unsupported_contract_status(method);
    if (status != PREDICATE_STATUS_OK)
    {
        publish_validation(method, owner, trait_method, status, detail);
        return;
    }
    if (!valid_hir(trait_method))
    {
        publish_validation(method, owner, INVALID, PREDICATE_STATUS_EXTRA_IMPL_METHOD, detail);
        return;
    }
    uint trait_status = method_unsupported_contract_status(trait_method);
    if (trait_status != PREDICATE_STATUS_OK)
    {
        uint trait_detail = method_contract_diagnostic_token(trait_method);
        publish_validation(
            method,
            owner,
            trait_method,
            trait_status,
            valid_token(trait_detail) ? trait_detail : detail);
        return;
    }
    if (duplicate_method_contract_for_owner_name(owner, name_id))
    {
        uint first = first_method_contract_for_owner_name(owner, name_id);
        if (first != method)
        {
            publish_validation(
                method, owner, first, PREDICATE_STATUS_DUPLICATE_IMPL_METHOD, detail);
            return;
        }
    }
    if (method_contract_is_public(trait_method) != method_contract_is_public(method))
    {
        publish_validation(
            method,
            owner,
            trait_method,
            PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH,
            detail);
        return;
    }
    uint trait_params = method_param_count(trait_method);
    uint impl_params = method_param_count(method);
    if (trait_params > MAX_METHOD_SIGNATURE_PARAMS ||
        impl_params > MAX_METHOD_SIGNATURE_PARAMS ||
        trait_params != impl_params)
    {
        publish_validation(
            method, owner, trait_method, PREDICATE_STATUS_METHOD_ARITY_MISMATCH, detail);
        return;
    }
    publish_type_peer(method_return_type(method), method_return_type(trait_method), owner, method);
    if (method_return_signature_definitely_mismatches(trait_method, method, owner))
    {
        publish_validation(
            method, owner, trait_method, PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH, detail);
        return;
    }
    publish_validation(method, owner, trait_method, PREDICATE_STATUS_OK, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_thread_id(dtid);
    if (!valid_hir(hir)) return;
    if (inherent_impl_owner_hir(hir)) validate_inherent_impl_owner(hir);
    if (trait_impl_owner_hir(hir))
    {
        validate_trait_impl_target(hir);
        validate_impl_owner_method_counts(hir);
    }
    if (!method_contract_lookup_row_valid(hir)) return;

    uint owner = predicate_method_contract_owner_hir[hir];
    uint name_id = method_contract_name_id(hir);
    uint name_token = method_contract_name_token(hir);
    uint detail = method_contract_diagnostic_token(hir);
    if (!valid_token(name_token) || name_id == INVALID)
    {
        publish_validation(
            hir, owner, INVALID, PREDICATE_STATUS_METHOD_ARITY_MISMATCH, detail);
        return;
    }
    if (trait_owner_hir(owner)) validate_trait_method(hir, owner, name_id, detail);
    else if (trait_impl_owner_hir(owner))
        validate_trait_impl_method(hir, owner, name_id, detail);
    else if (inherent_impl_owner_hir(owner))
        publish_validation(
            hir, owner, INVALID, method_unsupported_contract_status(hir), detail);
}
