import primitive_types;
// Shared bounded interpreter and exact graph fixtures for the static matcher
// operation-family entries. This file has no entrypoint. The selected family's
// operation method is its only route to production matcher APIs.
import type_checker.owned_type_constraint_engine;
import type_checker.owned_type_constraint_contract;
import thread_scratch;

RWStructuredBuffer<uint4> results;
StructuredBuffer<uint2> fixture_ranges;
// Each entry receives only its disjoint host-checked set of original case IDs.
StructuredBuffer<uint> fixture_case_ids;
// Two uint4 rows per instruction: (opcode,a,b,c), (d,0,0,0).
StructuredBuffer<uint4> fixture_ops;
static const uint INVALID = 0xffffffffu;

// Atom identity is owner + domain + ordinal. Distinct owners deliberately use
// the same dense ordinal, and all three graph adapters share these exact atoms.
bool parameter_key(uint atom, out uint owner, out uint domain, out uint ordinal)
{
    owner = INVALID; domain = 0u; ordinal = 0u;
    if (atom == 20u) owner = 10u;
    else if (atom == 21u || atom == 22u) { owner = 11u; ordinal = atom - 21u; }
    else if (atom == 23u) owner = 12u;
    else if (atom == 30u) { owner = 12u; domain = 1u; }
    else if (atom == 31u) { owner = 13u; domain = 1u; }
    else if (atom == 24u) owner = 15u;
    else if (atom == 40u) owner = 20u;
    else if (atom == 41u) owner = 21u;
    else if (atom == 42u) { owner = 21u; domain = 1u; }
    else if (atom == 43u || atom == 44u) { owner = 22u; ordinal = atom - 43u; }
    else if (atom == 50u) owner = 30u;
    else if (atom >= 64u && atom < 128u)
    { owner = 16u; domain = atom < 96u ? 0u : 1u; ordinal = (atom - 64u) % 32u; }
    return owner != INVALID;
}

bool parameter_valid(uint atom, bool constant)
{
    uint owner; uint domain; uint ordinal;
    return parameter_key(atom, owner, domain, ordinal) && domain == (constant ? 1u : 0u);
}

bool inventory(uint owner, bool constant, out uint count)
{
    count = 0u;
    if (owner == 16u) { count = 32u; return true; }
    if (owner == 17u) { count = constant ? 0u : 33u; return true; }
    if (owner == 14u) return true;
    if (owner == 13u) { count = constant ? 1u : 0u; return true; }
    if (owner == 12u || owner == 21u) { count = 1u; return true; }
    if (owner == 11u || owner == 22u) { count = constant ? 0u : 2u; return true; }
    if (owner == 10u || owner == 15u || owner == 20u || owner == 30u)
    { count = constant ? 0u : 1u; return true; }
    return false;
}

uint classify(uint selected_owner, uint atom, bool constant, out uint index)
{
    uint owner; uint domain; uint ordinal; uint count;
    index = INVALID;
    if (!inventory(selected_owner, constant, count) ||
        !parameter_key(atom, owner, domain, ordinal) || domain != (constant ? 1u : 0u))
        return OWNED_PARAMETER_INVALID;
    if (owner != selected_owner) return OWNED_PARAMETER_RIGID;
    if (ordinal >= count) return OWNED_PARAMETER_INVALID;
    index = ordinal;
    return OWNED_PARAMETER_BINDABLE;
}

// Graph namespaces deliberately collide: e.g. left node1=Box<T>, goal
// node1=Box<i32>. A stored goal node1 must never be traversed as left node1.
uint kind(uint side, uint node)
{
    if (node >= 17u) return INVALID;
    if (node == 2u || node == 16u || (side == 1u && node == 9u) || (side == 2u && node == 7u)) return 2u;
    if (node == 3u || node == 11u || (side != 2u && node == 5u)) return 4u;
    if ((side != 2u && node == 4u) || node == 12u || (side == 2u && node == 5u)) return 3u;
    return 1u;
}

uint arity(uint side, uint node)
{
    if (node == 13u) return 33u; // malformed application shape, independent of owned inventory
    return node == 0u || node == 6u || node == 10u ? 2u : 1u;
}

uint2 edge(uint side, uint node, uint slot)
{
    if (side == 0u)
    {
        if (node == 0u) return uint2(2u, 20u);
        if (node == 1u || node == 3u || node == 4u || node == 16u) return uint2(2u, 20u);
        if (node == 2u) return slot == 0u ? uint2(2u, 23u) : uint2(0x80000002u, 30u);
        if (node == 5u) return uint2(3u, 5u);
        if (node == 6u) return slot == 0u ? uint2(2u, 20u) : uint2(1u, 4u);
        if (node == 7u) return uint2(2u, 21u);
        if (node == 8u || node == 9u) return uint2(1u, 4u);
        if (node == 10u) return uint2(2u, 21u + slot);
        if (node == 11u) return uint2(2u, 50u);
        if (node == 12u) return uint2(0x80000001u, 4u);
        if (node == 14u) return uint2(0x80000002u, 31u);
        return uint2(1u, 4u);
    }
    if (side == 1u)
    {
        if (node == 0u) return slot == 0u ? uint2(1u, 3u) : uint2(2u, 40u);
        if (node == 1u || node == 3u || node == 4u) return uint2(2u, 40u);
        if (node == 2u) return slot == 0u ? uint2(2u, 41u) : uint2(0x80000002u, 42u);
        if (node == 5u) return uint2(3u, 5u);
        if (node == 7u) return uint2(2u, 43u);
        if (node == 8u) return uint2(2u, 44u);
        if (node == 10u) return uint2(2u, 43u + slot);
        if (node == 11u) return uint2(2u, 50u);
        return uint2(1u, 3u);
    }
    if (node == 0u) return uint2(1u, slot == 0u ? 4u : 3u);
    if (node == 4u) return uint2(2u, 20u);
    if (node == 6u || node == 15u) return uint2(1u, 3u);
    if (node == 8u) return uint2(3u, 1u);
    if (node == 9u) return uint2(0x80000001u, 4u);
    return uint2(1u, 4u);
}

uint probe_metadata(uint side, uint node, uint field)
{
    if (node >= 17u || field >= 10u) return INVALID;
    uint k = kind(side, node);
    if (field == 0u) return k;
    if (field == 1u) return k == 1u ? (arity(side, node) == 2u ? 61u : 60u) : INVALID;
    if (field == 2u) return k == 1u ? arity(side, node) : 0u;
    if (field == 3u) return edge(side, node, 0u).x;
    if (field == 4u) return edge(side, node, 0u).y;
    if (field == 5u && k == 2u) return node == 2u && side != 2u ? 2u : 1u;
    if (field == 6u && k == 2u)
    {
        if (node == 2u && side == 0u) return 30u;
        if (node == 2u && side == 1u) return 42u;
        return (side == 1u && node == 9u) || (side == 2u && node == 7u) ? 5u : 4u;
    }
    return INVALID;
}

bool probe_argument(uint side, uint node, uint slot, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    if (node >= 17u || kind(side, node) != 1u || slot >= arity(side, node)) return false;
    uint2 value = edge(side, node, slot); tag = value.x; payload = value.y; return true;
}

struct LeftGraph : IOwnedConstraintPatternGraph
{
    static bool constant_value(uint row, out uint3 value)
    { value = uint3(SCALAR_U32, row, 0u); return row != INVALID; }
    static uint constant_parameter_scalar(uint reference)
    { return parameter_valid(reference, true) ? SCALAR_U32 : 0u; }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { scalar = 0u; child = uint2(0u, INVALID); return false; }
    static uint metadata(uint node, uint field) { return probe_metadata(0u, node, field); }
    static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { return probe_argument(0u, node, slot, tag, payload); }
    static bool parameter_is_valid(uint atom, bool constant) { return parameter_valid(atom, constant); }
    static bool owner_parameter_count(uint owner, bool constant, out uint count)
    { return inventory(owner, constant, count); }
    static uint owned_parameter(uint owner, uint atom, bool constant, out uint index)
    { return classify(owner, atom, constant, index); }
}
struct RightGraph : IOwnedConstraintPatternGraph
{
    static bool constant_value(uint row, out uint3 value)
    { value = uint3(SCALAR_U32, row, 0u); return row != INVALID; }
    static uint constant_parameter_scalar(uint reference)
    { return parameter_valid(reference, true) ? SCALAR_U32 : 0u; }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { scalar = 0u; child = uint2(0u, INVALID); return false; }
    static uint metadata(uint node, uint field) { return probe_metadata(1u, node, field); }
    static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { return probe_argument(1u, node, slot, tag, payload); }
    static bool parameter_is_valid(uint atom, bool constant) { return parameter_valid(atom, constant); }
    static bool owner_parameter_count(uint owner, bool constant, out uint count)
    { return inventory(owner, constant, count); }
    static uint owned_parameter(uint owner, uint atom, bool constant, out uint index)
    { return classify(owner, atom, constant, index); }
}
struct GoalGraph : IConstraintMatchGraph
{
    static bool constant_value(uint row, out uint3 value)
    { value = uint3(SCALAR_U32, row, 0u); return row != INVALID; }
    static uint constant_parameter_scalar(uint reference)
    { return parameter_valid(reference, true) ? SCALAR_U32 : 0u; }
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { scalar = 0u; child = uint2(0u, INVALID); return false; }
    static uint metadata(uint node, uint field) { return probe_metadata(2u, node, field); }
    static bool argument(uint node, uint slot, out uint tag, out uint payload)
    { return probe_argument(2u, node, slot, tag, payload); }
    static bool parameter_is_valid(uint atom, bool constant) { return parameter_valid(atom, constant); }
}

static const uint OP_BEGIN_MATCH = 1u;
static const uint OP_MATCH = 2u;
static const uint OP_FINISH_MATCH = 3u;
static const uint OP_FIXED_MATCH = 4u;
static const uint OP_BEGIN_OVERLAP = 5u;
static const uint OP_OVERLAP = 6u;
static const uint OP_FINISH_OVERLAP = 7u;
static const uint OP_BEGIN_PATTERN = 8u;
static const uint OP_VISIT = 9u;
static const uint OP_FINISH_PATTERN = 10u;
static const uint OP_CHECK_BINDING = 11u;
static const uint OP_SET_LIMITS = 12u;

static const uint FIXTURE_MAX_OPERATIONS = 66u;

uint expected_state(uint id)
{
    if (id == 1u || id == 4u || id == 6u || id == 9u || id == 11u || id == 13u || id == 30u)
        return OWNED_CONSTRAINT_NO_MATCH;
    if (id == 7u || id == 14u || id == 17u || id == 18u || id == 26u || id == 31u)
        return OWNED_CONSTRAINT_INVALID_INPUT;
    if ((id >= 19u && id <= 22u) || id == 25u) return OWNED_CONSTRAINT_RESOURCE_LIMIT;
    return OWNED_CONSTRAINT_MATCHED;
}

bool final_invariant(uint id, inout OwnedConstraintState state)
{
    if (id == 8u)
        return state.bound.x == 1u && state.bound.z == 1u &&
            all(owned_constraint_binding_cell(state.frame, 0u).yz == uint2(1u, 3u)) &&
            all(owned_constraint_binding_cell(state.frame, 64u).yz == uint2(1u, 4u));
    if (id == 10u)
        return (state.bound.x == 1u && state.bound.z == 0u &&
            all(owned_constraint_binding_cell(state.frame, 0u) == uint4(1u, 2u, 40u, 0u))) ||
            (state.bound.x == 0u && state.bound.z == 1u &&
            all(owned_constraint_binding_cell(state.frame, 64u) == uint4(0u, 2u, 20u, 0u)));
    if (id == 11u) return state.bound.x == 1u && state.bound.z == 0u;
    if (id == 15u)
        return state.seen.x == 1u && state.seen.y == 1u &&
            all(state.bound == uint4(0u, 0u, 0u, 0u));
    if (id == 18u) return state.status.detail == 9u;
    if (id == 19u) return state.status.detail == 6u && state.work.pair_visits == 1u;
    if (id == 20u) return state.status.detail == 7u && state.work.occurs_visits == 0u;
    if (id == 21u) return state.status.detail == 8u;
    if (id == 22u) return state.status.detail == 5u && state.status.required == 2u;
    if (id == 24u) return state.seen.x == INVALID && state.seen.y == INVALID;
    if (id == 25u) return state.status.required == 33u && state.status.available == 32u;
    if (id == 30u) return state.bound.x == 0u;
    return true;
}

interface IOwnedFixtureOperations
{
    // Return instruction/invariant validity, not matcher success. Failed
    // matcher states must still receive the script's later API operations.
    static bool execute(uint opcode, uint4 args, OwnedConstraintLimits budget,
        inout OwnedConstraintState state);
}

void run_owned_fixture<Operations : IOwnedFixtureOperations>(uint lane)
{
    uint case_count; uint case_stride;
    fixture_case_ids.GetDimensions(case_count, case_stride);
    if (lane >= case_count) return;
    uint id = fixture_case_ids[lane]; if (id >= 32u) return;
    uint expected = expected_state(id);
    results[id] = uint4(0u, expected, 0u, 0u);
    uint ranges; uint stride; uint rows;
    fixture_ranges.GetDimensions(ranges, stride);
    fixture_ops.GetDimensions(rows, stride);
    if (id >= ranges || (rows & 1u) != 0u || thread_scratch_begin(lane) <= lane) return;
    uint2 span = fixture_ranges[id]; uint count = rows / 2u;
    if (span.y == 0u || span.y > FIXTURE_MAX_OPERATIONS ||
        span.x > count || span.y > count - span.x) return;
    OwnedConstraintLimits budget = {16u, 512u, 512u, 512u};
    OwnedConstraintState state = (OwnedConstraintState)0;
    bool started = false; bool invariant = true;
    [loop]
    for (uint step = 0u; step < span.y; step++)
    {
        uint row = (span.x + step) * 2u;
        uint4 first = fixture_ops[row]; uint4 second = fixture_ops[row + 1u];
        uint opcode = first.x; uint4 args = uint4(first.yzw, second.x);
        if (any(second.yzw != uint3(0u, 0u, 0u))) { invariant = false; break; }
        bool begins = opcode == OP_BEGIN_MATCH || opcode == OP_BEGIN_OVERLAP || opcode == OP_BEGIN_PATTERN;
        if ((begins && started) || (opcode == OP_SET_LIMITS && started) ||
            (!begins && opcode != OP_SET_LIMITS && !started))
        { invariant = false; break; }
        // Never stop because the matcher failed: case30 observes sticky failure
        // across the later match and finish operations in its exact sequence.
        if (opcode == OP_SET_LIMITS)
        {
            budget.depth = args.x; budget.pair_visits = args.y;
            budget.occurs_visits = args.z; budget.substitution_steps = args.w;
        }
        else
        {
            invariant = Operations.execute(opcode, args, budget, state);
            if (invariant && begins) started = true;
        }
        if (!invariant) break;
    }
    invariant = invariant && started && final_invariant(id, state);
    results[id] = uint4(state.status.state, expected, state.status.detail,
        state.status.state == expected && invariant ? 1u : 0u);
}
