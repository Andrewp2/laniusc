import type_checker.constant_storage_plan;
// Initialize one parent pointer per canonical dependency type. Type aliases
// point at their checked signature type; all other nodes are roots. Later
// parallel pointer-jumping rounds flatten arbitrary alias chains.

import dependency_interface;
import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> canonical_type_roots;
RWStructuredBuffer<uint2> dependency_constant_ref_by_type_out;
RWStructuredBuffer<uint4> checked_constant_atoms;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

bool identity_less(
    uint library_id,
    uint unit_id,
    uint local_index,
    uint target_library,
    uint target_unit,
    uint target_local)
{
    return library_id < target_library ||
           (library_id == target_library &&
            (unit_id < target_unit ||
             (unit_id == target_unit && local_index < target_local)));
}

uint find_declaration(uint library_id, uint unit_id, uint local_index)
{
    uint lo = 0u;
    uint hi = dependency_declaration_count();
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_library = dependency_declaration_library_id(mid);
        uint mid_unit = dependency_declaration_unit_id(mid);
        uint mid_local = dependency_declaration_local_index(mid);
        if (identity_less(mid_library, mid_unit, mid_local, library_id, unit_id, local_index))
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo < dependency_declaration_count() &&
        dependency_declaration_library_id(lo) == library_id &&
        dependency_declaration_unit_id(lo) == unit_id &&
        dependency_declaration_local_index(lo) == local_index)
        return lo;
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= dependency_type_count())
        return;
    uint root = type_i;
    uint base = type_i * TYPE_WORDS;
    if (dependency_type_word(base) == INTERFACE_TYPE_DECLARATION)
    {
        uint declaration_i = find_declaration(
            dependency_type_word(base + 1u),
            dependency_type_word(base + 8u),
            dependency_type_word(base + 2u));
        if (declaration_i != INVALID)
        {
            uint declaration_base = declaration_i * DECL_WORDS;
            // A declaration-shaped use such as Boxed<i32> owns its generic
            // edges and must remain its own canonical node. Only a true type
            // alias redirects to the declaration's checked target signature.
            if (dependency_declaration_word(declaration_base + 6u) ==
                HIR_ITEM_KIND_TYPE_ALIAS)
            {
                uint signature = dependency_declaration_word(declaration_base + 7u);
                if (signature < dependency_type_count() && signature != type_i)
                    root = signature;
            }
        }
    }
    canonical_type_roots[type_i] = root;

    // This map is page-local. Published atom rows instead belong to an immutable
    // per-page span retained across every replay of the dependency slot.
    uint map_capacity; uint map_stride;
    dependency_constant_ref_by_type_out.GetDimensions(map_capacity, map_stride);
    if (type_i >= map_capacity) return;
    dependency_constant_ref_by_type_out[type_i] = uint2(0u, INVALID);
    uint3 value;
    if (!dependency_literal_constant_value(type_i, value)) return;
    uint page_base = dependency_constant_type_span_base();
    uint total = dependency_constant_type_rows();
    if (page_base > total || type_i >= total - page_base ||
        gConstantStoragePlan.imported_base > gConstantStoragePlan.dynamic_base ||
        total > gConstantStoragePlan.dynamic_base - gConstantStoragePlan.imported_base ||
        gConstantStoragePlan.dynamic_base > gConstantStoragePlan.dynamic_limit ||
        gConstantStoragePlan.dynamic_limit > gConstantStoragePlan.total_rows ||
        gConstantStoragePlan.total_rows - gConstantStoragePlan.dynamic_limit != 96u) return;
    uint atom = gConstantStoragePlan.imported_base + page_base + type_i;
    uint atom_capacity; uint atom_stride;
    checked_constant_atoms.GetDimensions(atom_capacity, atom_stride);
    // The final 96 rows belong exclusively to selected-body replay.
    if (gConstantStoragePlan.total_rows > atom_capacity || atom >= gConstantStoragePlan.dynamic_base) return;
    checked_constant_atoms[atom] = uint4(value, 0u);
    dependency_constant_ref_by_type_out[type_i] = uint2(1u, atom);

}
