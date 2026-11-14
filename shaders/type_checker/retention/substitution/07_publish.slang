// Substitution step 7: one lane per request, after the attempt finished.
// A committed attempt publishes each request's result with its status and
// provenance. An overflowed attempt publishes SB_CAPACITY for every request:
// none of its partial results or failures is visible.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint request = sb_lane(dtid);
    uint phase = sb_counts[SB_C_PHASE];
    if (phase != SB_PHASE_DONE && phase != SB_PHASE_OVERFLOW) return;
    if (request >= sb_request_total()) return;
    uint4 r = sb_requests[request];
    uint run = sb_counts[SB_C_RUN];
    uint4 out = uint4(RT_UNKNOWN, SB_CAPACITY, RT_NONE, 0u);
    uint fail_value = RT_NONE;
    if (phase == SB_PHASE_DONE)
    {
        uint2 root = sb_req_root[request];
        if (root.y == SB_EDGE_TASK)
        {
            out = sb_task_res[root.x];
            fail_value = sb_task_fail[root.x];
            if (out.y == SB_PENDING) out = uint4(RT_UNKNOWN, SB_INVARIANT, r.z, r.y);
        }
        else if (root.y == SB_OK) out = uint4(root.x, SB_OK, RT_NONE, 0u);
        else out = uint4(RT_UNKNOWN, root.y, root.x, root.y == SB_DECL || root.y == SB_NOT_READY ? 0u : r.y);
    }
    if (out.y == SB_OK && !rt_term_closed(out.x)) out = uint4(RT_UNKNOWN, SB_INVARIANT, r.z, r.y);
    sb_results[request * SB_RESULT_WORDS] = out;
    sb_results[request * SB_RESULT_WORDS + 1u] = uint4(fail_value, r.w, run, 0u);
    InterlockedAdd(sb_counts[SB_C_STATUS + min(out.y, SB_STATUSES - 1u)], 1u);
}
