// Method-contract predicate collection.
//
// This module intentionally owns only the records used to classify trait and
// impl method contracts. Keeping it separate from bound-path and impl-header
// resolution prevents those unrelated descriptor tables from becoming part of
// this pass's shader ABI.

import generated_parse_production_ids;
import fixed.key;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;

RWStructuredBuffer<uint> predicate_owner_node;
RWStructuredBuffer<uint> predicate_bound_token;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_status;

StructuredBuffer<uint> predicate_method_contract_owner_node;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> predicate_method_contract_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_TRAIT = 10u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool trait_method_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_TRAIT_METHOD || kind == PROD_TRAIT_METHOD_PUB;
}

bool impl_method_node(uint node)
{
    return valid_node(node) && node_kind[node] == PROD_IMPL_FN;
}

uint method_contract_name_token(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;
    uint token = predicate_method_contract_name_token[method_node];
    return valid_token(token) ? token : INVALID;
}

uint method_contract_name_id(uint method_node)
{
    if (!valid_node(method_node))
        return INVALID;
    return predicate_method_contract_name_id[method_node];
}

bool method_contract_lookup_row_valid(uint method_node)
{
    if (!valid_node(method_node))
        return false;
    return valid_node(predicate_method_contract_owner_node[method_node]) &&
           method_contract_name_id(method_node) != INVALID;
}

public struct MethodContractLookupKey
{
    uint owner_node;
    uint name_id;
}

public struct MethodContractFixedKey : IFixedU32RowKey<MethodContractLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint method_node = row < active_hir_node_count()
            ? predicate_method_contract_key_order[row]
            : INVALID;
        if (!method_contract_lookup_row_valid(method_node))
            return 0u;

        if (lane == 0u)
            return fixed_key_encode_nullable_u32(
                predicate_method_contract_owner_node[method_node],
                INVALID);
        return fixed_key_encode_nullable_u32(method_contract_name_id(method_node), INVALID);
    }

    public static uint key_lane(MethodContractLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.owner_node, INVALID);
        return fixed_key_encode_nullable_u32(key.name_id, INVALID);
    }
}

public struct MethodContractKeyCompare : IRowQueryCompare<MethodContractLookupKey>
{
    public static int compare(uint row, MethodContractLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodContractLookupKey, MethodContractFixedKey>(
            row,
            key,
            2u);
    }
}

QueryRange method_contract_range_for_owner_name(uint owner_node, uint name_id)
{
    MethodContractLookupKey key;
    key.owner_node = owner_node;
    key.name_id = name_id;
    return equal_range_query<MethodContractLookupKey, MethodContractKeyCompare>(
        active_hir_node_count(),
        key);
}

bool method_contract_node_matches_owner_name(uint method_node, uint owner_node, uint name_id)
{
    return method_contract_lookup_row_valid(method_node) &&
           predicate_method_contract_owner_node[method_node] == owner_node &&
           method_contract_name_id(method_node) == name_id;
}

bool method_contract_order_row_matches_owner_name(uint row, uint owner_node, uint name_id)
{
    uint active = active_hir_node_count();
    if (row >= active)
        return false;

    uint method_node = predicate_method_contract_key_order[row];
    return method_contract_node_matches_owner_name(method_node, owner_node, name_id);
}

bool method_contract_range_matches_owner_name(
    uint owner_node,
    uint name_id,
    QueryRange range)
{
    if (!valid_node(owner_node) || name_id == INVALID)
        return false;
    if (range.begin >= range.end)
        return true;
    if (range.end > active_hir_node_count())
        return false;

    return method_contract_order_row_matches_owner_name(range.begin, owner_node, name_id) &&
           method_contract_order_row_matches_owner_name(range.end - 1u, owner_node, name_id);
}

uint trait_owner_node_for_method(uint method_node)
{
    uint owner = valid_node(method_node)
        ? predicate_method_contract_owner_node[method_node]
        : INVALID;
    return valid_node(owner) && hir_item_kind[owner] == HIR_ITEM_KIND_TRAIT
        ? owner
        : INVALID;
}

bool duplicate_trait_method_node(uint method_node)
{
    uint trait_node = trait_owner_node_for_method(method_node);
    uint name_id = method_contract_name_id(method_node);
    if (!valid_node(trait_node) || name_id == INVALID)
        return false;

    QueryRange range = method_contract_range_for_owner_name(trait_node, name_id);
    if (range.end <= range.begin + 1u)
        return false;

    uint first_method = predicate_method_contract_key_order[range.begin];
    return method_contract_node_matches_owner_name(first_method, trait_node, name_id) &&
           first_method != method_node;
}

uint method_unsupported_contract_status(uint method_node)
{
    if (!valid_node(method_node))
        return PREDICATE_STATUS_OK;

    uint record_status = predicate_method_contract_status[method_node];
    return record_status != INVALID ? record_status : PREDICATE_STATUS_OK;
}

void validate_trait_method_contract_node(uint node)
{
    if (!trait_method_node(node))
        return;

    uint method_status = method_unsupported_contract_status(node);
    if (method_status == PREDICATE_STATUS_OK && duplicate_trait_method_node(node))
        method_status = PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD;
    if (method_status == PREDICATE_STATUS_OK)
        return;

    uint name_token = method_contract_name_token(node);
    uint diagnostic_token = valid_token(name_token) ? name_token : hir_token_pos[node];
    predicate_owner_node[node] = node;
    predicate_bound_token[node] = diagnostic_token;
    predicate_bound_first_arg_token[node] = diagnostic_token;
    predicate_status[node] = method_status;
}

void validate_impl_method_contract_record_node(uint node)
{
    if (!impl_method_node(node))
        return;

    uint name_token = method_contract_name_token(node);
    uint diagnostic_token = valid_token(name_token) ? name_token : hir_token_pos[node];
    uint owner_node = predicate_method_contract_owner_node[node];
    bool inherent_impl_method =
        valid_node(owner_node) && node_kind[owner_node] == PROD_IMPL_INHERENT;

    uint method_status = method_unsupported_contract_status(node);
    if (inherent_impl_method && method_status != PREDICATE_STATUS_OK)
    {
        predicate_owner_node[node] = node;
        predicate_bound_token[node] = diagnostic_token;
        predicate_bound_first_arg_token[node] = diagnostic_token;
        predicate_status[node] = method_status;
        return;
    }

    if (method_contract_lookup_row_valid(node))
        return;

    predicate_owner_node[node] = node;
    predicate_bound_token[node] = diagnostic_token;
    predicate_bound_first_arg_token[node] = diagnostic_token;
    if (inherent_impl_method)
        return;
    predicate_status[node] = PREDICATE_STATUS_METHOD_ARITY_MISMATCH;
}
