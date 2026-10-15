// Impl bindings of a body specialization packet (BodyImplBinding in
// generic_body.rs): per replayed instance, the native target of a bound member
// whose implementation program evidence selected outside the replayed unit.
// They follow the whole entry capacity at BODY_IMPL_BINDING_ROW: a header row
// (binding count, 0, 0, 0) that every job rewrites, then two rows per binding
// sorted by key (instance, slot, required symbol, trait library, trait unit):
// (instance, slot, required symbol, trait library) and (trait unit, target
// library, target unit, target symbol). The trait unit is (INVALID, INVALID)
// for a trait of the replayed unit. An instance is a batch entry
// (body_specialization_entry_for_owner).
// Requires body_specialization_inputs.
#ifndef LANIUS_BODY_IMPL_BINDINGS
#define LANIUS_BODY_IMPL_BINDINGS
#include "body_specialization_entries.slang"

static const uint BODY_IMPL_BINDING_ROW =
    BODY_GRAPH_EXT_START + BODY_GRAPH_EXT_ROWS + (BODY_MAX_ENTRIES - 1u) * BODY_EXTRA_ENTRY_ROWS;
static const uint BODY_MAX_IMPL_BINDINGS = 8192u;
// log2(BODY_MAX_IMPL_BINDINGS) + 1 halvings reach an empty range.
static const uint BODY_IMPL_BINDING_SEARCH_STEPS = 14u;

uint body_impl_binding_count()
{
    uint rows; uint stride;
    body_specialization_inputs.GetDimensions(rows, stride);
    uint count = rows > BODY_IMPL_BINDING_ROW ? body_specialization_inputs[BODY_IMPL_BINDING_ROW].x : 0u;
    uint fit = rows > BODY_IMPL_BINDING_ROW ? (rows - BODY_IMPL_BINDING_ROW - 1u) / 2u : 0u;
    return min(count, min(fit, BODY_MAX_IMPL_BINDINGS));
}

// Lexicographic order of binding `index`'s key against the wanted key:
// negative when the binding sorts first.
int body_impl_binding_compare(uint index, uint4 wanted, uint wanted_unit)
{
    uint row = BODY_IMPL_BINDING_ROW + 1u + index * 2u;
    uint4 key = body_specialization_inputs[row];
    uint unit = body_specialization_inputs[row + 1u].x;
    if (key.x != wanted.x) return key.x < wanted.x ? -1 : 1;
    if (key.y != wanted.y) return key.y < wanted.y ? -1 : 1;
    if (key.z != wanted.z) return key.z < wanted.z ? -1 : 1;
    if (key.w != wanted.w) return key.w < wanted.w ? -1 : 1;
    if (unit != wanted_unit) return unit < wanted_unit ? -1 : 1;
    return 0;
}

// The (library, unit, symbol) bound to member `symbol` of the trait in
// `trait_unit` ((INVALID, INVALID) for a trait of this unit) on type slot
// `slot` of `instance`. A binary search with a fixed step bound and no
// per-thread array.
bool body_impl_binding(uint instance, uint slot, uint symbol, uint2 trait_unit, out uint3 target)
{
    target = uint3(0xffffffffu, 0xffffffffu, 0xffffffffu);
    uint4 wanted = uint4(instance, slot, symbol, trait_unit.x);
    uint low = 0u;
    uint high = body_impl_binding_count();
    for (uint step = 0u; step < BODY_IMPL_BINDING_SEARCH_STEPS && low < high; step++)
    {
        uint middle = (low + high) / 2u;
        if (body_impl_binding_compare(middle, wanted, trait_unit.y) < 0) low = middle + 1u;
        else high = middle;
    }
    if (low >= body_impl_binding_count() || body_impl_binding_compare(low, wanted, trait_unit.y) != 0)
        return false;
    target = body_specialization_inputs[BODY_IMPL_BINDING_ROW + 2u + low * 2u].yzw;
    return true;
}

#endif
