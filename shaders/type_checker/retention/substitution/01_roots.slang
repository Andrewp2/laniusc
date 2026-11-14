// Substitution step 1: one lane per request. Validates the store, the
// declaration's committed complete definition and the ENV (owner, masks,
// arity, closedness, binding classes and declared constant scalars), then
// resolves the request term to an immediate or its root task, and the ENV
// to its closed-evaluation task (environment 0). Equal keys share one task.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint request = sb_lane(dtid);
    if (request >= sb_request_total()) return;
    uint4 r = sb_requests[request];
    SbCheck check = sb_validate(r.x, r.y, r.z);
    sb_req_root[request * SB_ROOT_WORDS + 1u] = uint4(check.status, check.cause, check.node, check.value);
    if (check.status != SB_OK)
    {
        sb_req_root[request * SB_ROOT_WORDS] = uint4(RT_NONE, check.status, RT_NONE, check.status);
        return;
    }
    SbBinder b = sb_binder(r.y);
    SbBinder closed = sb_binder(0u);
    uint2 term = sb_edge(sb_resolve(b, r.z));
    uint2 env = sb_edge(sb_resolve(closed, r.y));
    sb_req_root[request * SB_ROOT_WORDS] = uint4(term, env);
}
