// Stores each request's field type. A run that did not publish leaves
// invalid fields; the next round gate stops the rounds, and the host
// substitutes the round again and repeats this pass.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.substitution.retained_substitution_layout;
public void publish_projected_schema_field_types(uint q, uint4 result, bool current)
{
    if (q >= ps_round_count()) return;
    uint2 field = uint2(RT_INVALID, SB_INVARIANT);
    if (current) field = uint2(result.y == SB_OK ? result.x : RT_INVALID, result.y);
    pj_schema_fields[ps_round_base()+q] = field;
}
