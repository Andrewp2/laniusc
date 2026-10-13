import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.native_layout.recipe_abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.graph_admission;

// These are the parser HIR item kinds retained in SourceLocal binder identity.
// Declaration start (binder.w) and declaration name (nominal.z) are distinct.
static const uint PLR_HIR_ENUM_ITEM = 26u;
static const uint PLR_HIR_STRUCT_ITEM = 27u;

public EvidenceStatus plr_admit_recipe(uint recipe)
{
    uint4 row; uint4 tail; uint4 owner; uint4 span; uint4 identity; uint4 extra;
    uint4 binder; uint4 binder_extra; uint group_offset; uint groups; uint group_width;
    if (!plr_read_recipe(recipe, row, tail) || row.z < 1u || row.z > 2u || tail.w != 0u ||
        !pev_read_admitted_owner(row.y, owner, span) || owner.z != tail.y ||
        !pev_atom(row.x, identity, extra) || !pev_atom(owner.x, binder, binder_extra) ||
        any(extra != uint4(0u, 0u, 0u, 0u)) ||
        !plr_table(1u, group_offset, groups, group_width) ||
        (tail.x == 0u && row.w != 0u) || row.w > groups || tail.x > groups - row.w ||
        (row.z == 1u && tail.x != 1u)) return pev_invalid(160u, recipe, PEV_INVALID);
    if (identity.x == 1u)
    {
        // An actual public declaration has the same exported owner atom and no
        // associated-method scope. Never synthesize public identity for private data.
        if (binder.x != 3u || any(identity.yzw != binder.yzw) ||
            any(binder_extra != uint4(0u, 0u, 0u, 0u)) || tail.z != PEV_INVALID)
            return pev_invalid(161u, recipe, row.y);
    }
    else if (identity.x == 2u)
    {
        uint wanted_kind = row.z == 1u ? PLR_HIR_STRUCT_ITEM : PLR_HIR_ENUM_ITEM;
        if (identity.y != owner.y || identity.z != tail.z || identity.w != 0u ||
            binder.x != 4u || binder.y != owner.y || binder.z != wanted_kind ||
            any(binder_extra != uint4(0u, 0u, 0u, 0u)))
            return pev_invalid(161u, recipe, row.y);
    }
    else return pev_invalid(161u, recipe, row.x);
    // Retain accepted definitions independently of whether any application
    // requests a native layout. Application arity is checked at materialization.
    // Both directions are required: group admission proves its owner claims
    // this row, and recipe admission proves no row was borrowed from another
    // definition (including a record that claims another record's sole group).
    for (uint ordinal = 0u; ordinal < tail.x; ordinal++)
    {
        uint3 group;
        if (!plr_read_group(row.w + ordinal, group) || group.x != recipe)
            return pev_invalid(165u, recipe, row.w + ordinal);
    }
    uint address;
    if (!plr_address(3u, row.x, 0u, 1u, address)) return pev_invalid(160u, recipe, row.x);
    uint previous;
    InterlockedCompareExchange(program_evidence_native_recipes[address], PEV_INVALID, recipe, previous);
    if (previous != PEV_INVALID) return pev_invalid(164u, recipe, previous);
    return pev_ok();
}

public EvidenceStatus plr_admit_group(uint group)
{
    uint3 row; uint4 recipe; uint4 tail;
    if (!plr_read_group(group, row) || !plr_read_recipe(row.x, recipe, tail) ||
        group < recipe.w || group - recipe.w >= tail.x ||
        (row.z == 0u && row.y != 0u)) return pev_invalid(165u, group, PEV_INVALID);
    uint roots;
    if (!pev_catalog_count(7u, roots) || row.y > roots || row.z > roots - row.y)
        return pev_invalid(165u, group, row.y);
    // Independent complete graph budgets for every field/variant operand.
    // Rows have already passed the catalog's physical node/edge admission.
    for (uint i = 0u; i < row.z; i++)
    {
        uint2 reference;
        if (!pev_read_root(row.y + i, reference) || !pev_admitted_type_reference_shape(reference))
            return pev_invalid(166u, group, row.y + i);
        uint visits;
        EvidenceStatus result = pev_admit_catalog_definition_root(row.y + i, recipe.y, false, visits);
        if (result.state != PEV_VALID) return result;
    }
    return pev_ok();
}
