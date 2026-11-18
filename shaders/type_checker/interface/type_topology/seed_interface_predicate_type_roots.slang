// Bound operands are separate checked roots. Their syntactic parent is the
// contract application, which has no runtime value-type representation.
import hir_records;
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> interface_predicate_flag;
StructuredBuffer<uint> interface_predicate_owner;
StructuredBuffer<uint> interface_predicate_argument_count;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row)
{
    atomic_u32_or(interface_status, 0u, 65536u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, 6u);
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    uint rows; uint stride;
    interface_predicate_flag.GetDimensions(rows, stride);
    if (row >= min(compact_predicate_count[0u], min(active, rows)) || interface_predicate_flag[row] != 1u) return;
    uint bound = compact_predicates[row].bound;
    uint owner = interface_predicate_owner[row];
    if (bound >= active || owner == INVALID ||
        ((owner & 0x80000000u) == 0u && owner >= gParams.decl_capacity)) { fail(row); return; }
    uint count = interface_predicate_argument_count[row];
    uint total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    HirRange range = compact_type_arg_ranges[bound];
    if (count == 0u) return;
    if (range.count != count || range.start > total || count > total - range.start)
    { fail(row); return; }
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        HirTypeArg argument = compact_type_args[range.start + ordinal];
        uint node = argument.value;
        if (argument.owner != bound || argument.ordinal != ordinal || node >= active ||
            (interface_type_parent[node] != bound && interface_type_parent[node] != INVALID))
        { fail(row); return; }
        uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, node, INVALID, owner);
        if (prior != INVALID && prior != owner) { fail(row); return; }
    }
}
