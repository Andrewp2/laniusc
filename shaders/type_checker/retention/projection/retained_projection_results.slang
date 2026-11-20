import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.substitution.retained_substitution_results;

// A substitution result: the closed TermId, or RT_INVALID with `status`.
public uint pj_result(uint request, out uint status)
{
    if (!sb_result_current(pj_config[PJ_CFG_RUN], request))
    {
        status = 0xffffu;
        return RT_INVALID;
    }
    uint4 r0 = sb_results[request * SB_RESULT_WORDS];
    status = r0.y;
    return r0.y == SB_OK ? r0.x : RT_INVALID;
}
