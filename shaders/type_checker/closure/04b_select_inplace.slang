// Select the in-place instantiations of an original job (inplace_read.slang):
// one lane per closure instance, after the export.
//
// A function is instantiated in place when the closure proves that its one
// instance is the only environment its body is ever lowered under:
// - it is a top-level function outside the unit's interface, so no other
//   unit names it and every call to it is a call row of this job;
// - 01_mark saw each of those calls in a nongeneric function with a
//   complete closed environment (it blocks the callee of every other call),
//   so the instances of the function are exactly its distinct environments;
// - it has one instance, exported as checked rows: concrete type operands
//   and constant atoms.
// 01_mark also blocks a function that itself calls a generic body, and 03c
// one whose bound-member call routes to a generic implementation or to
// none: their bodies wait for the replays, which patch such calls.
//
// The first lane to claim a function publishes its instance; a second
// instance blocks the function. Readers run in later dispatches.
import hir_records;
import type_checker.closure.instance_closure;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> interface_public_decl_index_by_hir;
RWStructuredBuffer<uint> instance_inplace_owner;
RWStructuredBuffer<uint> instance_inplace_counts;

static const uint INVALID = 0xffffffffu;
static const uint INPLACE_BLOCKED = 0x80000000u;
static const uint HIR_FILE = 1u;
static const uint HIR_ITEM = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_IMPL = 35u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint EXPORT_DONE = 1u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

// A generic function declared at file level whose parameters are all its
// own, and which the unit's interface does not name (a public function, or
// a private one a public template reaches, has an interface index).
bool private_top_level_function(uint row)
{
    if (compact_hir_core[row].kind != HIR_FN || compact_hir_payload[row].a != HIR_ITEM_KIND_FN ||
        compact_generic_param_ranges[row].count == 0u ||
        interface_public_decl_index_by_hir[row] != INVALID) return false;
    uint node = compact_hir_core[row].parent;
    for (uint depth = 0u; depth < hir_count() && node < hir_count(); depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_FILE) return true;
        if (kind == HIR_IMPL || kind == HIR_FN || compact_generic_param_ranges[node].count != 0u ||
            (kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT)) return false;
        uint parent = compact_hir_core[node].parent;
        if (parent >= node) break;
        node = parent;
    }
    return false;
}

// Every argument is a concrete type row or scalar, or a constant atom.
bool closed_arguments(uint4 extra)
{
    uint types = extra.w >> 16u;
    uint arity = extra.w & 0xffffu;
    uint rows; uint stride;
    instance_closure_refs.GetDimensions(rows, stride);
    if (types > arity || extra.x >= rows || arity > rows - extra.x) return false;
    for (uint index = 0u; index < arity; index++)
    {
        uint2 operand = instance_closure_refs[extra.x + index];
        if (index < types ? (operand.x != 1u && operand.x != 3u) : operand.x != 1u) return false;
        if (operand.y == INVALID) return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = dtid.x + dtid.y * 16776960u;
    if (index >= min(instance_closure_counts[IC_COUNT_LENGTH], ic_instance_capacity())) return;
    uint4 instance = instance_closure_instances[2u * index];
    uint callee = instance.y;
    uint rows; uint stride;
    instance_inplace_owner.GetDimensions(rows, stride);
    // An instance of a dependency's summary function names no local row.
    if (callee >= hir_count() || callee >= rows) return;
    uint4 extra = instance_closure_instances[2u * index + 1u];
    uint ignored;
    // A full table or an unexpanded frontier may hide another instance.
    bool selected = instance_closure_counts[IC_COUNT_FLAGS] == 0u && instance.z == 1u &&
        extra.z == EXPORT_DONE && all(instance_closure_targets[index] == uint4(INVALID, INVALID, INVALID, INVALID)) &&
        private_top_level_function(callee) && closed_arguments(extra);
    if (selected)
    {
        uint previous;
        InterlockedCompareExchange(instance_inplace_owner[callee], 0u, index + 1u, previous);
        selected = previous == 0u;
    }
    if (!selected)
    {
        InterlockedOr(instance_inplace_owner[callee], INPLACE_BLOCKED, ignored);
        return;
    }
    InterlockedAdd(instance_inplace_counts[0u], 1u, ignored);
}
