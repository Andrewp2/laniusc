import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.substitution.retained_substitution_layout;
public void note_unpublished_requests()
{
    if (dg_config[8] != 0u) dg_status[10] = 11u;
}

public void resolve_discovery_request(uint lane, uint4 r, bool current)
{
    uint4 m = dg_req_meta[lane];
    if (!current) { dg_fail(m.x,m.y,m.z,5u,0u); return; }
    if (r.y != SB_OK) { dg_fail(m.x,m.y,m.z,6u,r.y); return; }
    uint callee = rt_uses[m.z * RT_USE_WORDS].w;
    if (rt_term_kind(r.x) != RT_KIND_ENV || !rt_term_closed(r.x) || rt_term_words(r.x).x != callee)
    { dg_fail(m.x,m.y,m.z,6u,SB_ENV); return; }
    uint entry=dg_entry(callee);
    if (entry!=RT_INVALID && rt_dir[entry*RT_DIR_WORDS].y==3u) return; // solver-selected route follows
    uint slot = dg_insert(callee,r.x,m.x,m.y,m.z);
    if (slot == RT_INVALID) return;
    uint4 route = uint4(1u,slot,0u,dg_config[15]);
    if (m.x != 0u) dg_roots[m.y] = route; else { dg_edges[m.y] = route; dg_targets[m.y]=uint2(callee,r.x); }
}
