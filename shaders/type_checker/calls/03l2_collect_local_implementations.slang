// Append this unit's trait implementations and the bounds of its generic
// free functions to the bound-directed inference tables (bound_tables.slang).
//
// One lane per HIR row: a trait implementation row adds an implementation.
// The trait is the implementation header's resolved path; the subject and
// the trait arguments are the header's checked references, interned here on
// demand. A header part without a canonical ID leaves the row with an
// unknown subject, which only makes a selection ambiguous.
//
// One lane per predicate row: an accepted bound `P: Tr<A1..An>` of a free
// function adds a predicate row when P is one of the function's own type
// parameters and every argument interns. The function's parameters intern
// as its slots, as an imported function's do (03l1).
//
// A local trait's identity is (BOUND_LOCAL_IMPLEMENTATION, 0, declaration);
// a local function's is (BOUND_LOCAL_IMPLEMENTATION, 1, HIR node).
import hir_records;
import type_checker.type.instances.generic_param_lookup;
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
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirPredicate> compact_predicates;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_lookup_state;

static const uint INVALID = 0xffffffffu;
static const uint HIR_IMPL = 35u;
static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;

#include "../type/instances/lexical_parameter_lookup.slang"

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

bool valid_node(uint node) { return node < hir_count(); }

// The checked reference of type expression `node`.
uint2 type_reference(uint node)
{
    uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    return token < gParams.n_tokens
        ? uint2(type_expr_ref_tag[token], type_expr_ref_payload[token]) : uint2(0u, INVALID);
}

// The bound-table identity of the resolved trait of path node `trait_node`
// (an imported trait's (library, unit, declaration), a local trait's
// (BOUND_LOCAL_IMPLEMENTATION, 0, declaration)); false when it is no trait.
bool trait_identity(uint trait_node, out uint3 identity)
{
    identity = uint3(INVALID, INVALID, INVALID);
    if (!valid_node(trait_node) ||
        compact_hir_semantic_facts[trait_node].semantic_kind != HIR_SEMANTIC_TYPE_PATH) return false;
    uint path = path_id_by_owner_hir[trait_node];
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes) || resolved_type_status[path] != 0u)
        return false;
    uint decl = resolved_type_decl[path];
    if (decl < min(decl_count_out[0u], gParams.n_hir_nodes))
    {
        if (decl_kind[decl] != HIR_ITEM_KIND_TRAIT) return false;
        identity = uint3(BOUND_LOCAL_IMPLEMENTATION, 0u, decl);
        return true;
    }
    uint reference = trait_reference_for_dependency_path(path);
    if (!trait_reference_is_dependency(reference)) return false;
    identity = trait_reference_identity(reference).yzw;
    return true;
}

// The bound-table identity of an accepted predicate's trait reference.
bool predicate_trait_identity(uint reference, out uint3 identity)
{
    identity = uint3(INVALID, INVALID, INVALID);
    if (reference == INVALID) return false;
    if (trait_reference_is_dependency(reference))
    {
        identity = trait_reference_identity(reference).yzw;
        return true;
    }
    if (reference >= min(decl_count_out[0u], gParams.n_hir_nodes) ||
        decl_kind[reference] != HIR_ITEM_KIND_TRAIT) return false;
    identity = uint3(BOUND_LOCAL_IMPLEMENTATION, 0u, reference);
    return true;
}

void collect_predicate(uint row)
{
    if (row >= min(compact_predicate_count[0u], gParams.n_hir_nodes)) return;
    HirPredicate predicate = compact_predicates[row];
    uint bound = predicate.bound;
    uint owner = predicate.owner;
    if ((predicate.metadata & 0xffu) != 1u || !valid_node(bound) || !valid_node(owner)) return;
    // Free functions only: a method's bounds include its impl's, and an
    // impl's own bounds are prerequisites.
    if (compact_hir_core[owner].kind != HIR_FN || predicate_owner_node[bound] != owner ||
        predicate_status[bound] != 0u) return;
    uint parent = compact_hir_core[owner].parent;
    if (valid_node(parent) && valid_node(generic_decl_owner_by_node_a[parent])) return;
    uint3 trait;
    if (!predicate_trait_identity(predicate_bound_reference[bound], trait)) return;
    uint subject = predicate_subject_token[bound];
    if (subject != predicate.subject || subject >= gParams.n_tokens) return;
    uint parameters = min(generic_param_count_out[0u], gParams.n_tokens);
    uint parameter = lexical_parameter_row(bound, subject, GENERIC_PARAM_KIND_TYPE);
    if (parameter >= parameters ||
        generic_param_owner_token[parameter] != lexical_parameter_owner_token(owner)) return;
    uint slot = CtCheckedRows.generic_slot(generic_param_token[parameter]);
    if (slot >= 32u) return;
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[bound];
    if (range.count == 0u || range.count > BOUND_PREDICATE_ARGUMENTS || range.start > total ||
        range.count > total - range.start) return;
    uint4 low = uint4(CT_NONE, CT_NONE, CT_NONE, CT_NONE);
    uint4 high = low;
    uint spare = CT_NONE;
    for (uint ordinal = 0u; ordinal < BOUND_PREDICATE_ARGUMENTS; ordinal++)
    {
        if (ordinal >= range.count) break;
        uint2 reference = type_reference(compact_type_args[range.start + ordinal].value);
        uint id = reference.x != 0u && reference.y != INVALID
            ? ct_intern_checked<CtCheckedRows>(reference.x, reference.y, spare) : CT_UNKNOWN;
        if (!ct_is_resolved(id) || ct_is_constant(id)) return;
        uint lane = ordinal & 3u;
        if (ordinal < 4u)
            low = uint4(lane == 0u ? id : low.x, lane == 1u ? id : low.y, lane == 2u ? id : low.z, lane == 3u ? id : low.w);
        else
            high = uint4(lane == 0u ? id : high.x, lane == 1u ? id : high.y, lane == 2u ? id : high.z, lane == 3u ? id : high.w);
    }
    uint target = bound_reserve_row(BOUND_COUNT_PREDICATES);
    if (target == INVALID) return;
    uint base = target * BOUND_ROW_WORDS;
    bound_predicate_rows[base + 0u] = BOUND_LOCAL_IMPLEMENTATION;
    bound_predicate_rows[base + 1u] = 1u;
    bound_predicate_rows[base + 2u] = owner;
    bound_predicate_rows[base + 3u] = row;
    bound_predicate_rows[base + 4u] = slot;
    bound_predicate_rows[base + 5u] = trait.x;
    bound_predicate_rows[base + 6u] = trait.y;
    bound_predicate_rows[base + 7u] = trait.z;
    bound_predicate_rows[base + 8u] = range.count;
    for (uint ordinal = 0u; ordinal < BOUND_PREDICATE_ARGUMENTS; ordinal++)
    {
        uint4 part = ordinal < 4u ? low : high;
        uint lane = ordinal & 3u;
        uint id = lane == 0u ? part.x : lane == 1u ? part.y : lane == 2u ? part.z : part.w;
        bound_predicate_rows[base + 9u + ordinal] = ordinal < range.count ? id : CT_NONE;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    collect_predicate(node);
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_IMPL ||
        compact_hir_semantic_facts[node].semantic_kind != HIR_SEMANTIC_IMPL_TRAIT) return;
    uint trait_node = predicate_trait_impl_trait_type_node[node];
    uint3 trait;
    if (!trait_identity(trait_node, trait)) return;
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
    bound_implementation_rows[base + 0u] = trait.x;
    bound_implementation_rows[base + 1u] = trait.y;
    bound_implementation_rows[base + 2u] = trait.z;
    bound_implementation_rows[base + 3u] = BOUND_LOCAL_IMPLEMENTATION;
    bound_implementation_rows[base + 4u] = 0u;
    bound_implementation_rows[base + 5u] = node;
    bound_implementation_rows[base + 6u] = complete ? subject : CT_UNKNOWN;
    bound_implementation_rows[base + 7u] = complete ? count : range.count;
}
