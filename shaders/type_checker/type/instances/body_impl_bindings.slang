// V2 impl bindings of a body specialization packet. The sorted key is
// (instance, subject type slot, required symbol, trait library, trait unit).
// Its value is an exact target plus a retained declaration-slot environment,
// never an environment inferred from the target or the receiver's spelling.
// Requires body_specialization_inputs.
#ifndef LANIUS_BODY_IMPL_BINDINGS
#define LANIUS_BODY_IMPL_BINDINGS
#include "body_specialization_entries.slang"

static const uint BODY_IMPL_BINDING_ROW =
    BODY_GRAPH_EXT_START + BODY_GRAPH_EXT_ROWS + (BODY_MAX_ENTRIES - 1u) * BODY_EXTRA_ENTRY_ROWS;
static const uint BODY_MAX_IMPL_BINDINGS = 8192u;
static const uint BODY_IMPL_BINDING_MAGIC = 0x42494232u;
static const uint BODY_IMPL_BINDING_VERSION = 2u;
static const uint BODY_IMPL_BINDING_ROWS = 3u;
static const uint BODY_MAX_IMPL_ENVIRONMENTS = 8192u;
static const uint BODY_MAX_IMPL_ARGUMENTS = 32768u;
static const uint BODY_IMPL_ENVIRONMENT_ROW =
    BODY_IMPL_BINDING_ROW + 2u + BODY_IMPL_BINDING_ROWS * BODY_MAX_IMPL_BINDINGS;
static const uint BODY_IMPL_ARGUMENT_ROW = BODY_IMPL_ENVIRONMENT_ROW + BODY_MAX_IMPL_ENVIRONMENTS;
// log2(BODY_MAX_IMPL_BINDINGS) + 1 halvings reach an empty range.
static const uint BODY_IMPL_BINDING_SEARCH_STEPS = 14u;

// Every ordinary/replay job writes both header rows. Only used pool prefixes
// need physical backing; unreferenced tails are never read. No count truncates.
bool body_impl_binding_header(out uint3 counts)
{
    counts = uint3(0u, 0u, 0u);
    uint rows; uint stride;
    body_specialization_inputs.GetDimensions(rows, stride);
    if (rows < BODY_IMPL_BINDING_ROW + 2u) return false;
    uint4 header = body_specialization_inputs[BODY_IMPL_BINDING_ROW];
    uint4 arguments = body_specialization_inputs[BODY_IMPL_BINDING_ROW + 1u];
    if (header.x != BODY_IMPL_BINDING_MAGIC || header.y != BODY_IMPL_BINDING_VERSION ||
        header.z > BODY_MAX_IMPL_BINDINGS || header.w > BODY_MAX_IMPL_ENVIRONMENTS ||
        arguments.x > BODY_MAX_IMPL_ARGUMENTS || any(arguments.yzw != 0u)) return false;
    if (header.z > (rows - BODY_IMPL_BINDING_ROW - 2u) / BODY_IMPL_BINDING_ROWS ||
        (header.w != 0u && (rows < BODY_IMPL_ENVIRONMENT_ROW || header.w > rows - BODY_IMPL_ENVIRONMENT_ROW)) ||
        (arguments.x != 0u && (rows < BODY_IMPL_ARGUMENT_ROW || arguments.x > rows - BODY_IMPL_ARGUMENT_ROW)) ||
        ((header.w == 0u) != (arguments.x == 0u))) return false;
    counts = uint3(header.z, header.w, arguments.x);
    return true;
}

uint4 body_impl_binding_key(uint index)
{
    return body_specialization_inputs[BODY_IMPL_BINDING_ROW + 2u + index * BODY_IMPL_BINDING_ROWS];
}
uint4 body_impl_binding_target(uint index)
{
    return body_specialization_inputs[BODY_IMPL_BINDING_ROW + 3u + index * BODY_IMPL_BINDING_ROWS];
}
uint4 body_impl_binding_environment(uint index)
{
    return body_specialization_inputs[BODY_IMPL_BINDING_ROW + 4u + index * BODY_IMPL_BINDING_ROWS];
}
uint4 body_impl_environment(uint index)
{
    return body_specialization_inputs[BODY_IMPL_ENVIRONMENT_ROW + index];
}
uint4 body_impl_argument(uint index)
{
    return body_specialization_inputs[BODY_IMPL_ARGUMENT_ROW + index];
}

// Lexicographic order of binding `index`'s key against the wanted key:
// negative when the binding sorts first.
int body_impl_binding_compare(uint index, uint4 wanted, uint wanted_unit)
{
    uint4 key = body_impl_binding_key(index);
    uint unit = body_impl_binding_target(index).x;
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
bool body_impl_binding(uint instance, uint slot, uint symbol, uint2 trait_unit,
    out uint3 target, out uint4 environment)
{
    target = uint3(0xffffffffu, 0xffffffffu, 0xffffffffu);
    environment = uint4(0xffffffffu, 0u, 0u, 0u);
    uint3 counts;
    if (!body_impl_binding_header(counts)) return false;
    uint4 wanted = uint4(instance, slot, symbol, trait_unit.x);
    uint low = 0u;
    uint high = counts.x;
    for (uint step = 0u; step < BODY_IMPL_BINDING_SEARCH_STEPS && low < high; step++)
    {
        uint middle = (low + high) / 2u;
        if (body_impl_binding_compare(middle, wanted, trait_unit.y) < 0) low = middle + 1u;
        else high = middle;
    }
    if (low >= counts.x || body_impl_binding_compare(low, wanted, trait_unit.y) != 0)
        return false;
    target = body_impl_binding_target(low).yzw;
    environment = body_impl_binding_environment(low);
    return true;
}

// Distributed seed validation. Fixed pool bases fit in the header's physical
// prefix, while every referenced graph root belongs to the raw graph count.
bool body_impl_binding_valid(uint index, uint3 counts)
{
    static const uint BAD = 0xffffffffu;
    uint4 graph = body_specialization_inputs[0u];
    uint4 entries = body_specialization_inputs[705u];
    if (graph.x > BODY_TYPE_SLOTS || entries.x > BODY_CONSTANT_SLOTS ||
        entries.y >= BODY_MAX_ENTRIES || graph.z > BODY_GRAPH_NODES || graph.w > BODY_GRAPH_EDGES) return false;
    uint entry_count = graph.x != 0u || entries.x != 0u ? entries.y + 1u : 0u;
    if (entry_count == 0u && entries.y != 0u) return false;
    uint4 key = body_impl_binding_key(index);
    uint4 target = body_impl_binding_target(index);
    uint4 environment = body_impl_binding_environment(index);
    if (key.x >= entry_count || key.y >= BODY_TYPE_SLOTS || key.z == BAD ||
        any(target.yzw == BAD) || ((key.w == BAD) != (target.x == BAD)) || environment.w > 3u) return false;
    uint4 entry = body_entry_header(key.x);
    if (entry.x > BODY_TYPE_SLOTS || entry.w > BODY_CONSTANT_SLOTS || key.y >= entry.x) return false;
    if (index != 0u)
    {
        uint4 previous = body_impl_binding_key(index - 1u);
        uint previous_unit = body_impl_binding_target(index - 1u).x;
        if (body_impl_binding_compare(index, previous, previous_unit) <= 0) return false;
    }
    if (environment.y > BODY_TYPE_SLOTS || environment.z > BODY_CONSTANT_SLOTS) return false;
    if (environment.y == 0u && environment.z == 0u) return environment.x == BAD;
    if (environment.x >= counts.y) return false;
    uint4 span = body_impl_environment(environment.x);
    return span.y == environment.y && span.z == environment.z;
}

bool body_impl_environment_valid(uint index, uint3 counts)
{
    uint4 span = body_impl_environment(index);
    if (span.w != 0u || span.y > BODY_TYPE_SLOTS || span.z > BODY_CONSTANT_SLOTS ||
        span.y + span.z == 0u || span.x > counts.z || span.y + span.z > counts.z - span.x) return false;
    if (index == 0u) { if (span.x != 0u) return false; }
    else
    {
        uint4 previous = body_impl_environment(index - 1u);
        if (previous.y > BODY_TYPE_SLOTS || previous.z > BODY_CONSTANT_SLOTS ||
            previous.x > counts.z || previous.y + previous.z > counts.z - previous.x ||
            span.x != previous.x + previous.y + previous.z) return false;
    }
    if (index + 1u == counts.y && span.x + span.y + span.z != counts.z) return false;
    uint graph_count = body_specialization_inputs[0u].z;
    if (graph_count > BODY_GRAPH_NODES) return false;
    for (uint local = 0u; local < span.y + span.z; local++)
    {
        uint4 argument = body_impl_argument(span.x + local);
        bool constant = local >= span.y;
        uint slot = constant ? local - span.y : local;
        if (argument.x != (constant ? 1u : 0u) || argument.y != slot ||
            argument.z >= graph_count || argument.w != 0u) return false;
        uint kind = body_graph_node(argument.z).x;
        if (constant ? kind != 10u : !(kind == 1u || kind == 2u || kind == 3u || kind == 4u || kind == 9u)) return false;
    }
    return true;
}

#endif
