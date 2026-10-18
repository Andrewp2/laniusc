// Stress gate for single-dispatch lock-free interning (canonical_api.slang).
// mode 0: every lane interns a nested chain whose keys are heavily shared
// with other lanes, building each parent from the IDs returned for its
// children. mode 1: validate uniqueness, structure and published facts.
import type_checker.canonical.canonical_api;
import primitive_types;

struct Params
{
    uint lanes;
    uint distinct;
    uint seed;
    uint mode;
};
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> stress_result;
// [0] duplicate keys, [1] broken probe chains, [2] wrong structure,
// [3] wrong facts, [4] unpublished results, [5] live records,
// [6] failed interns.
RWStructuredBuffer<uint> stress_errors;

uint mix32(uint x)
{
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    return x ^ (x >> 16u);
}

uint lane_chain(uint lane)
{
    // Even seeds place equal chains in one wave, odd seeds spread them.
    uint group = (gParams.seed & 1u) != 0u ? lane % gParams.distinct
        : (lane / max(gParams.lanes / gParams.distinct, 1u));
    return mix32(group ^ (gParams.seed * 0x9e3779b9u));
}

uint chain_depth(uint chain) { return 1u + chain % 12u; }
uint level_shape(uint chain, uint level) { return (chain >> (2u * (level % 14u))) & 3u; }
uint level_arity(uint level) { return 3u + level % 4u; }

uint leaf_value(uint chain) { return chain % 61u; }

uint intern_leaf(uint value, inout uint spare)
{
    return ct_intern_small(CC_KIND_VALUE, 0u, uint3(SCALAR_U32, value, 0u), uint2(0u, 0u),
        uint2(value, CT_NONE), spare);
}

// Wide operand i of a named level: the previous level, or a shared leaf.
uint named_operand(uint previous, uint level, uint index, inout bool ok, inout uint spare)
{
    if (index % 2u == 0u) return previous;
    uint leaf = intern_leaf((level * 7u + index) % 5u, spare);
    if (!ct_is_resolved(leaf)) ok = false;
    return leaf;
}

void intern_chain(uint lane)
{
    uint chain = lane_chain(lane);
    // One lane-owned spare record bounds allocation to live records + lanes.
    uint spare = CT_NONE;
    uint id = intern_leaf(leaf_value(chain), spare);
    for (uint level = 1u; level <= chain_depth(chain) && ct_is_resolved(id); level++)
    {
        uint shape = level_shape(chain, level);
        if (shape == 0u)
            id = ct_intern_small(CT_KIND_SLICE, 1u, uint3(0u, 0u, 0u), uint2(id, 0u), uint2(0u, 0u), spare);
        else if (shape == 1u)
        {
            uint count = cc_intern_count(level % 3u, spare);
            id = ct_is_resolved(count) ? ct_intern_small(CT_KIND_ARRAY, 2u, uint3(0u, 0u, 0u),
                uint2(id, count), uint2(0u, 0u), spare) : CT_UNKNOWN;
        }
        else if (shape == 2u)
        {
            uint arity = level_arity(level);
            CtKey key = ct_key_begin(CT_KIND_NAMED, arity, arity, uint3(1u, 2u, (chain >> level) & 3u));
            bool ok = ct_key_reserve_args(key);
            for (uint index = 0u; index < arity && ok; index++)
                ct_key_arg(key, index, named_operand(id, level, index, ok, spare));
            if (!ok) key.ok = false;
            id = ct_intern_spare(key, uint2(0xffffffffu, 0u), spare);
        }
        else
            id = ct_intern_small(CT_KIND_REF, 1u, uint3(0u, 0u, 0u), uint2(id, 0u), uint2(0u, 0u), spare);
    }
    if (!ct_is_resolved(id)) InterlockedAdd(stress_errors[6u], 1u);
    stress_result[lane] = id;
}

bool records_equal(uint a, uint b)
{
    if (any(ct_head[a] != ct_head[b])) return false;
    uint arity = ct_arity(a);
    for (uint i = 0u; i < arity; i++)
        if (ct_arg(a, i) != ct_arg(b, i)) return false;
    return true;
}

// Recompute a record's facts from its key and its children's facts.
bool facts_consistent(uint record)
{
    uint4 head = ct_head[record];
    CtKey key = ct_key_begin(head.x & 0xffu, (head.x >> 8u) & 0xffu, head.x >> 16u, head.yzw);
    for (uint i = 0u; i < ct_arity(record); i++) ct_key_fold(key, ct_arg(record, i));
    uint4 meta = ct_meta[record];
    return key.ok && all(meta.zw == key.shash) &&
        (meta.y & 0xffffu) == key.height + 1u && (meta.y >> 16u) == key.flags;
}

void validate_slot(uint slot)
{
    uint record = ct_slot[slot];
    if (record == 0u) return;
    InterlockedAdd(stress_errors[5u], 1u);
    if (!facts_consistent(record)) InterlockedAdd(stress_errors[3u], 1u);
    uint slots = ct_slot_capacity();
    uint probe = ct_probe_start(ct_meta[record].zw);
    for (uint step = 0u; step < slots && probe != slot; step++)
    {
        uint other = ct_slot[probe];
        if (other == 0u) { InterlockedAdd(stress_errors[1u], 1u); return; }
        if (records_equal(other, record)) { InterlockedAdd(stress_errors[0u], 1u); return; }
        probe = (probe + 1u) & (slots - 1u);
    }
}

bool is_published(uint record)
{
    if (record <= SCALAR_NEVER) return true;
    uint slots = ct_slot_capacity();
    uint probe = ct_probe_start(ct_meta[record].zw);
    for (uint step = 0u; step < slots; step++)
    {
        uint other = ct_slot[probe];
        if (other == record) return true;
        if (other == 0u) return false;
        probe = (probe + 1u) & (slots - 1u);
    }
    return false;
}

bool leaf_is(uint id, uint value)
{
    return ct_kind(id) == CC_KIND_VALUE && all(ct_words(id) == uint3(SCALAR_U32, value, 0u)) &&
        ct_arity(id) == 0u && cc_count(id) == value;
}

void validate_lane(uint lane)
{
    uint chain = lane_chain(lane);
    uint id = stress_result[lane];
    if (!ct_is_resolved(id)) return;
    if (!is_published(id)) { InterlockedAdd(stress_errors[4u], 1u); return; }
    uint depth = chain_depth(chain);
    if (ct_height(id) != depth + 1u) { InterlockedAdd(stress_errors[3u], 1u); return; }
    for (uint level = depth; level >= 1u; level--)
    {
        uint shape = level_shape(chain, level);
        uint kind = ct_kind(id);
        bool ok;
        if (shape == 0u) ok = kind == CT_KIND_SLICE && ct_arity(id) == 1u;
        else if (shape == 1u)
        {
            uint count = ct_arg(id, 1u);
            ok = kind == CT_KIND_ARRAY && ct_arity(id) == 2u && ct_kind(count) == CC_KIND_COUNT &&
                ct_words(count).x == level % 3u;
        }
        else if (shape == 2u)
        {
            uint arity = level_arity(level);
            ok = kind == CT_KIND_NAMED && ct_arity(id) == arity && ct_type_slots(id) == arity &&
                all(ct_words(id) == uint3(1u, 2u, (chain >> level) & 3u));
            for (uint index = 0u; index < arity && ok; index++)
            {
                uint operand = ct_arg(id, index);
                ok = index % 2u == 0u ? operand == ct_arg(id, 0u)
                    : leaf_is(operand, (level * 7u + index) % 5u);
            }
        }
        else ok = kind == CT_KIND_REF && ct_arity(id) == 1u;
        if (!ok) { InterlockedAdd(stress_errors[2u], 1u); return; }
        id = ct_arg(id, 0u);
    }
    if (!leaf_is(id, leaf_value(chain))) InterlockedAdd(stress_errors[2u], 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (gParams.mode == 0u)
    {
        if (i < gParams.lanes) intern_chain(i);
        return;
    }
    if (i < ct_slot_capacity()) validate_slot(i);
    if (i < gParams.lanes) validate_lane(i);
}
