// Seed public function parameter type roots from compact parameter rows.

import hir_records;
import atomics;
import type_checker.interface.method_parameters;
struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 d) { return d.x + d.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && compact_hir_core[node].kind == HIR_TYPE; }
void seed(uint type_node_id, uint owner, uint detail)
{
    if (!type_node(type_node_id) || interface_type_parent[type_node_id] != INVALID)
    {
        atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, detail); return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, type_node_id, INVALID, owner);
    if (prior != INVALID && prior != owner)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, detail); }
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_param_count[0u], gParams.hir_capacity)) return;
    HirParam param = compact_params[row];
    uint owner = param.owner < active_hir_count() ? public_decl_index_by_hir[param.owner] : INVALID;
    if (owner == INVALID)
    {
        uint method = interface_method_for_function(param.owner,
            min(compact_method_count[0u], gParams.hir_capacity), compact_method_cores);
        if (method == INVALID) return;
        HirMethodSignature signature = compact_method_signatures[method];
        if (interface_method_parameter_ordinal(signature, param.ordinal) == INVALID) return;
        owner = interface_trait_method_owner(compact_method_cores[method], active_hir_count(),
            compact_hir_core, compact_hir_payload, public_decl_index_by_hir);
        // The preceding declaration-seeding pass has already attached this
        // public method's receiver type to its exported owner declaration.
        if (owner == INVALID && interface_public_inherent_method(signature))
        {
            uint receiver = signature.impl_receiver_type;
            owner = receiver < active_hir_count()
                ? interface_type_seed_owner[receiver] : INVALID;
        }
    }
    if (owner < gParams.decl_capacity) seed(param.type_node, owner, row);
}
