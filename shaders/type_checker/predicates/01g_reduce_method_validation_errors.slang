// Reduce per-method validation rows to the first failing row for each impl owner.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> predicate_method_validation_owner_node;
StructuredBuffer<uint> predicate_method_validation_status;

RWStructuredBuffer<uint> predicate_method_validation_first_error_row;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PREDICATE_STATUS_OK = 0u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_node(row))
        return;

    uint owner = predicate_method_validation_owner_node[row];
    if (!valid_node(owner) || node_kind[owner] != PROD_IMPL_TRAIT)
        return;

    uint status = predicate_method_validation_status[row];
    if (status == INVALID || status == PREDICATE_STATUS_OK)
        return;

    atomic_u32_min(predicate_method_validation_first_error_row, owner, row);
}
