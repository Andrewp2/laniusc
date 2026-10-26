// Append this unit's implementations of imported traits to the bound-directed
// inference tables (bound_tables.slang). One lane per trait implementation
// HIR row. The trait is the implementation header's resolved path; the
// subject and the trait arguments are the header's checked references,
// interned here on demand. A header part without a canonical ID leaves the
// row with an unknown subject, which only makes a selection ambiguous.
//
// A local trait cannot appear in an imported function's bound, so its
// implementations are not collected.
import hir_records;
import type_checker.checked_type_graph;
import type_checker.predicates.trait_reference;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.calls.bound_tables;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> predicate_trait_impl_trait_type_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_IMPL = 35u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

bool valid_node(uint node) { return node < hir_count(); }

// The checked reference of type expression `node`.
uint2 type_reference(uint node)
{
    uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    return token < gParams.n_tokens
        ? uint2(type_expr_ref_tag[token], type_expr_ref_payload[token]) : uint2(0u, INVALID);
}

// The resolved imported trait of the header's trait path, or INVALID.
uint imported_trait(uint trait_node)
{
    if (!valid_node(trait_node) ||
        compact_hir_semantic_facts[trait_node].semantic_kind != HIR_SEMANTIC_TYPE_PATH) return INVALID;
    uint path = path_id_by_owner_hir[trait_node];
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes) || resolved_type_status[path] != 0u)
        return INVALID;
    if (resolved_type_decl[path] < min(decl_count_out[0u], gParams.n_hir_nodes)) return INVALID;
    return trait_reference_for_dependency_path(path);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_IMPL ||
        compact_hir_semantic_facts[node].semantic_kind != HIR_SEMANTIC_IMPL_TRAIT) return;
    uint trait_node = predicate_trait_impl_trait_type_node[node];
    uint reference = imported_trait(trait_node);
    if (!trait_reference_is_dependency(reference)) return;
    uint4 trait = trait_reference_identity(reference);
    uint target = bound_reserve_row(BOUND_COUNT_IMPLEMENTATIONS);
    if (target == INVALID) return;
    uint base = target * BOUND_ROW_WORDS;
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[trait_node];
    bool complete = range.start <= total && range.count <= total - range.start &&
        range.count <= BOUND_IMPLEMENTATION_ARGUMENTS;
    uint count = complete ? range.count : 0u;
    // Operand 0 is the subject, operand 1 + i trait argument i: one
    // interning site serves them all.
    uint subject = CT_UNKNOWN;
    uint spare = CT_NONE;
    for (uint operand = 0u; operand <= BOUND_IMPLEMENTATION_ARGUMENTS; operand++)
    {
        uint id = CT_NONE;
        if (complete && operand <= count)
        {
            uint2 reference = type_reference(operand == 0u
                ? compact_hir_semantic_facts[node].method_impl_receiver_type
                : compact_type_args[range.start + operand - 1u].value);
            id = reference.x != 0u && reference.y != INVALID
                ? ct_intern_checked<CtCheckedRows>(reference.x, reference.y, spare) : CT_UNKNOWN;
            if (!ct_is_resolved(id) || ct_is_constant(id)) complete = false;
        }
        if (operand == 0u) subject = id;
        else bound_implementation_rows[base + 7u + operand] = id;
    }
    bound_implementation_rows[base + 0u] = trait.y;
    bound_implementation_rows[base + 1u] = trait.z;
    bound_implementation_rows[base + 2u] = trait.w;
    bound_implementation_rows[base + 3u] = BOUND_LOCAL_IMPLEMENTATION;
    bound_implementation_rows[base + 4u] = 0u;
    bound_implementation_rows[base + 5u] = node;
    bound_implementation_rows[base + 6u] = complete ? subject : CT_UNKNOWN;
    bound_implementation_rows[base + 7u] = complete ? count : range.count;
}
