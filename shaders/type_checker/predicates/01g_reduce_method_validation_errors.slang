// Reduce dense method/type validation rows to the first failing row for each
// compact trait-impl owner.

import atomics;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirPayload { uint a; uint b; uint c; uint d; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> predicate_method_validation_owner_node;
StructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_first_error_row;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_IMPL_TRAIT = 2u;
static const uint PREDICATE_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint hir) { return hir != INVALID && hir < active_hir_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_hir(row)) return;
    uint owner = predicate_method_validation_owner_node[row];
    if (!valid_hir(owner) || compact_hir_payload[owner].a != HIR_IMPL_TRAIT) return;
    uint status = predicate_method_validation_status[row];
    if (status == INVALID || status == PREDICATE_STATUS_OK) return;
    atomic_u32_min(predicate_method_validation_first_error_row, owner, row);
}
