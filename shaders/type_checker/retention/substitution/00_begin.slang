// Substitution step 0 (one lane): open the attempt. The host has zeroed
// sb_counts and the memo slots and written the run number into sb_config.
// Saves the store's term counters as this attempt's watermark: an attempt
// that overflows restores them (step 08) and clears the hash slots that
// point past them (step 09), so nothing it interned stays reachable.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;
import type_checker.retention.substitution.sb_dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sb_counts[SB_C_STORE_TERMS_BASE] = rt_counts[RT_A_TERMS];
    sb_counts[SB_C_STORE_ARGS_BASE] = rt_counts[RT_A_TERM_ARGS];
    sb_counts[SB_C_STORE_SPARE_TERMS] = rt_counts[RT_C_SPARE + RT_A_TERMS];
    sb_counts[SB_C_STORE_SPARE_ARGS] = rt_counts[RT_C_SPARE + RT_A_TERM_ARGS];
    sb_counts[SB_C_STORE_OVERFLOW_SAVED] = rt_counts[RT_C_OVERFLOW];
    sb_counts[SB_C_STORE_DEMAND_TERMS_SAVED] = rt_counts[RT_C_DEMAND + RT_A_TERMS];
    sb_counts[SB_C_STORE_DEMAND_ARGS_SAVED] = rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS];
    rt_counts[RT_C_OVERFLOW] = 0u;
    rt_counts[RT_C_DEMAND + RT_A_TERMS] = 0u;
    rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS] = 0u;

    uint requests = sb_request_count[0u];
    uint capacity = sb_request_capacity();
    if (requests > capacity)
    {
        sb_counts[SB_C_REQUEST_CLAMPED] = requests;
        requests = capacity;
    }
    sb_counts[SB_C_REQUESTS] = requests;
    sb_counts[SB_C_RUN] = sb_config[SB_CFG_RUN];
    sb_counts[SB_C_STATE] = SB_STATE_OPEN;
    sb_counts[SB_C_PHASE] = SB_PHASE_EXPAND;
    sb_counts[SB_C_FRONTIER_LO] = 0u;
    sb_counts[SB_C_FRONTIER_HI] = 0u;
    sb_counts[SB_C_LEVEL] = 0u;
    sb_set_dispatch(SB_D_ROOTS, requests);
    sb_set_dispatch(SB_D_PUBLISH, requests);
    sb_set_dispatch(SB_D_EXPAND, 0u);
    sb_set_dispatch(SB_D_SCATTER, 0u);
    sb_set_dispatch(SB_D_EVAL, 0u);
    sb_set_dispatch(SB_D_ROLLBACK, 0u);
}
