// Imported alias targets over canonical IDs. Each alias use's leaf row is
// interned on demand (ahead of the early canonical stage), and its ID is the
// environment of the alias declaration's signature: the target is the
// signature's canonical type substituted under it (ct_subst). The leaf
// application is the environment, so an alias keeps its own environment.
//
// Each page contributes the targets of its own declarations, published as
// (0, ID) until substitution/08 realizes them as checked rows after the last
// page; a later normalization then follows nested alias targets without
// depending on dependency page order. Normalization rewrites rows interned
// here, so 09_rearm_early_candidates re-arms them for the early stage.
import dependency_interface;
import status;
import type_checker.checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_checked;
import type_checker.substitution.checked_source_slots;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint4> resolved_value_qualifier_binding;
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
RWStructuredBuffer<uint2> imported_type_alias_target;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
// Failure details: the leaf has no canonical ID, the signature has none,
// or the substitution has none.
static const uint FAILURE_LEAF = 0x41490011u;
static const uint FAILURE_SIGNATURE = 0x41490012u;
static const uint FAILURE_TARGET = 0x41490013u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path = dtid.x + dtid.y * 16776960u;
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return;
    uint count = path_segment_count[path];
    uint4 parent = resolved_value_qualifier_binding[path];
    bool qualified_value = path_kind[path] == 3u && count >= 2u && parent.x == 2u;
    if (count == 0u || (path_kind[path] != 4u && !qualified_value)) return;
    uint leaf = path_segment_token[path_segment_base[path] + count - (qualified_value ? 2u : 1u)];
    if (leaf >= gParams.n_tokens || type_instance_kind[leaf] != 1u || type_instance_state[leaf] != 1u) return;
    uint declaration = qualified_value
        ? dependency_find_declaration(parent.y, parent.z, parent.w)
        : dependency_find_declaration(resolved_dependency_library_id[path],
            resolved_dependency_unit_id[path], resolved_dependency_local_index[path]);
    if (declaration == INVALID || dependency_declaration_word(declaration * 14u + 6u) != 8u) return;
    uint signature = dependency_declaration_word(declaration * 14u + 7u);
    uint types = dependency_type_count();
    uint root = signature < types ? canonical_type_roots[signature] : INVALID;
    uint pattern = root < types ? ct_dependency_state(root) : CT_UNKNOWN;
    if (!ct_is_resolved(pattern)) { record_min_token_error(status, leaf, 6u, FAILURE_SIGNATURE); return; }
    // Candidates this lane publishes are re-armed before the early stage.
    if (ct_subst_counts[CT_SUBST_COUNT_EARLY_INTERNED] == 0u)
        InterlockedOr(ct_subst_counts[CT_SUBST_COUNT_EARLY_INTERNED], 1u);
    uint row_spare = CT_NONE;
    uint application = ct_intern_checked<CtCheckedRows>(3u, leaf, row_spare);
    if (!ct_is_record(application) || ct_kind(application) != CT_KIND_NAMED)
    { record_min_token_error(status, leaf, 6u, FAILURE_LEAF); return; }
    CtSpare spare = ct_spare_none();
    uint target = ct_subst(CheckedSourceSlots(), application, pattern, true, spare);
    if (!ct_is_resolved(target) || ct_is_constant(target))
    { record_min_token_error(status, leaf, 6u, FAILURE_TARGET); return; }
    imported_type_alias_target[leaf] = uint2(0u, target);
}
