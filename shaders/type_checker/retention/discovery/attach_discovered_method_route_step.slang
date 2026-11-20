import type_checker.retention.discovery.discovery_workspace;

public void note_unpublished_method_routes()
{
    if (dg_config[8] != 0u && dg_status[10] == 0u) dg_status[10] = 13u;
}

public void attach_discovered_method_route(uint lane, uint4 route, uint environment, uint depth)
{
    if (route.w == 0u) return;
    uint4 out = route;
    uint4 m = dg_req_meta[lane];
    if (out.w != 1u || m.x != 0u) { dg_fail(m.x, m.y, m.z, 9u, out.w); return; }
    out.y = environment;
    uint entry=dg_entry(out.x);
    if (entry==RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y!=2u || !rt_is_stored_term(out.y) ||
        rt_term_kind(out.y)!=RT_KIND_ENV || !rt_term_closed(out.y) || rt_term_words(out.y).x!=out.x)
    { dg_fail(m.x,m.y,m.z,9u,13u); return; }
    uint4 published=uint4(2u,out.x,0u,dg_config[15]);
    if (dg_generic(entry))
    {
        if (rt_dir[entry*RT_DIR_WORDS+2u].x==RT_INVALID) { dg_fail(m.x,m.y,m.z,9u,14u); return; }
        uint slot=dg_insert_at_depth(out.x,out.y,m.x,m.y,m.z,depth); if (slot==RT_INVALID) return;
        published=uint4(1u,slot,0u,dg_config[15]);
    }
    dg_edges[m.y]=published; dg_targets[m.y]=out.xy;
}
