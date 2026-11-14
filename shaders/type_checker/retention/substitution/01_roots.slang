// Substitution step 1: one lane per request. Validates the store, the
// declaration's committed complete definition and the ENV (owner, masks,
// arity, closedness, binding classes and declared constant scalars), then
// resolves the request term to an immediate or its root task. Equal
// (env, term) keys share one task.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint request = sb_lane(dtid);
    if (request >= sb_request_total()) return;
    uint4 r = sb_requests[request];
    uint status = sb_validate(r.x, r.y);
    if (status != SB_OK)
    {
        sb_req_root[request] = uint2(r.z, status);
        return;
    }
    SbBinder b = sb_binder(r.y);
    sb_req_root[request] = sb_edge(sb_resolve(b, r.z));
}
