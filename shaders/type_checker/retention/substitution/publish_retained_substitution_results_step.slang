// Substitution step 4: one lane per request, after the attempt finished.
// A committed attempt publishes each request's result with its status and
// provenance. An overflowed attempt publishes SB_CAPACITY for every request:
// none of its partial results or failures is visible.
//
// Outcome order of one request (fixed, never timing-dependent):
//   1. a request validation failure (step 01);
//   2. a failure of the ENV's closed evaluation: SB_ENV, cause
//      SB_ENV_EVAL, with the inner status in r2.y and the inner provenance;
//   3. an ENV whose closed evaluation is a different term: SB_ENV, cause
//      SB_ENV_NONCANONICAL, failed value = the normalized ENV;
//   4. the term's own result.
// Every ENV failure names the request ENV as its failed environment.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

// The outcome of a root edge: (value, status, failed node, failed env) and
// (failed child value, cause).
void edge_result(uint2 edge, uint env, out uint4 out, out uint2 fail)
{
    fail = uint2(RT_NONE, SB_ENV_NONE);
    if (edge.y == SB_EDGE_TASK)
    {
        out = sb_task_result(sb_edge_task(edge.x), fail);
        if (out.y == SB_PENDING) { out = uint4(RT_UNKNOWN, SB_INVARIANT, RT_NONE, env); fail = uint2(RT_NONE, SB_ENV_NONE); }
    }
    else if (edge.y == SB_OK) out = uint4(edge.x, SB_OK, RT_NONE, 0u);
    else out = uint4(RT_UNKNOWN, edge.y, edge.x, env);
}

public void publish_retained_substitution_results(uint request, uint4 r)
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase != SB_PHASE_DONE && phase != SB_PHASE_OVERFLOW) return;
    if (request >= sb_request_total()) return;
    uint4 out = uint4(RT_UNKNOWN, SB_CAPACITY, RT_NONE, 0u);
    uint fail_value = RT_NONE;
    uint3 cause = uint3(SB_ENV_NONE, SB_OK, SB_ENV_NONE);
    if (phase == SB_PHASE_DONE)
    {
        uint4 root = sb_req_root[request * SB_ROOT_WORDS];
        uint4 check = sb_req_root[request * SB_ROOT_WORDS + 1u];
        if (check.x != SB_OK)
        {
            bool scoped = check.x != SB_NOT_READY && check.x != SB_DECL;
            out = uint4(RT_UNKNOWN, check.x, check.z, scoped ? r.y : 0u);
            fail_value = check.w;
            cause.x = check.y;
        }
        else
        {
            uint4 env_out; uint2 env_fail;
            edge_result(root.zw, r.y, env_out, env_fail);
            if (env_out.y != SB_OK)
            {
                out = uint4(RT_UNKNOWN, SB_ENV, env_out.z, r.y);
                fail_value = env_fail.x;
                cause = uint3(SB_ENV_EVAL, env_out.y, env_fail.y);
            }
            else if (env_out.x != r.y)
            {
                out = uint4(RT_UNKNOWN, SB_ENV, r.y, r.y);
                fail_value = env_out.x;
                cause.x = SB_ENV_NONCANONICAL;
            }
            else
            {
                uint2 term_fail;
                edge_result(root.xy, r.y, out, term_fail);
                fail_value = term_fail.x;
                cause.x = term_fail.y;
            }
        }
    }
    if (out.y == SB_OK && !rt_term_closed(out.x))
    {
        out = uint4(RT_UNKNOWN, SB_INVARIANT, r.z, r.y);
        fail_value = RT_NONE;
        cause = uint3(SB_ENV_NONE, SB_OK, SB_ENV_NONE);
    }
    sb_results[request * SB_RESULT_WORDS] = out;
    sb_results[request * SB_RESULT_WORDS + 1u] = uint4(fail_value, r.w, sb_counts[SB_C_RUN], sb_counts[SB_C_GENERATION]);
    sb_results[request * SB_RESULT_WORDS + 2u] = uint4(cause, 0u);
    InterlockedAdd(sb_counts[SB_C_STATUS + min(out.y, SB_STATUSES - 1u)], 1u);
}
