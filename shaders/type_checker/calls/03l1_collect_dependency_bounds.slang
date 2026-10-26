// Append the resident dependency page's trait implementations and the
// bounds of its free functions to the bound-directed inference tables
// (bound_tables.slang). Runs once per page and round, after the page's
// signature nodes are interned and its alias roots are current.
//
// An implementation whose header has a node without a canonical ID (or a
// constant argument) keeps its row with an unknown subject, so it still
// counts against a unique selection. A bound is kept only when its subject
// is one of the function's own type parameters and every argument has an ID;
// a dropped bound only infers nothing.
import dependency_interface;
import semantic_interface_layout;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.calls.bound_tables;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint IMPLEMENTATION_KIND_TRAIT = 2u;
// The dispatch width (resident.rs records 4096 lanes); lanes stride the page.
static const uint LANES = 4096u;

// The canonical type of dependency node `t` (its alias root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? ct_dependency_state(root) : CT_UNKNOWN;
}

bool usable_argument(uint id)
{
    return ct_is_resolved(id) && !ct_is_constant(id);
}

void collect_implementation(uint row)
{
    uint base = row * SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS;
    if (dependency_implementation_word(base + 14u) != IMPLEMENTATION_KIND_TRAIT) return;
    uint3 trait = uint3(dependency_implementation_word(base + 2u),
        dependency_implementation_word(base + 3u), dependency_implementation_word(base + 4u));
    if (any(trait == uint3(INVALID, INVALID, INVALID))) return;
    uint target = bound_reserve_row(BOUND_COUNT_IMPLEMENTATIONS);
    if (target == INVALID) return;
    uint out_base = target * BOUND_ROW_WORDS;
    uint first = dependency_implementation_word(base + 6u);
    uint count = dependency_implementation_word(base + 7u);
    uint arguments = dependency_implementation_argument_count();
    bool complete = count <= BOUND_IMPLEMENTATION_ARGUMENTS && first <= arguments &&
        count <= arguments - first;
    for (uint ordinal = 0u; ordinal < BOUND_IMPLEMENTATION_ARGUMENTS; ordinal++)
    {
        uint id = complete && ordinal < count
            ? dependency_type(dependency_implementation_argument(first + ordinal)) : CT_NONE;
        if (ordinal < count && !usable_argument(id)) complete = false;
        bound_implementation_rows[out_base + 8u + ordinal] = id;
    }
    uint subject = dependency_type(dependency_implementation_word(base + 5u));
    bound_implementation_rows[out_base + 0u] = trait.x;
    bound_implementation_rows[out_base + 1u] = trait.y;
    bound_implementation_rows[out_base + 2u] = trait.z;
    bound_implementation_rows[out_base + 3u] = dependency_implementation_library_id(row);
    bound_implementation_rows[out_base + 4u] = dependency_implementation_unit_id(row);
    bound_implementation_rows[out_base + 5u] = dependency_implementation_local_index(row);
    bound_implementation_rows[out_base + 6u] = complete && ct_is_resolved(subject) && !ct_is_constant(subject)
        ? subject : CT_UNKNOWN;
    bound_implementation_rows[out_base + 7u] = count;
}

void collect_predicate(uint row)
{
    uint base = row * SEMANTIC_INTERFACE_PREDICATE_WORDS;
    uint owner = dependency_predicate_word(base);
    // Free functions only: methods and implementation prerequisites have
    // an owner scope of their own.
    if (dependency_predicate_word(base + 1u) != 0u ||
        (owner & SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER) != 0u) return;
    uint library; uint unit; uint local;
    if (!dependency_contract_owner_identity(owner, library, unit, local)) return;
    uint subject = dependency_predicate_word(base + 2u);
    uint subject_root = subject < dependency_type_count() ? canonical_type_roots[subject] : INVALID;
    if (subject_root >= dependency_type_count() ||
        dependency_type_word(subject_root * TYPE_WORDS) != INTERFACE_TYPE_GENERIC_PARAMETER) return;
    uint slot = dependency_generic_type_slot(subject_root);
    if (slot >= 32u) return;
    uint3 trait = uint3(dependency_predicate_word(base + 3u), dependency_predicate_word(base + 4u),
        dependency_predicate_word(base + 5u));
    if (any(trait == uint3(INVALID, INVALID, INVALID))) return;
    uint first = dependency_predicate_word(base + 6u);
    uint count = dependency_predicate_word(base + 7u);
    uint arguments = dependency_predicate_argument_count();
    if (count == 0u || count > BOUND_PREDICATE_ARGUMENTS || first > arguments ||
        count > arguments - first) return;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
        if (!usable_argument(dependency_type(dependency_predicate_argument(first + ordinal)))) return;
    uint target = bound_reserve_row(BOUND_COUNT_PREDICATES);
    if (target == INVALID) return;
    uint out_base = target * BOUND_ROW_WORDS;
    bound_predicate_rows[out_base + 0u] = library;
    bound_predicate_rows[out_base + 1u] = unit;
    bound_predicate_rows[out_base + 2u] = local;
    bound_predicate_rows[out_base + 3u] = dependency_predicate_local_index(row);
    bound_predicate_rows[out_base + 4u] = slot;
    bound_predicate_rows[out_base + 5u] = trait.x;
    bound_predicate_rows[out_base + 6u] = trait.y;
    bound_predicate_rows[out_base + 7u] = trait.z;
    bound_predicate_rows[out_base + 8u] = count;
    for (uint ordinal = 0u; ordinal < BOUND_PREDICATE_ARGUMENTS; ordinal++)
        bound_predicate_rows[out_base + 9u + ordinal] = ordinal < count
            ? dependency_type(dependency_predicate_argument(first + ordinal)) : CT_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    if (lane >= LANES) return;
    uint implementations = dependency_implementation_count();
    uint predicates = dependency_predicate_count();
    uint rows = max(implementations, predicates);
    for (uint row = lane; row < rows; row += LANES)
    {
        if (row < implementations) collect_implementation(row);
        if (row < predicates) collect_predicate(row);
    }
}
