// Debug validation of the canonical table (LANIUS_DEBUG_VALIDATE_CANONICAL=1),
// step 1 of 3: uniqueness and facts, without the previous graph walker.
// Per slot: the published record's facts recompute from its key and its
// children, its probe chain is unbroken, and no equal record precedes it.
// Per candidate: nothing is pending and every stored reference is published.
// Per dependency node: the same, for the nodes of every page of the job.
// Counter layout: CANONICAL_VALIDATION_COUNTERS in canonical_passes.rs.
import type_checker.canonical.canonical_api;

RWStructuredBuffer<uint> canonical_validation;
// Bucket chains of the cross-check (canonical_crosscheck.slang), cleared here.
RWStructuredBuffer<uint> canonical_crosscheck_links;

static const uint V_UNKNOWN_ROWS = 2u;
static const uint V_RESOLVED_ROWS = 3u;
static const uint V_DUPLICATES = 4u;
static const uint V_BROKEN = 5u;
static const uint V_FACTS = 6u;
static const uint V_UNPUBLISHED = 7u;
static const uint V_PENDING = 8u;
static const uint V_LIVE = 9u;
static const uint V_UNKNOWN_CONSTANTS = 10u;
static const uint V_RESOLVED_CONSTANTS = 11u;
static const uint V_OVERFLOW = 12u;
static const uint V_ROUNDS = 13u;
// After the witness pairs (90_validate).
static const uint V_UNKNOWN_DEPENDENCY = 36u;
static const uint V_RESOLVED_DEPENDENCY = 37u;

void count(uint word)
{
    InterlockedAdd(canonical_validation[word], 1u);
}

bool records_equal(uint a, uint b)
{
    if (any(ct_head[a] != ct_head[b])) return false;
    uint arity = ct_arity(a);
    for (uint i = 0u; i < arity; i++)
        if (ct_arg(a, i) != ct_arg(b, i)) return false;
    return true;
}

bool facts_consistent(uint record)
{
    uint4 head = ct_head[record];
    CtKey key = ct_key_begin(head.x & 0xffu, (head.x >> 8u) & 0xffu, head.x >> 16u, head.yzw);
    uint arity = ct_arity(record);
    for (uint i = 0u; i < arity; i++) ct_key_fold(key, ct_arg(record, i));
    uint4 meta = ct_meta[record];
    return key.ok && all(meta.zw == key.shash) &&
        (meta.y & 0xffffu) == min(key.height + 1u, 0xffffu) && (meta.y >> 16u) == key.flags;
}

void validate_slot(uint slot)
{
    uint record = ct_slot[slot];
    if (record == 0u) return;
    count(V_LIVE);
    if (record < CT_FIRST_RECORD || record >= ct_counts[CT_COUNT_NEXT_RECORD])
    {
        count(V_FACTS);
        return;
    }
    if (!facts_consistent(record)) count(V_FACTS);
    uint slots = ct_slot_capacity();
    uint probe = ct_probe_start(ct_meta[record].zw);
    for (uint step = 0u; step < slots && probe != slot; step++)
    {
        uint other = ct_slot[probe];
        if (other == 0u) { count(V_BROKEN); return; }
        if (records_equal(other, record)) { count(V_DUPLICATES); return; }
        probe = (probe + 1u) & (slots - 1u);
    }
}

bool is_published(uint record)
{
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

void validate_candidate(uint candidate)
{
    uint state = ct_candidate_state(candidate);
    bool row = candidate < ct_row_capacity();
    if (state == CT_NONE) return;
    if (state == CT_PENDING) count(V_PENDING);
    if (!ct_is_resolved(state))
    {
        count(row ? V_UNKNOWN_ROWS : V_UNKNOWN_CONSTANTS);
        return;
    }
    count(row ? V_RESOLVED_ROWS : V_RESOLVED_CONSTANTS);
    if (ct_is_stored(state) && !is_published(state)) count(V_UNPUBLISHED);
}

// Entries no page reached stay pending (the buffer may exceed the job's span).
void validate_dependency(uint index)
{
    uint state = canonical_dependency_type[index];
    if (state == CT_PENDING) return;
    if (!ct_is_resolved(state))
    {
        count(V_UNKNOWN_DEPENDENCY);
        return;
    }
    count(V_RESOLVED_DEPENDENCY);
    if (ct_is_stored(state) && !is_published(state)) count(V_UNPUBLISHED);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (i < ct_slot_capacity()) validate_slot(i);
    if (i < ct_candidate_count()) validate_candidate(i);
    if (i < ct_dependency_capacity()) validate_dependency(i);
    uint links; uint stride;
    canonical_crosscheck_links.GetDimensions(links, stride);
    if (i < links) canonical_crosscheck_links[i] = 0u;
    if (i == 0u)
    {
        canonical_validation[V_OVERFLOW] = ct_counts[CT_COUNT_OVERFLOW];
        canonical_validation[V_ROUNDS] = ct_counts[CT_COUNT_ROUND];
    }
}
