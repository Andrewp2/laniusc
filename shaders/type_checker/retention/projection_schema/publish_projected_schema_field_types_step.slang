// Stores each request's field type. A run that did not publish leaves
// invalid fields; the next round gate stops the rounds, and the host
// substitutes the round again and repeats this pass.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.substitution.retained_substitution_results;
public void publish_projected_schema_field_types(uint q)
{
    if (q >= ps_round_count()) return;
    uint run = ps_config[PS_CFG_RUN];
    uint2 result = uint2(RT_INVALID,SB_INVARIANT);
    if (sb_result_current(run,q))
    {
        uint4 r = sb_results[q*SB_RESULT_WORDS];
        result = uint2(r.y == SB_OK ? r.x : RT_INVALID,r.y);
    }
    pj_schema_fields[ps_round_base()+q] = result;
}
