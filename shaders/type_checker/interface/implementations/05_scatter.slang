// Persist implementation identity and independently checked canonical roots.
import hir_records;
import atomics;
import semantic_interface_layout;
import type_checker.predicates.trait_reference;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> interface_implementation_flag;
StructuredBuffer<uint> interface_implementation_prefix;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_implementation_argument_count;
StructuredBuffer<uint> interface_implementation_argument_prefix;
StructuredBuffer<uint> interface_implementation_argument_total;
StructuredBuffer<uint> interface_implementation_member_count;
StructuredBuffer<uint> interface_implementation_member_prefix;
StructuredBuffer<uint> interface_implementation_member_total;
StructuredBuffer<uint> interface_implementation_method_count;
StructuredBuffer<uint> interface_implementation_method_prefix;
StructuredBuffer<uint> interface_implementation_method_total;
StructuredBuffer<uint> interface_declaration_member_total;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> interface_type_count;
RWStructuredBuffer<uint> interface_implementation_words;
RWStructuredBuffer<uint> interface_implementation_written;
RWStructuredBuffer<uint> interface_implementation_arguments;
RWStructuredBuffer<uint> interface_implementation_argument_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 131072u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows; uint stride;
    interface_implementation_flag.GetDimensions(rows, stride);
    if (row >= min(compact_hir_count[0u], rows) || interface_implementation_flag[row] != 1u) return;
    uint index = interface_implementation_prefix[row];
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    bool inherent = compact_hir_semantic_facts[row].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT;
    uint subject_hir = compact_hir_semantic_facts[row].method_impl_receiver_type;
    uint bound = compact_hir_payload[row].b;
    if (index >= min(interface_implementation_total[0u], rows) || subject_hir >= active || (!inherent && bound >= active))
    { fail(row, 12u); return; }
    uint file_rows; uint file_stride;
    module_id_by_file_id.GetDimensions(file_rows, file_stride);
    uint file = compact_hir_links[row].file_id;
    uint module = file < file_rows ? module_id_by_file_id[file] : INVALID;
    uint modules = module_count_out[0u];
    if (module == INVALID && file == 0u && modules == 0u) module = 0u;
    if (module >= max(modules, 1u)) { fail(row, 13u); return; }
    uint3 identity = uint3(INVALID, INVALID, INVALID);
    if (!inherent)
    {
        uint reference = predicate_bound_reference[row];
        identity = uint3(gParams.library_id, gParams.unit_id, INVALID);
        if (trait_reference_is_dependency(reference)) identity = trait_reference_identity(reference).yzw;
        else if (reference < gParams.decl_capacity) identity.z = public_decl_index_by_local[reference];
        if (any(identity == INVALID)) { fail(row, 14u); return; }
    }
    uint subject = interface_type_index_by_hir[subject_hir];
    if (subject >= interface_type_count[0u]) { fail(row, 14u); return; }
    uint first = interface_implementation_argument_prefix[row];
    uint count = interface_implementation_argument_count[row];
    uint argument_capacity; uint argument_stride;
    interface_implementation_arguments.GetDimensions(argument_capacity, argument_stride);
    uint total = interface_implementation_argument_total[0u];
    HirRange arguments; arguments.start = 0u; arguments.count = 0u;
    if (!inherent) arguments = compact_type_arg_ranges[bound];
    uint source_total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    if (total > argument_capacity || first > total || count > total - first ||
        arguments.count != count || (count != 0u && (arguments.start > source_total || count > source_total - arguments.start)))
    { fail(row, 15u); return; }
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        HirTypeArg argument = compact_type_args[arguments.start + ordinal];
        uint root = argument.value < active ? interface_type_index_by_hir[argument.value] : INVALID;
        if (argument.owner != bound || argument.ordinal != ordinal || root >= interface_type_count[0u])
        { fail(row, 16u); return; }
        interface_implementation_arguments[first + ordinal] = root;
        if (atomic_u32_compare_exchange(interface_implementation_argument_written, first + ordinal, 0u, 1u) != 0u)
        { fail(row, 17u); return; }
    }
    uint members = interface_implementation_member_count[index];
    uint first_member = interface_implementation_member_prefix[index];
    uint methods = interface_implementation_method_count[index];
    uint first_method = interface_implementation_method_prefix[index];
    if (first_member > interface_implementation_member_total[0u] || members > interface_implementation_member_total[0u] - first_member ||
        first_method > interface_implementation_method_total[0u] || methods > interface_implementation_method_total[0u] - first_method)
    { fail(row, 18u); return; }
    uint base = index * SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS;
    interface_implementation_words[base] = module;
    interface_implementation_words[base + 1u] = 1u;
    interface_implementation_words[base + 2u] = identity.x;
    interface_implementation_words[base + 3u] = identity.y;
    interface_implementation_words[base + 4u] = identity.z;
    interface_implementation_words[base + 5u] = subject;
    interface_implementation_words[base + 6u] = first;
    interface_implementation_words[base + 7u] = count;
    interface_implementation_words[base + 8u] = interface_declaration_member_total[0u] + first_member;
    interface_implementation_words[base + 9u] = members;
    interface_implementation_words[base + 10u] = INVALID;
    interface_implementation_words[base + 11u] = 0u;
    interface_implementation_words[base + 12u] = first_method;
    interface_implementation_words[base + 13u] = methods;
    interface_implementation_words[base + 14u] = inherent ? SEMANTIC_INTERFACE_IMPLEMENTATION_INHERENT : SEMANTIC_INTERFACE_IMPLEMENTATION_TRAIT;
    if (atomic_u32_compare_exchange(interface_implementation_written, index, 0u, 1u) != 0u)
        fail(row, 19u);
}
