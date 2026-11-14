// Request producer for retained substitution tests: one lane per committed
// use. A use whose callee another (library, unit) defines and whose
// environment is a closed ENV becomes requests under (callee, environment):
// the callee's declared result (kind 0) and parameters (kind 1), every
// resolved row term of its body segment (kind 2), and the environment
// (kind 3) and result (kind 4) of each use inside that body. Those inner
// environments are terms in the callee's scope, so substituting them is the
// discovery step to the next instance.
//
// fx_out at 16 + 4 * request: (use, kind, index, the use's checked result).
import type_checker.retention.retention_store;

RWStructuredBuffer<uint> fx_config;
RWStructuredBuffer<uint> fx_out;
RWStructuredBuffer<uint4> sb_requests;
globallycoherent RWStructuredBuffer<uint> sb_request_count;

void emit(uint use, uint kind, uint index, uint callee, uint env, uint term, uint expected)
{
    uint capacity; uint stride;
    sb_requests.GetDimensions(capacity, stride);
    uint at;
    InterlockedAdd(sb_request_count[0u], 1u, at);
    if (at >= capacity) return;
    sb_requests[at] = uint4(callee, env, term, (use << 12u) | (kind << 9u) | min(index, 511u));
    uint o = 16u + 4u * at;
    fx_out[o] = use;
    fx_out[o + 1u] = kind;
    fx_out[o + 2u] = index;
    fx_out[o + 3u] = expected;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint use = dtid.x;
    if (use >= rt_counts[RT_A_USES]) return;
    uint4 u0 = rt_uses[use * RT_USE_WORDS + 0u];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint callee = u0.w;
    if (callee == 0u || rt_decl_def[callee] == 0u) return;
    if (all(rt_decl_key[callee].xy == rt_decl_key[u0.x].xy)) return;
    if (!rt_is_stored_term(u1.x) || rt_term_kind(u1.x) != RT_KIND_ENV || !rt_term_closed(u1.x)) return;
    uint env = u1.x;
    uint entry = rt_decl_def[callee] - 1u;
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    emit(use, 0u, 0u, callee, env, rt_sigs[d1.z], u1.y);
    for (uint p = 0u; p < d1.w; p++) emit(use, 1u, p, callee, env, rt_sigs[d1.z + 1u + p], 0u);
    if (d2.x != RT_INVALID)
    {
        uint4 s0 = rt_segments[d2.x * RT_SEG_WORDS];
        for (uint row = 0u; row < s0.z; row++)
        {
            uint term = rt_seg_rows[(s0.y + row) * RT_ROW_WORDS + 3u].x;
            if (rt_is_resolved(term)) emit(use, 2u, row, callee, env, term, 0u);
        }
    }
    for (uint k = 0u; k < d3.x; k++)
    {
        uint4 i1 = rt_uses[(d2.w + k) * RT_USE_WORDS + 1u];
        if (rt_is_resolved(i1.x)) emit(use, 3u, k, callee, env, i1.x, 0u);
        if (rt_is_resolved(i1.y)) emit(use, 4u, k, callee, env, i1.y, 0u);
    }
}
