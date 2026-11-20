import type_checker.retention.discovery.discovery_admission;
import type_checker.retention.discovery.discovery_request_status;
// A chain of waves (mode 3): words 0-2 the current wave's (lo, hi, edges),
// word 3 the instances with closed predicates before it, then (lo, hi) of
// chained wave i at 4 + 2i.
RWStructuredBuffer<uint> dg_wave;
// Mode 4: the closed-solve receipt gates method and bound routes.
StructuredBuffer<uint> dg_receipt;
RWStructuredBuffer<uint> dg_route_gate;
RWStructuredBuffer<uint> dg_bound_args;
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
        if(lane==0u)
        {
            uint producer=dg_receipt[31];
            bool solved=producer==0u && dg_receipt[64]==2u;
            if(producer!=16u && !solved && dg_status[10]==0u) dg_status[10]=12u;
            bool run=solved && dg_status[10]==0u && dg_status[12]==0u;
            uint requests=dg_config[12];
            dg_route_gate[0u] = run ? 1u : 0u;
            dg_bound_args[0]=run ? min(requests,65535u) : 0u;
            dg_bound_args[1]=run ? (requests+65534u)/65535u : 0u;
            dg_bound_args[2]=run ? 1u : 0u;
        }
        return;
    }
    if (dg_config[0] == 0u && lane == 0u) finish_discovery_requests();
}
