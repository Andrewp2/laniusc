// Export accepted lexical implementation owners in compact HIR order.
// Inherent visibility comes from public methods, independently of pub impl.
import hir_records;
import atomics;
import type_checker.predicates.trait_reference;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_contract_owner_count;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> decl_visibility;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
StructuredBuffer<uint> semantic_type_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> decl_id_by_name_token;
RWStructuredBuffer<uint> interface_implementation_flag;
RWStructuredBuffer<uint> interface_implementation_argument_count;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
void fail(uint row, uint detail)
{
    atomic_u32_or(interface_status, 0u, 131072u);
    atomic_u32_min(interface_status, 1u, row);
    atomic_u32_min(interface_status, 2u, detail);
}
// A HIR type whose checked type is a local nominal with no public declaration.
// The interface names local nominals by public index (type_topology
// 12_type_records), so it cannot spell this one. A hidden declaration
// (public_decls/02_hidden) has an index, but importers cannot name it, so
// its impls stay private as well.
bool private_nominal(uint node)
{
    if (semantic_type_ref_tag_by_hir[node] != 3u) return false;
    uint instance = semantic_type_ref_payload_by_hir[node];
    uint rows; uint stride;
    type_instance_kind.GetDimensions(rows, stride);
    if (instance >= rows || type_instance_kind[instance] != 1u) return false;
    uint declaration = type_instance_decl_token[instance];
    if (declaration >= gParams.token_capacity) return false;
    uint source = decl_id_by_name_token[declaration];
    return source >= gParams.decl_capacity || public_decl_index_by_local[source] == INVALID ||
        decl_visibility[source] != 1u;
}
// Whether the HIR subtree at `root` writes a private nominal type.
bool names_private_type(uint root, uint active)
{
    if (root >= active) return false;
    uint end = min(compact_hir_links[root].subtree_end, active);
    bool found = false;
    for (uint node = root; node < end; node++)
        found = found || (compact_hir_core[node].kind == 5u && private_nominal(node));
    return found;
}
// Whether the impl head (subject, trait path and trait arguments) names a type
// the interface cannot export. Such an impl is usable only where the type is
// visible, so it stays out of the interface; the program catalog admits it
// from the checked unit's contracts as a private implementation.
bool head_names_private_type(uint subject, uint bound, uint active)
{
    if (names_private_type(subject, active)) return true;
    if (bound >= active) return false;
    if (names_private_type(bound, active)) return true;
    HirRange range = compact_type_arg_ranges[bound];
    uint total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    if (range.count > 32u || range.start > total || range.count > total - range.start) return false;
    bool found = false;
    for (uint ordinal = 0u; ordinal < range.count; ordinal++)
        found = found || names_private_type(compact_type_args[range.start + ordinal].value, active);
    return found;
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    uint rows; uint stride;
    interface_implementation_flag.GetDimensions(rows, stride);
    if (row >= min(active, rows)) return;
    uint marked = interface_implementation_flag[row];
    interface_implementation_flag[row] = 0u;
    interface_implementation_argument_count[row] = 0u;
    if (compact_hir_core[row].kind != 35u) return;
    uint owner = row;
    uint subject = compact_hir_semantic_facts[owner].method_impl_receiver_type;
    if (compact_hir_semantic_facts[owner].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT)
    {
        if (marked == 0u) return;
        if (predicate_status[owner] != 0u || subject >= active || compact_hir_core[subject].kind != 5u)
        { fail(row, 3u); return; }
        if (names_private_type(subject, active)) return;
        interface_implementation_flag[row] = 1u;
        return;
    }
    if (compact_hir_semantic_facts[owner].semantic_kind != HIR_SEMANTIC_IMPL_TRAIT) return;
    uint bound = compact_hir_payload[owner].b;
    uint parent = compact_hir_core[owner].parent;
    bool public_impl = compact_hir_payload[owner].d == 1u ||
        (parent < active && compact_hir_semantic_facts[parent].semantic_kind == HIR_SEMANTIC_PUBLIC_IMPL);
    if (!public_impl) return;
    uint validation = predicate_method_validation_status[owner];
    if (compact_hir_core[owner].kind != 35u || compact_hir_payload[owner].a != 2u ||
        predicate_status[owner] != 0u || (validation != 0u && validation != INVALID) ||
        bound >= active || subject >= active ||
        compact_hir_payload[owner].b != bound || compact_hir_payload[owner].c != subject ||
        compact_hir_core[subject].kind != 5u)
    { fail(row, 3u); return; }
    if (head_names_private_type(subject, bound, active)) return;
    uint reference = predicate_bound_reference[owner];
    uint required_methods = INVALID;
    if (trait_reference_is_dependency(reference))
    {
        if (trait_reference_header(reference, 2u) != 0u) { fail(row, 4u); return; }
        uint4 identity = trait_reference_identity(reference);
        if (any(identity.yzw == INVALID)) { fail(row, 5u); return; }
        required_methods = trait_reference_header(reference, 3u);
    }
    else if (reference < gParams.decl_capacity && public_decl_index_by_local[reference] != INVALID)
    {
        uint trait_hir = decl_hir_node[reference];
        if (trait_hir >= active || compact_hir_payload[trait_hir].a != 10u) { fail(row, 6u); return; }
        uint token = compact_hir_payload[trait_hir].b;
        if (token >= gParams.token_capacity || type_decl_const_param_count_by_owner_token[token] != 0u)
        { fail(row, 4u); return; }
        required_methods = predicate_method_contract_owner_count[trait_hir];
    }
    // A private local trait: the interface cannot name it either.
    else if (reference < gParams.decl_capacity) return;
    else { fail(row, 5u); return; }
    // Inherited impl parameters have their own exported scope. Method rows
    // retain composed counts; required-member bindings retain exact targets.
    uint arguments = predicate_bound_arg_count[owner];
    if (arguments > 32u || required_methods != predicate_method_contract_owner_count[owner])
    { fail(row, 7u); return; }
    interface_implementation_argument_count[row] = arguments;
    interface_implementation_flag[row] = 1u;
}
