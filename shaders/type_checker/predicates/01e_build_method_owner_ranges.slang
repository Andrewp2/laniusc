// Build owner-indexed ranges over sorted trait/impl method contract records.
//
// Scheduling contract:
// - Dispatch after method contract rows have been sorted by
//   (owner node, method name, method node).
// - Each owner gets a compact range into predicate_method_contract_key_order.
// - Consumers can validate trait/impl method sets from records instead of
//   scanning HIR subtrees.

import fixed.key;
import gpu_index;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_key_order;

RWStructuredBuffer<uint> predicate_method_contract_owner_range_first;
RWStructuredBuffer<uint> predicate_method_contract_owner_range_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_method_contract(uint node)
{
    return valid_node(node) &&
           valid_node(predicate_method_contract_owner_hir[node]) &&
           predicate_method_contract_name_id[node] != INVALID;
}

uint method_contract_owner_for_order_row(uint row)
{
    if (row >= active_hir_node_count())
        return INVALID;
    uint node = predicate_method_contract_key_order[row];
    return valid_method_contract(node) ? predicate_method_contract_owner_hir[node] : INVALID;
}

public struct MethodOwnerLookupKey
{
    uint owner_node;
}

public struct MethodOwnerRangeCompare : IRowQueryCompare<MethodOwnerLookupKey>
{
    public static int compare(uint row, MethodOwnerLookupKey key)
    {
        uint row_key = fixed_key_encode_nullable_u32(
            method_contract_owner_for_order_row(row),
            INVALID);
        uint lookup_key = fixed_key_encode_nullable_u32(key.owner_node, INVALID);
        if (row_key < lookup_key)
            return -1;
        if (row_key > lookup_key)
            return 1;
        return 0;
    }
}

QueryRange method_contract_owner_range(uint owner_node)
{
    MethodOwnerLookupKey key;
    key.owner_node = owner_node;
    return equal_range_query<MethodOwnerLookupKey, MethodOwnerRangeCompare>(
        active_hir_node_count(),
        key);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint active = active_hir_node_count();
    if (row >= active)
        return;

    uint method_node = predicate_method_contract_key_order[row];
    if (!valid_method_contract(method_node))
        return;

    uint owner = predicate_method_contract_owner_hir[method_node];
    uint previous_owner = row == 0u
        ? INVALID
        : method_contract_owner_for_order_row(row - 1u);
    if (previous_owner == owner)
        return;

    QueryRange range = method_contract_owner_range(owner);
    predicate_method_contract_owner_range_first[owner] = range.begin;
    predicate_method_contract_owner_range_count[owner] = range.end - range.begin;
}
