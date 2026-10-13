// Serialize only accepted contract facts. Subject leaves retain exact member
// ownership; trait references are translated into persistent declaration ids.
import hir_records;
import atomics;
import semantic_interface_layout;
import type_checker.predicates.trait_reference;
import type_checker.interface.method_parameters;
import type_checker.interface.scalar_leaves;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<uint> interface_implementation_total;
RWStructuredBuffer<uint> interface_implementation_words;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> interface_predicate_flag;
StructuredBuffer<uint> interface_predicate_owner;
StructuredBuffer<uint> interface_predicate_scope;
StructuredBuffer<uint> interface_predicate_subject_row;
StructuredBuffer<uint> interface_predicate_argument_count;
StructuredBuffer<uint> interface_predicate_prefix;
StructuredBuffer<uint> interface_predicate_total;
StructuredBuffer<uint> interface_predicate_argument_prefix;
StructuredBuffer<uint> interface_predicate_argument_total;
StructuredBuffer<uint> interface_member_index_by_generic_row;
StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_member_words;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_signature_type_total;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_predicate_words;
RWStructuredBuffer<uint> interface_predicate_written;
RWStructuredBuffer<uint> interface_predicate_arguments;
RWStructuredBuffer<uint> interface_predicate_argument_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 65536u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
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
    uint destination = interface_predicate_prefix[row];
    uint count = interface_predicate_argument_count[row];
    uint first = interface_predicate_argument_prefix[row];
    if (destination >= interface_predicate_total[0u] || destination >= gParams.hir_capacity ||
        interface_predicate_argument_total[0u] > gParams.hir_capacity ||
        first > interface_predicate_argument_total[0u] || count > interface_predicate_argument_total[0u] - first)
    { fail(row, 7u); return; }
    uint parameter = interface_predicate_subject_row[row];
    uint member = parameter < gParams.token_capacity ? interface_member_index_by_generic_row[parameter] : INVALID;
    uint owner = interface_predicate_owner[row];
    uint scope = interface_predicate_scope[row];
    if (member >= interface_member_total[0u]) { fail(row, 8u); return; }
    uint member_base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint source_owner = compact_predicates[row].owner;
    uint member_scope = interface_member_words[member_base + 9u];
    bool allowed_scope = member_scope == scope;
    if (!allowed_scope && (scope & 0xc0000000u) == 0x80000000u)
    {
        uint method = interface_method_for_function(source_owner,
            min(compact_method_count[0u], active), compact_method_cores);
        if (method != INVALID)
        {
            HirMethodCore method_core = compact_method_cores[method];
            allowed_scope = (owner & 0x80000000u) != 0u
                ? method_core.impl_node < active && member_scope == (0xc0000000u | method_core.impl_node)
                : member_scope == 0u && method_core.owner < active;
        }
    }
    if (!allowed_scope || interface_member_words[member_base] != owner ||
        interface_member_words[member_base + 1u] != 2u)
    { fail(row, 9u); return; }
    uint bound = compact_predicates[row].bound;
    uint reference = bound < active ? predicate_bound_reference[bound] : INVALID;
    uint3 identity = uint3(gParams.library_id, gParams.unit_id, INVALID);
    if (trait_reference_is_dependency(reference))
    {
        uint4 resolved = trait_reference_identity(reference);
        identity = resolved.yzw;
    }
    else if (reference < gParams.decl_capacity)
        identity.z = public_decl_index_by_local[reference];
    if (any(identity == INVALID)) { fail(row, 10u); return; }
    uint subject = interface_type_count[0u] + INTERFACE_SCALAR_LEAF_COUNT + interface_signature_type_total[0u] + destination;
    uint type_base = subject * 9u;
    for (uint word = 0u; word < 9u; word++) interface_types[type_base + word] = 0u;
    interface_types[type_base] = 2u;
    interface_types[type_base + 1u] = member;
    uint base = destination * SEMANTIC_INTERFACE_PREDICATE_WORDS;
    interface_predicate_words[base] = owner;
    interface_predicate_words[base + 1u] = scope;
    interface_predicate_words[base + 2u] = subject;
    interface_predicate_words[base + 3u] = identity.x;
    interface_predicate_words[base + 4u] = identity.y;
    interface_predicate_words[base + 5u] = identity.z;
    interface_predicate_words[base + 6u] = first;
    interface_predicate_words[base + 7u] = count;
    HirRange range = compact_type_arg_ranges[bound];
    uint total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    if (count != 0u && (range.count != count || range.start > total || count > total - range.start))
    { fail(row, 11u); return; }
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint node = compact_type_args[range.start + ordinal].value;
        uint root = node < active ? interface_type_index_by_hir[node] : INVALID;
        if (root >= interface_type_count[0u]) { fail(row, 12u); return; }
        interface_predicate_arguments[first + ordinal] = root;
        uint prior = atomic_u32_compare_exchange(interface_predicate_argument_written, first + ordinal, 0u, 1u);
        if (prior != 0u) { fail(row, 13u); return; }
    }
    if ((owner & 0x80000000u) != 0u && (scope & 0xc0000000u) == 0xc0000000u)
    {
        uint implementation = owner & 0x7fffffffu;
        if (implementation >= interface_implementation_total[0u]) { fail(row, 16u); return; }
        uint implementation_base = implementation * SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS;
        uint implementation_kind = interface_implementation_words[implementation_base + 14u];
        if (implementation_kind != SEMANTIC_INTERFACE_IMPLEMENTATION_INHERENT &&
            implementation_kind != SEMANTIC_INTERFACE_IMPLEMENTATION_TRAIT)
        { fail(row, 16u); return; }
        atomic_u32_min(interface_implementation_words, implementation_base + 10u, destination);
        atomic_u32_add(interface_implementation_words, implementation_base + 11u, 1u);
    }
    uint prior = atomic_u32_compare_exchange(interface_predicate_written, destination, 0u, 1u);
    if (prior != 0u) fail(row, 14u);
}
