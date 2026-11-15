import type_checker.retention.discovery.dg_common;
import type_checker.retention.substitution.sb_consumer;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane = dg_lane(id);
    if (lane >= sb_counts[SB_C_REQUESTS]) return;
    uint4 m = dg_req_meta[lane];
    if (!sb_result_current(dg_config[5],lane)) { dg_fail(m.x,m.y,m.z,5u,0u); return; }
    uint4 r = sb_results[lane * SB_RESULT_WORDS];
    if (r.y != SB_OK) { dg_fail(m.x,m.y,m.z,6u,r.y); return; }
    uint callee = rt_uses[m.z * RT_USE_WORDS].w;
    if (rt_term_kind(r.x) != RT_KIND_ENV || !rt_term_closed(r.x) || rt_term_words(r.x).x != callee)
    { dg_fail(m.x,m.y,m.z,6u,SB_ENV); return; }
    uint entry=dg_entry(callee);
    if (entry!=RT_INVALID && rt_dir[entry*RT_DIR_WORDS].y==3u) return; // solver-selected route follows
    uint instance = dg_insert(callee,r.x,m.x,m.y,m.z);
    if (instance == RT_INVALID) return;
    uint4 route = uint4(1u,instance,0u,dg_config[15]);
    if (m.x != 0u) dg_roots[m.y] = route; else { dg_edges[m.y] = route; dg_targets[m.y]=uint2(callee,r.x); }
}
