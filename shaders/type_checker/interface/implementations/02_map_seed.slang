// Map accepted implementation owners and preserve subject/operand roots.
import hir_records;
import atomics;
import semantic_interface_layout;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> predicate_method_contract_owner_count;
StructuredBuffer<uint> interface_implementation_flag;
StructuredBuffer<uint> interface_implementation_prefix;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_implementation_argument_count;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_implementation_index_by_hir;
RWStructuredBuffer<uint> interface_implementation_method_count;
RWStructuredBuffer<uint> interface_implementation_member_count;
RWStructuredBuffer<uint> interface_generic_scope_owner_by_hir;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 131072u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}
bool seed(uint node, uint parent, uint owner, bool constant_argument, uint row)
{
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (node >= active) { fail(row, 10u); return false; }
    uint tag = semantic_type_ref_tag_by_hir[node];
    bool checked_constant = constant_argument &&
        (tag == 0x80000001u || tag == 0x80000002u || tag == 0x80000003u);
    if ((compact_hir_core[node].kind != 5u && !checked_constant) ||
        (interface_type_parent[node] != parent && interface_type_parent[node] != INVALID))
    { fail(row, 10u); return false; }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, node, INVALID, owner);
    if (prior != INVALID && prior != owner) { fail(row, 11u); return false; }
    return true;
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows; uint stride;
    interface_implementation_flag.GetDimensions(rows, stride);
    if (row >= min(compact_hir_count[0u], rows) || interface_implementation_flag[row] != 1u) return;
    uint subject = compact_hir_semantic_facts[row].method_impl_receiver_type;
    bool inherent = compact_hir_semantic_facts[row].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT;
    uint bound = compact_hir_payload[row].b;
    uint index = interface_implementation_prefix[row];
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (index >= interface_implementation_total[0u] || index >= rows ||
        row >= min(active, rows) || (!inherent && bound >= active))
    { fail(row, 8u); return; }
    interface_implementation_index_by_hir[row] = index + 1u;
    interface_implementation_method_count[index] = inherent ? 0u : predicate_method_contract_owner_count[row];
    interface_implementation_member_count[index] = compact_generic_param_ranges[row].count;
    uint owner = SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER | index;
    interface_generic_scope_owner_by_hir[row] = owner;
    if (!seed(subject, INVALID, owner, false, row)) return;
    if (inherent) return;
    uint count = interface_implementation_argument_count[row];
    HirRange range = compact_type_arg_ranges[bound];
    uint total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    if (range.count != count || (count != 0u && (range.start > total || count > total - range.start)))
    { fail(row, 9u); return; }
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        HirTypeArg argument = compact_type_args[range.start + ordinal];
        if (argument.owner != bound || argument.ordinal != ordinal)
        { fail(row, 9u); return; }
        if (!seed(argument.value, bound, owner, true, row)) return;
    }
}
