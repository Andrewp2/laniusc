import type_checker.retention.projection.schema.common;
import type_checker.retention.substitution.sb_consumer;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint q = ps_lane(id);
    if (q == 0u) ps_status[1] = rt_counts[RT_A_TERMS];
    if (q >= ps_status[0]) return;
    uint2 result = uint2(RT_INVALID,SB_INVARIANT);
    if (sb_result_current(ps_config[5],q))
    {
        uint4 r = sb_results[q*SB_RESULT_WORDS];
        result = uint2(r.y == SB_OK ? r.x : RT_INVALID,r.y);
    }
    pj_schema_fields[ps_config[2]+q] = result;
}
