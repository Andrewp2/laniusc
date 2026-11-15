import type_checker.retention.discovery.dg_common;
StructuredBuffer<uint4> mr_out;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=dg_lane(id); if (i>=dg_status[7]) return;
    uint4 out=mr_out[i]; if (out.w==0u) return;
    uint4 m=dg_req_meta[i];
    if (out.w!=1u || m.x!=0u) { dg_fail(m.x,m.y,m.z,9u,out.w); return; }
    uint entry=dg_entry(out.x);
    if (entry==RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y!=2u || !rt_is_stored_term(out.y) ||
        rt_term_kind(out.y)!=RT_KIND_ENV || !rt_term_closed(out.y) || rt_term_words(out.y).x!=out.x)
    { dg_fail(m.x,m.y,m.z,9u,13u); return; }
    uint4 route=uint4(2u,out.x,0u,dg_config[15]);
    if (dg_generic(entry))
    {
        if (rt_dir[entry*RT_DIR_WORDS+2u].x==RT_INVALID) { dg_fail(m.x,m.y,m.z,9u,14u); return; }
        uint target=dg_insert(out.x,out.y,m.x,m.y,m.z); if (target==RT_INVALID) return;
        route=uint4(1u,target,0u,dg_config[15]);
    }
    dg_edges[m.y]=route; dg_targets[m.y]=out.xy;
}
