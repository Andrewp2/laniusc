import type_checker.retention.discovery.dg_admission;
RWStructuredBuffer<uint4> pj_instances;
RWStructuredBuffer<uint4> pj_routes;
RWStructuredBuffer<uint2> pj_targets;
RWStructuredBuffer<uint4> pj_readiness;
RWStructuredBuffer<uint4> dg_root_routes;
RWStructuredBuffer<uint4> dg_root_readiness;
// A chain of waves (mode 3): words 0-2 the current wave's (lo, hi, edges),
// word 3 the instances with closed predicates before it, then (lo, hi) of
// chained wave i at 4 + 2i.
RWStructuredBuffer<uint> dg_wave;
// Mode 4: a chained closed solve's receipt (route header, solver state,
// batch receipt), and the workgroups of its method routes (seven kernels)
// and of the bound routes, which the receipt gates. Mode 5: the source
// publication's status, which gates the roots pass (dg_bound_args).
StructuredBuffer<uint> dg_receipt;
RWStructuredBuffer<uint> dg_route_args;
RWStructuredBuffer<uint> dg_bound_args;
void write_groups(uint at, uint groups, bool run)
{
    dg_route_args[at]=run ? min(groups,65535u) : 0u;
    dg_route_args[at+1u]=run ? (groups+65534u)/65535u : 0u;
    dg_route_args[at+2u]=run ? 1u : 0u;
}
uint4 route_of(uint4 route,bool root)
{
    if(route.x==1u) return uint4(0xfffffffeu,0xffff0002u,dg_rank[dg_slots[route.y].y],dg_config[15]);
    if(route.x==2u) return dg_native(route.y);
    return root ? uint4(0u,0u,0u,0u) : uint4(RT_INVALID,0u,0u,dg_config[15]);
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane=dg_lane(id);
    if(dg_config[0]==3u)
    {
        // The next chained wave expands the instances the last one
        // inserted, unless the host must decide first: a failure or
        // overflow, or new instances with closed predicates (status 11
        // differs from dg_wave word 3), which need the closed solver. Then
        // the wave's frontier is empty and it does nothing. A wave that
        // records its closed solve (config 11 set) takes new closed
        // predicates itself.
        if(lane==0u)
        {
            uint lo=dg_wave[1];
            bool go=(dg_config[11]!=0u || dg_status[11]==dg_wave[3]) && dg_status[12]==0u && dg_status[3]==0u
                && dg_status[10]==0u && dg_status[6]==RT_INVALID;
            uint hi=go ? max(dg_status[0],lo) : lo;
            dg_wave[0]=lo; dg_wave[1]=hi; dg_wave[2]=dg_status[2];
            uint at=4u+2u*(dg_config[8]-1u);
            dg_wave[at]=lo; dg_wave[at+1u]=hi;
        }
        return;
    }
    if(dg_config[0]==4u)
    {
        // A chained closed solve's receipt, copied into dg_receipt. A solve
        // that ran must have placed its batch (producer word 31 zero) and
        // finished (solver stop word, receipt word 64, is 2): otherwise
        // the chain stops with code 12 and the host runs the attempt again
        // without it. A skipped solve (producer word 16) has no proofs, so
        // the wave's method and bound routes dispatch no workgroups, as do
        // those of a failed one. Config words 10, 12 and 13 are the
        // workgroups of the routes' proof-sized, request-sized and
        // term-slot-sized kernels (words 1 to 3 hold the frontier).
        if(lane==0u)
        {
            uint producer=dg_receipt[31];
            bool solved=producer==0u && dg_receipt[64]==2u;
            if(producer!=16u && !solved && dg_status[10]==0u) dg_status[10]=12u;
            bool run=solved && dg_status[10]==0u && dg_status[12]==0u;
            uint requests=dg_config[12];
            write_groups(0u,dg_config[10],run);
            write_groups(3u,requests,run);
            write_groups(6u,1u,run);
            write_groups(9u,1u,run);
            write_groups(12u,requests,run);
            write_groups(15u,1u,run);
            write_groups(18u,dg_config[13],run);
            dg_bound_args[0]=run ? min(requests,65535u) : 0u;
            dg_bound_args[1]=run ? (requests+65534u)/65535u : 0u;
            dg_bound_args[2]=run ? 1u : 0u;
        }
        return;
    }
    if(dg_config[0]==5u)
    {
        // The roots' gate: the source publication's status words (route
        // header 8 to 10, copied into dg_receipt words 0 to 2). Its solve
        // ran without a host readback, so it publishes as valid only when
        // it finished and its catalog was admitted (header words 45 to 47).
        // The roots pass dispatches config word 10's workgroups for a valid
        // publication and none otherwise: nothing requests a substitution
        // and nothing is appended to the store. The roots' readback returns
        // the status, and the host rejects or checks again.
        if(lane==0u)
        {
            bool run=dg_receipt[0]==1u && dg_receipt[1]==0u;
            uint groups=dg_config[10];
            dg_bound_args[0]=run ? min(groups,65535u) : 0u;
            dg_bound_args[1]=run ? (groups+65534u)/65535u : 0u;
            dg_bound_args[2]=run ? 1u : 0u;
        }
        return;
    }
    if(dg_config[0]==0u)
    {
        if(lane==0u)
        {
            if(dg_status[6]!=RT_INVALID) dg_status[16]=dg_errors[dg_status[6]].x;
            if(dg_status[6]!=RT_INVALID)
            {
                uint4 e=dg_errors[dg_status[6]];
                dg_status[17]=e.y; dg_status[18]=e.z; dg_status[19]=e.w;
            }
            if(rt_counts[RT_C_READY]==0u || rt_counts[RT_C_GENERATION]!=dg_config[15]) dg_status[10]=1u;
            // Resolution follows requests without a host check; it does
            // nothing after a failure or overflow, which the host reports.
            dg_status[12]=dg_status[3]!=0u || dg_status[6]!=RT_INVALID || dg_status[10]!=0u ? 1u : 0u;
        }
        return;
    }
    if (dg_proof_identity[0] != 0u && !dg_proofs_current()) { if (lane == 0u) dg_status[10] = 8u; return; }
    if(dg_status[3]!=0u || dg_status[6]!=RT_INVALID || dg_status[10]!=0u) return;
    if(dg_config[0]==1u)
    {
        if(lane<dg_status[1])
        {
            uint instance=dg_order[lane];
            uint4 i0=dg_instances[2u*instance]; uint4 i1=dg_instances[2u*instance+1u];
            pj_instances[2u*lane]=i0;
            pj_instances[2u*lane+1u]=uint4(i1.xy,0u,0u);
        }
        if(lane<dg_status[2]) { pj_routes[lane]=route_of(dg_edges[lane],false); pj_targets[lane]=dg_targets[lane]; }
        if(lane<rt_counts[RT_A_USES]) dg_root_routes[lane]=route_of(dg_roots[lane],true);
    }
    else if(lane==0u)
    {
        // Projection checks every instance call's ABI before lowering.
        // Original callers require a separate GPU ABI certification.
        pj_readiness[0]=uint4(dg_config[15],1u | (dg_proof_identity[0] != 0u ? 4u : 0u),dg_status[1],dg_status[2]);
        dg_root_readiness[0]=uint4(dg_config[15],1u,dg_status[1],rt_counts[RT_A_USES]);
    }
}
