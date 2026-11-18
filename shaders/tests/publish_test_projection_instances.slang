// Test producer of explicit projection instances
// (docs/compiler-retained-projection.md, "Producer contract"). Discovery is
// the production producer; this kernel stands in for it in tests. It
// writes instance records, routes and the readiness record on the GPU from
// retained uses and substitution results; the host only sequences the modes
// and reads the rank counter between levels.
//
// fx_config: (mode, a, b, slot mask, run, generation flags, ...)
// fx_out: [0] ranks, [1] routes, [2] overflow, [3] roots found,
//         [64 ..64+S) identity slots (closed ENV TermId; the ENV's owner
//         word is the callee DeclId, so the ENV alone is the identity),
//         [64+S ..64+2S) rank + 1 of the slot.
//
// Modes:
//  0 roots: one lane per retained use. A DIRECT use inside a nongeneric
//    body (no segment) of library `a` whose callee has a body and whose
//    environment is closed is a discovery root; a root without parameters
//    is flagged ENTRY when `b` is 1.
//  1 requests: one lane per rank in [a, b). Each DIRECT use whose callee is
//    a committed FREE_FN with a body requests its environment u1.x under
//    the rank's (DeclId, ENV), tagged rank << 12 | use.
//  2 insert: one lane per request. A current OK result is the callee's
//    closed ENV; a new identity gets the next rank.
//  3 routes: one lane per request. The use's route names the callee rank.
//  4 readiness: one lane.
//  5 clears the request count: one lane.
//  6 writes an explicit readiness header for boundary fault tests.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_results;

RWStructuredBuffer<uint> fx_config;
globallycoherent RWStructuredBuffer<uint> fx_out;
RWStructuredBuffer<uint4> pj_instances;
RWStructuredBuffer<uint4> pj_routes;
RWStructuredBuffer<uint4> pj_readiness;
RWStructuredBuffer<uint4> sb_requests;
globallycoherent RWStructuredBuffer<uint> sb_request_count;

static const uint DIR_FREE_FN = 1u;
static const uint USE_DIRECT = 1u;
static const uint SLOTS = 64u;
static const uint NATIVE_LIBRARY = 0xfffffffeu;
static const uint NATIVE_NS_INSTANCE = 0xffff0002u;
static const uint ROUTE_NONE = 0xffffffffu;

uint slot_count() { return fx_config[3] + 1u; }

uint entry_of(uint decl)
{
    uint n; uint s;
    rt_decl_def.GetDimensions(n, s);
    if (decl == 0u || decl >= n || rt_decl_def[decl] == 0u) return RT_INVALID;
    uint entry = rt_decl_def[decl] - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    if (d0.x != decl || d0.y != DIR_FREE_FN || d0.w != RT_DIR_COMMITTED || d2.x == RT_INVALID) return RT_INVALID;
    return entry;
}

void create(uint slot, uint decl, uint env, uint flags)
{
    uint entry = entry_of(decl);
    uint uses = rt_dir[entry * RT_DIR_WORDS + 3u].x;
    uint rank; uint routes;
    InterlockedAdd(fx_out[0], 1u, rank);
    InterlockedAdd(fx_out[1], uses, routes);
    uint n; uint s;
    pj_instances.GetDimensions(n, s);
    uint m; pj_routes.GetDimensions(m, s);
    if (2u * rank + 2u > n || routes + uses > m)
    {
        InterlockedOr(fx_out[2], 1u);
        return;
    }
    uint generation = rt_counts[RT_C_GENERATION];
    pj_instances[2u * rank] = uint4(decl, env, generation, flags);
    pj_instances[2u * rank + 1u] = uint4(routes, uses, 0u, 0u);
    for (uint k = 0u; k < uses; k++) pj_routes[routes + k] = uint4(ROUTE_NONE, 0u, 0u, generation);
    fx_out[SLOTS + slot_count() + slot] = rank + 1u;
}

uint hash(uint env) { return (env * 2654435761u) & fx_config[3]; }

void insert(uint decl, uint env, uint flags)
{
    uint slot = hash(env);
    for (uint probe = 0u; probe < slot_count(); probe++)
    {
        uint previous;
        InterlockedCompareExchange(fx_out[SLOTS + slot], 0u, env, previous);
        if (previous == 0u)
        {
            create(slot, decl, env, flags);
            return;
        }
        if (previous == env) return;
        slot = (slot + 1u) & fx_config[3];
    }
    InterlockedOr(fx_out[2], 2u);
}

uint rank_of(uint env)
{
    uint slot = hash(env);
    for (uint probe = 0u; probe < slot_count(); probe++)
    {
        uint key = fx_out[SLOTS + slot];
        if (key == env) return fx_out[SLOTS + slot_count() + slot] - 1u;
        if (key == 0u) return RT_INVALID;
        slot = (slot + 1u) & fx_config[3];
    }
    return RT_INVALID;
}

// The callee and closed ENV of request `q`, or false.
bool resolved(uint q, out uint rank, out uint use, out uint callee, out uint env)
{
    rank = 0u; use = 0u; callee = 0u; env = RT_INVALID;
    if (q >= sb_request_count[0u] || !sb_result_current(fx_config[4], q)) return false;
    uint4 r0 = sb_results[q * SB_RESULT_WORDS];
    uint tag = sb_requests[q].w;
    rank = tag >> 12u;
    use = tag & 0xfffu;
    uint4 i0 = pj_instances[2u * rank];
    uint entry = rt_decl_def[i0.x] - 1u;
    uint first = rt_dir[entry * RT_DIR_WORDS + 2u].w;
    callee = rt_uses[(first + use) * RT_USE_WORDS].w;
    env = r0.x;
    return r0.y == SB_OK && rt_is_stored_term(env) && rt_term_kind(env) == RT_KIND_ENV && rt_term_closed(env) &&
        rt_term_words(env).x == callee;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x;
    uint mode = fx_config[0];
    if (mode == 6u)
    {
        if (lane == 0u) pj_readiness[0u] = uint4(fx_config[1], fx_config[2], fx_config[3], fx_config[4]);
        return;
    }
    if (mode == 0u)
    {
        if (lane >= rt_counts[RT_A_USES]) return;
        uint4 u0 = rt_uses[lane * RT_USE_WORDS];
        uint4 u1 = rt_uses[lane * RT_USE_WORDS + 1u];
        uint owner = u0.x;
        uint n; uint s;
        rt_decl_def.GetDimensions(n, s);
        if (owner == 0u || owner >= n || rt_decl_def[owner] == 0u || rt_decl_key[owner].x != fx_config[1]) return;
        uint owner_entry = rt_decl_def[owner] - 1u;
        if (rt_dir[owner_entry * RT_DIR_WORDS + 2u].x != RT_INVALID) return;
        uint callee = u0.w;
        uint entry = entry_of(callee);
        if ((u0.z & 0xffu) != USE_DIRECT || entry == RT_INVALID) return;
        uint env = u1.x;
        if (!rt_is_stored_term(env) || rt_term_kind(env) != RT_KIND_ENV || !rt_term_closed(env) ||
            rt_term_words(env).x != callee)
            return;
        uint params = rt_dir[entry * RT_DIR_WORDS + 1u].w;
        InterlockedAdd(fx_out[3], 1u);
        insert(callee, env, params == 0u ? fx_config[2] : 0u);
        return;
    }
    if (mode == 1u)
    {
        uint rank = fx_config[1] + lane;
        if (rank >= fx_config[2]) return;
        uint4 i0 = pj_instances[2u * rank];
        uint entry = rt_decl_def[i0.x] - 1u;
        uint first = rt_dir[entry * RT_DIR_WORDS + 2u].w;
        uint uses = rt_dir[entry * RT_DIR_WORDS + 3u].x;
        for (uint k = 0u; k < uses; k++)
        {
            uint4 u0 = rt_uses[(first + k) * RT_USE_WORDS];
            uint4 u1 = rt_uses[(first + k) * RT_USE_WORDS + 1u];
            if ((u0.z & 0xffu) != USE_DIRECT || entry_of(u0.w) == RT_INVALID || !rt_is_term(u1.x)) continue;
            uint capacity; uint stride;
            sb_requests.GetDimensions(capacity, stride);
            uint at;
            InterlockedAdd(sb_request_count[0u], 1u, at);
            if (at >= capacity) { InterlockedOr(fx_out[2], 4u); continue; }
            sb_requests[at] = uint4(i0.x, i0.y, u1.x, (rank << 12u) | k);
        }
        return;
    }
    if (mode == 2u || mode == 3u)
    {
        uint rank; uint use; uint callee; uint env;
        if (!resolved(lane, rank, use, callee, env))
        {
            if (lane < sb_request_count[0u]) InterlockedOr(fx_out[2], 8u);
            return;
        }
        if (mode == 2u)
        {
            insert(callee, env, 0u);
            return;
        }
        uint target = rank_of(env);
        if (target == RT_INVALID) { InterlockedOr(fx_out[2], 16u); return; }
        uint4 q1 = pj_instances[2u * rank + 1u];
        pj_routes[q1.x + use] = uint4(NATIVE_LIBRARY, NATIVE_NS_INSTANCE, target, rt_counts[RT_C_GENERATION]);
        return;
    }
    if (mode == 5u && lane == 0u)
    {
        sb_request_count[0u] = 0u;
        return;
    }
    if (mode == 4u && lane == 0u)
        pj_readiness[0u] = uint4(rt_counts[RT_C_GENERATION], 1u, fx_out[0], fx_out[1]);
}
