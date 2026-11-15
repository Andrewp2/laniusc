import type_checker.retention.discovery.dg_admission;
RWStructuredBuffer<uint4> sb_requests;
globallycoherent RWStructuredBuffer<uint> sb_request_count;

[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane = dg_lane(id);
    uint root = dg_config[4]; uint use = lane; uint owner = RT_INVALID;
    if (lane == 0u && (rt_counts[RT_C_READY] == 0u || rt_counts[RT_C_GENERATION] != dg_config[15]))
        dg_status[10] = 1u;
    if (lane == 0u && dg_proof_identity[0] != 0u && !dg_proofs_current()) dg_status[10] = 8u;
    if (root != 0u)
    {
        if (lane >= rt_counts[RT_A_USES]) return;
        dg_roots[lane] = uint4(0u,0u,0u,0u);
        uint e = dg_entry(rt_uses[use * RT_USE_WORDS].x);
        if (e == RT_INVALID || dg_generic(e)) return;
    }
    else
    {
        if (lane >= dg_status[2] - dg_config[3]) return;
        uint lo = 0u; uint hi = dg_config[2] - dg_config[1];
        while (lo < hi)
        {
            uint mid = lo + (hi - lo) / 2u;
            if (dg_scan(mid) <= lane) lo = mid + 1u; else hi = mid;
        }
        owner = dg_config[1] + lo;
        uint4 i1 = dg_instances[2u * owner + 1u];
        uint entry = dg_entry(dg_instances[2u * owner].x);
        uint edge = dg_config[3] + lane;
        use = rt_dir[entry * RT_DIR_WORDS + 2u].w + edge - i1.x;
        dg_edge_owner[edge] = uint2(owner, use);
        dg_edges[edge] = uint4(0u,0u,0u,0u);
        dg_targets[edge]=uint2(0u,RT_NONE);
        lane = edge;
    }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint form = u0.z & 0xffu;
    // Non-call syntax contributes row and layout types during projection.
    if (form == 3u || form == 4u || form == 5u) return;
    if (form == 8u)
    {
        // A function value names an ordinary out-of-line function. Its C
        // entry is emitted in the caller batch and calls this symbol.
        uint callee = dg_entry(u0.w);
        if (callee == RT_INVALID || rt_dir[callee*RT_DIR_WORDS].y != 1u ||
            dg_generic(callee) || dg_predicates(callee))
        { dg_fail(root,lane,use,4u,u0.w); return; }
        uint4 route = uint4(2u,u0.w,0u,dg_config[15]);
        if (root != 0u) dg_roots[lane] = route;
        else { dg_edges[lane] = route; dg_targets[lane] = uint2(u0.w,RT_NONE); }
        return;
    }
    // Required members use this same substitution request. The closed
    // solver wave selects their concrete implementation after substitution.
    if ((form != 1u && form != 2u && form != 6u) || (form == 1u && (u0.z >> 8u) != 0u))
    {
        if (root == 0u || form == 7u) dg_fail(root,lane,use,3u,form);
        return;
    }
    uint adjustment = (u0.z >> 8u) & 0xffu;
    if (form == 2u && (adjustment < 1u || adjustment > 2u || (u0.z >> 16u) > 64u))
    { dg_fail(root,lane,use,3u,u0.z); return; }
    uint callee = dg_entry(u0.w);
    if (callee == RT_INVALID) { dg_fail(root,lane,use,2u,u0.w); return; }
    // Original objects already lower nongeneric extern calls through the
    // target ABI. They have no body to instantiate and no provisional symbol.
    if (rt_dir[callee * RT_DIR_WORDS].y == 4u &&
        !dg_generic(callee) && !dg_predicates(callee))
    {
        uint4 route=uint4(2u,u0.w,0u,dg_config[15]);
        if (root!=0u) dg_roots[lane]=route;
        else { dg_edges[lane]=route; dg_targets[lane]=uint2(u0.w,RT_NONE); }
        return;
    }
    // A host service must resolve to a nongeneric extern declaration above.
    if (form == 6u) { dg_fail(root,lane,use,4u,u0.w); return; }
    bool bound=rt_dir[callee*RT_DIR_WORDS].y==3u;
    if (bound && root!=0u) { dg_fail(root,lane,use,4u,u0.w); return; }
    if (!bound && rt_dir[callee * RT_DIR_WORDS].y != 1u && rt_dir[callee * RT_DIR_WORDS].y != 2u)
    { dg_fail(root,lane,use,4u,u0.w); return; }
    if (form == 2u && !bound && rt_dir[callee * RT_DIR_WORDS].y != 2u)
    { dg_fail(root,lane,use,4u,u0.w); return; }
    if (!bound && dg_predicates(callee) && !dg_use_proven(use,callee,root != 0u))
    { dg_fail(root,lane,use,8u,u0.w); return; }
    if (!dg_generic(callee))
    {
        uint4 route = uint4(2u,u0.w,0u,dg_config[15]);
        if (root != 0u) dg_roots[lane] = route; else { dg_edges[lane] = route; dg_targets[lane]=uint2(u0.w,RT_NONE); }
        return;
    }
    if (!bound && rt_dir[callee * RT_DIR_WORDS + 2u].x == RT_INVALID)
    { dg_fail(root,lane,use,2u,u0.w); return; }
    uint request; InterlockedAdd(sb_request_count[0],1u,request);
    InterlockedMax(dg_status[7],request+1u);
    uint capacity; uint stride; sb_requests.GetDimensions(capacity,stride);
    if (request >= capacity) { InterlockedOr(dg_status[3],4u); return; }
    uint decl = root != 0u ? u0.w : dg_instances[2u * owner].x;
    uint env = root != 0u ? u1.x : dg_instances[2u * owner].y;
    sb_requests[request] = uint4(decl,env,u1.x,use);
    dg_req_meta[request] = uint4(root,lane,use,owner);
    if (root != 0u) InterlockedAdd(dg_status[9],1u);
}
