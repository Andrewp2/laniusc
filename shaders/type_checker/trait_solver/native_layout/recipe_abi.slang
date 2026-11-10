// Immutable checked nominal recipes share the program's admitted graph roots.
// The sidecar is owned by the exact frozen catalog; it is never a source-job
// scratch resource or a second implementation/identity registry.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;

public static const uint PLR_MAGIC = 0x504c5231u;
public static const uint PLR_VERSION = 1u;
public static const uint PLR_HEADER_WORDS = 24u;
public static const uint PLR_BUILDING = 0x80000001u;
public static const uint PLR_BUSY = 0x80000000u;
public RWStructuredBuffer<uint> trait_solver_native_recipes;

// The binding covers the retained allocation; the dispatch parameters carry
// the logical extent. A logical extent beyond the allocation reads as empty.
public uint plr_logical_words()
{
    uint physical; uint stride;
    trait_solver_native_recipes.GetDimensions(physical, stride);
    uint logical = trait_solver_params.recipe_word_count;
    return select(logical <= physical, logical, 0u);
}

public bool plr_table(uint table, out uint offset, out uint count, out uint width)
{
    offset = TS_INVALID; count = 0u; width = 0u;
    uint actual = plr_logical_words();
    if (table >= 4u || actual < PLR_HEADER_WORDS) return false;
    uint logical = trait_solver_native_recipes[5u];
    if (logical < PLR_HEADER_WORDS || logical > actual) return false;
    uint base = 8u + table * 3u;
    offset = trait_solver_native_recipes[base];
    count = trait_solver_native_recipes[base + 1u];
    width = trait_solver_native_recipes[base + 2u];
    uint expected = table == 0u || table == 2u ? 8u : (table == 1u ? 3u : 1u);
    return width == expected && count != TS_INVALID &&
        (count != 0u || offset == 0u) &&
        ts_word_span(offset, count, width, logical);
}
public bool plr_address(uint table, uint row, uint field, uint fields, out uint address)
{
    address = TS_INVALID; uint offset; uint count; uint width;
    if (!plr_table(table, offset, count, width) || row >= count ||
        field >= width || fields == 0u || fields > width - field) return false;
    address = offset + row * width + field; return true;
}
public bool plr_read_recipe(uint recipe, out uint4 low, out uint4 high)
{
    low = high = uint4(0u, 0u, 0u, 0u); uint address;
    if (!plr_address(0u, recipe, 0u, 8u, address)) return false;
    low = uint4(trait_solver_native_recipes[address], trait_solver_native_recipes[address + 1u],
        trait_solver_native_recipes[address + 2u], trait_solver_native_recipes[address + 3u]);
    high = uint4(trait_solver_native_recipes[address + 4u], trait_solver_native_recipes[address + 5u],
        trait_solver_native_recipes[address + 6u], trait_solver_native_recipes[address + 7u]);
    return true;
}
public bool plr_read_group(uint group, out uint3 value)
{
    value = uint3(TS_INVALID, TS_INVALID, TS_INVALID); uint address;
    if (!plr_address(1u, group, 0u, 3u, address)) return false;
    value = uint3(trait_solver_native_recipes[address], trait_solver_native_recipes[address + 1u],
        trait_solver_native_recipes[address + 2u]); return true;
}
public bool plr_header_is_valid()
{
    uint actual = plr_logical_words();
    if (actual < PLR_HEADER_WORDS || !ts_catalog_is_valid()) return false;
    if (trait_solver_native_recipes[0u] != PLR_MAGIC ||
        trait_solver_native_recipes[1u] != PLR_VERSION ||
        trait_solver_native_recipes[2u] != trait_solver_catalog[2u] ||
        trait_solver_native_recipes[3u] != trait_solver_catalog[3u] ||
        trait_solver_native_recipes[7u] != 0u) return false;
    for (uint reserved = 20u; reserved < PLR_HEADER_WORDS; reserved++)
        if (trait_solver_native_recipes[reserved] != 0u) return false;
    uint atoms;
    if (!ts_catalog_count(1u, atoms) || trait_solver_native_recipes[6u] != atoms) return false;
    uint input_end = trait_solver_native_recipes[4u];
    uint logical = trait_solver_native_recipes[5u];
    if (input_end < PLR_HEADER_WORDS || input_end > logical || logical != actual) return false;
    uint next = PLR_HEADER_WORDS;
    // A canonical contiguous layout proves all input/output spans disjoint.
    for (uint table = 0u; table < 4u; table++)
    {
        uint offset; uint count; uint width;
        if (!plr_table(table, offset, count, width) ||
            (count != 0u && offset != next)) return false;
        if ((table == 2u && count != 1u) || (table == 3u && count != atoms)) return false;
        next += count * width; // table reader proved this product/span fits.
        if (table == 1u && next != input_end) return false;
    }
    return next == logical;
}
public bool plr_state(out uint state)
{
    state = 0u; uint address;
    if (!plr_address(2u, 0u, 0u, 1u, address)) return false;
    state = trait_solver_native_recipes[address]; return true;
}
public bool plr_building()
{
    uint state;
    return plr_header_is_valid() && plr_state(state) && state == PLR_BUILDING;
}
public bool plr_is_valid()
{
    uint state;
    return plr_header_is_valid() && plr_state(state) && state == TS_VALID;
}
public bool plr_write_status(EvidenceStatus status)
{
    uint address;
    if (!plr_address(2u, 0u, 0u, 8u, address)) return false;
    trait_solver_native_recipes[address + 1u] = status.detail;
    trait_solver_native_recipes[address + 2u] = status.subject_row;
    trait_solver_native_recipes[address + 3u] = status.related_row;
    trait_solver_native_recipes[address + 4u] = status.required;
    trait_solver_native_recipes[address + 5u] = status.available;
    trait_solver_native_recipes[address + 6u] = 0u;
    trait_solver_native_recipes[address + 7u] = 0u;
    trait_solver_native_recipes[address] = status.state; return true;
}
public void plr_failure(EvidenceStatus status)
{
    if (status.state == TS_VALID) return;
    uint address;
    if (!plr_address(2u, 0u, 0u, 8u, address)) return;
    uint previous;
    InterlockedCompareExchange(trait_solver_native_recipes[address], PLR_BUILDING, PLR_BUSY, previous);
    if (previous != PLR_BUILDING) return;
    trait_solver_native_recipes[address + 1u] = status.detail;
    trait_solver_native_recipes[address + 2u] = status.subject_row;
    trait_solver_native_recipes[address + 3u] = status.related_row;
    trait_solver_native_recipes[address + 4u] = status.required;
    trait_solver_native_recipes[address + 5u] = status.available;
    trait_solver_native_recipes[address + 6u] = 0u;
    trait_solver_native_recipes[address + 7u] = 0u;
    InterlockedCompareExchange(trait_solver_native_recipes[address], PLR_BUSY, status.state, previous);
}
// Available only after the complete sidecar admission/freeze barrier. A valid
// nominal without a definition is distinct from an invalid identity.
public bool plr_recipe_for_nominal(uint atom, out uint recipe)
{
    recipe = TS_INVALID; uint address;
    if (!plr_address(3u, atom, 0u, 1u, address)) return false;
    recipe = trait_solver_native_recipes[address]; return recipe != TS_INVALID;
}
