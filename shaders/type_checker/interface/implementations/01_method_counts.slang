// Size each accepted implementation's deterministic method/member segment.
// Atomic sums size the segment; member positions never depend on lane order.
import hir_records;
import atomics;
import type_checker.interface.method_parameters;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_validation_required_symbol;
StructuredBuffer<uint> interface_implementation_index_by_hir;
StructuredBuffer<uint> interface_implementation_total;
RWStructuredBuffer<uint> interface_implementation_member_count;
RWStructuredBuffer<uint> interface_generic_scope_owner_by_hir;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 131072u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (row >= min(compact_method_count[0u], active)) return;
    HirMethodCore method = compact_method_cores[row];
    uint map_rows; uint stride;
    interface_implementation_index_by_hir.GetDimensions(map_rows, stride);
    if (method.impl_node >= min(active, map_rows)) return;
    uint link = interface_implementation_index_by_hir[method.impl_node];
    if (link == 0u) return;
    bool inherent = compact_hir_semantic_facts[method.impl_node].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT;
    HirMethodSignature signature = compact_method_signatures[row];
    if (inherent && !interface_public_inherent_method(signature)) return;
    uint implementation = link - 1u;
    uint rows;
    interface_implementation_member_count.GetDimensions(rows, stride);
    if (implementation >= min(interface_implementation_total[0u], rows) ||
        method.node >= active || method.owner != method.impl_node ||
        predicate_status[method.impl_node] != 0u ||
        (!inherent && (predicate_method_validation_status[method.node] != 0u ||
        predicate_method_validation_required_symbol[method.node] == INVALID)))
    { fail(row, 32u); return; }

    if (!inherent && (((signature.metadata >> 16u) & 3u) != 0u ||
        compact_generic_param_ranges[method.node].count != 0u))
    { fail(row, 33u); return; }
    HirRange parameters = compact_param_ranges[method.node];
    uint total = min(compact_param_count[0u], active);
    bool implicit_self = signature.receiver_mode == 1u || signature.receiver_mode == 2u;
    if (signature.receiver_mode > 3u || (signature.metadata & 0xffffu) > 1u ||
        parameters.count > 65535u || (implicit_self && parameters.count == 0u) ||
        (parameters.count != 0u &&
         (parameters.start > total || parameters.count > total - parameters.start)))
    { fail(row, 34u); return; }
    uint footprint = 1u + parameters.count - uint(implicit_self) + compact_generic_param_ranges[method.node].count;
    interface_generic_scope_owner_by_hir[method.node] = 0x80000000u | implementation;
    atomic_u32_add(interface_implementation_member_count, implementation, footprint);
}
