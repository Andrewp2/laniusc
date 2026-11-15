// Projection step 0: one lane per rank. Validates the instance record
// against the readiness record, the store build and the callable's
// committed directory entry, inserts its identity (DeclId, ENV) into the
// identity table (a second rank with one identity is DUPLICATE), and writes
// the rank's plan (pj_info) and its counts (pj_base, scanned by step 1). A
// rank that fails contributes no rows.
import type_checker.retention.projection.pj_common;

globallycoherent RWStructuredBuffer<uint> pj_identity;

static const uint DIR_FREE_FN = 1u;

uint fnv(uint h, uint v)
{
    for (uint b = 0u; b < 4u; b++) h = (h ^ ((v >> (8u * b)) & 0xffu)) * 16777619u;
    return h;
}

// The rank that already holds (decl, env), or RT_INVALID after inserting
// `rank`. A full table counts an overflow.
uint identity_insert(uint rank, uint decl, uint env)
{
    uint slots; uint s;
    pj_identity.GetDimensions(slots, s);
    uint mask = slots - 1u;
    uint slot = fnv(fnv(2166136261u, decl), env) & mask & pj_config[PJ_CFG_IDENTITY_MASK];
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint previous;
        InterlockedCompareExchange(pj_identity[slot], 0u, rank + 1u, previous);
        if (previous == 0u) return RT_INVALID;
        uint4 other = pj_instances[(previous - 1u) * PJ_INSTANCE_WORDS];
        if (other.x == decl && other.y == env) return previous - 1u;
        slot = (slot + 1u) & mask;
    }
    InterlockedOr(pj_status[PJ_S_IDENTITY_OVERFLOW], 1u);
    return RT_INVALID;
}

void fail(uint rank, uint code, uint detail)
{
    pj_errors[rank] = uint4(code, detail, 0u, 0u);
    InterlockedAdd(pj_status[PJ_S_ERRORS], 1u);
    InterlockedMin(pj_status[PJ_S_ERROR_RANK], rank);
    for (uint c = 0u; c < PJ_COLUMNS; c++) pj_base[rank * PJ_COLUMNS + c] = 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint rank = pj_lane(dtid);
    uint count = pj_instance_count();
    if (rank >= count) return;
    if (rank == 0u)
    {
        pj_status[PJ_S_INSTANCES] = count;
        pj_status[PJ_S_GENERATION] = rt_counts[RT_C_GENERATION];
    }
    for (uint w = 0u; w < PJ_INFO_WORDS; w++) pj_info[rank * PJ_INFO_WORDS + w] = uint4(0u, 0u, 0u, 0u);
    pj_errors[rank] = uint4(0u, 0u, 0u, 0u);

    uint4 ready = pj_readiness[0u];
    uint generation = rt_counts[RT_C_GENERATION];
    if ((ready.y & PJ_READY_ROUTES) == 0u || ready.x != generation || generation == 0u ||
        rt_counts[RT_C_READY] == 0u)
    {
        fail(rank, PJ_E_READINESS, ready.y);
        return;
    }
    uint4 q0 = pj_instances[rank * PJ_INSTANCE_WORDS];
    uint4 q1 = pj_instances[rank * PJ_INSTANCE_WORDS + 1u];
    uint decl = q0.x;
    uint env = q0.y;
    if (q0.z != generation || (q0.w & ~PJ_FLAG_ENTRY) != 0u ||
        !rt_is_stored_term(env) || rt_term_kind(env) != RT_KIND_ENV || !rt_term_closed(env) ||
        rt_term_words(env).x != decl)
    {
        fail(rank, PJ_E_RECORD, 0u);
        return;
    }
    uint entry = pj_dir_entry(decl);
    if (entry == RT_INVALID)
    {
        fail(rank, PJ_E_DECL, 0u);
        return;
    }
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    if (d0.x != decl || d0.y != DIR_FREE_FN || d0.w != RT_DIR_COMMITTED || d3.w != 0u ||
        d2.x == RT_INVALID)
    {
        fail(rank, PJ_E_DECL, d0.y | (d3.w << 8u));
        return;
    }
    if (q1.y != d3.x || q1.x > pj_route_count() || q1.y > pj_route_count() - q1.x)
    {
        fail(rank, PJ_E_ROUTES, q1.y);
        return;
    }
    if ((q0.w & PJ_FLAG_ENTRY) != 0u && d1.w != 0u)
    {
        fail(rank, PJ_E_ENTRY, d1.w);
        return;
    }
    uint other = identity_insert(rank, decl, env);
    if (other != RT_INVALID)
    {
        // Both ranks of one identity fail; each lane reports its own.
        fail(rank, PJ_E_DUPLICATE, other);
        return;
    }

    uint segment = d2.x;
    uint4 s0 = rt_segments[segment * RT_SEG_WORDS + 0u];
    uint4 s1 = rt_segments[segment * RT_SEG_WORDS + 1u];
    uint4 s2 = rt_segments[segment * RT_SEG_WORDS + 2u];
    uint4 s4 = rt_segments[segment * RT_SEG_WORDS + 4u];
    uint base = rank * PJ_INFO_WORDS;
    pj_info[base + 0u] = uint4(decl, env, entry, segment);
    pj_info[base + 1u] = uint4(s0.z, s2.w, d1.w, d3.x);
    pj_info[base + 2u] = s1;
    pj_info[base + 3u] = uint4(s2.xyz, d1.z);
    pj_info[base + 4u] = uint4(s0.y, s0.w, d2.w, q0.w);
    pj_info[base + 5u] = s4;

    uint b = rank * PJ_COLUMNS;
    pj_base[b + PJ_C_ROWS] = s0.z;
    pj_base[b + PJ_C_TOKENS] = s2.w;
    pj_base[b + PJ_C_SIDE + 0u] = s1.x;
    pj_base[b + PJ_C_SIDE + 1u] = s1.y;
    pj_base[b + PJ_C_SIDE + 2u] = s1.z;
    pj_base[b + PJ_C_SIDE + 3u] = s1.w;
    pj_base[b + PJ_C_SIDE + 4u] = s2.x;
    pj_base[b + PJ_C_SIDE + 5u] = s2.y;
    pj_base[b + PJ_C_SIDE + 6u] = s2.z;
    pj_base[b + PJ_C_REQUESTS] = 1u + d1.w + s0.z + 2u * d3.x;
    InterlockedMax(pj_status[PJ_S_MAX_ROWS], s0.z);
    InterlockedMax(pj_status[PJ_S_MAX_TOKENS], s2.w);
    InterlockedMax(pj_status[PJ_S_MAX_SIDE], max(max(max(s1.x, s1.y), max(s1.z, s1.w)), max(max(s2.x, s2.y), s2.z)));
}
