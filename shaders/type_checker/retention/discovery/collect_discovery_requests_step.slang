import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_admission;
public RWStructuredBuffer<uint4> sb_requests;
public RWStructuredBuffer<uint> sb_request_count;

public struct DiscoveryFrontier
{
    public uint lo;
    public uint hi;
    public uint edge;
};

public DiscoveryFrontier configured_frontier()
{
    return { dg_config[1], dg_config[2], dg_config[3] };
}

void collect_discovery_use(uint root, uint lane, uint use, uint owner)
{
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
    uint capacity; uint stride; sb_requests.GetDimensions(capacity,stride);
    if (request >= capacity) { InterlockedOr(dg_status[3],4u); return; }
    uint decl = root != 0u ? u0.w : dg_instances[2u * owner].x;
    uint env = root != 0u ? u1.x : dg_instances[2u * owner].y;
    sb_requests[request] = uint4(decl,env,u1.x,use);
    dg_req_meta[request] = uint4(root,lane,use,owner);
    if (root != 0u) InterlockedAdd(dg_status[9],1u);
}

groupshared uint discovery_body_base;

// One workgroup reserves the edge range for a body and classifies its
// uses in parallel. Every lane in the group enters with the same owner.
public void collect_instance_requests(uint owner, uint lane)
{
    uint entry = dg_entry(dg_instances[2u * owner].x);
    if (entry == RT_INVALID) return;
    uint count = rt_dir[entry * RT_DIR_WORDS + 3u].x;
    if (lane == 0u)
    {
        uint base;
        InterlockedAdd(dg_status[2u], count, base);
        InterlockedMax(dg_status[5u], base + count);
        uint capacity; uint stride;
        dg_edges.GetDimensions(capacity, stride);
        if (base > capacity || count > capacity - base)
        {
            InterlockedOr(dg_status[3u], 2u);
            discovery_body_base = RT_INVALID;
        }
        else
        {
            uint depth = dg_instances[2u * owner + 1u].z;
            dg_instances[2u * owner + 1u] = uint4(base, count, depth, 0u);
            discovery_body_base = base;
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint base = discovery_body_base;
    if (base != RT_INVALID)
    {
        uint first = rt_dir[entry * RT_DIR_WORDS + 2u].w;
        for (uint offset = lane; offset < count; offset += STEP_PROGRAM_GROUP_LANES)
        {
            uint edge = base + offset;
            uint use = first + offset;
            dg_edge_owner[edge] = uint2(owner, use);
            dg_edges[edge] = uint4(0u);
            dg_targets[edge] = uint2(0u, RT_NONE);
            collect_discovery_use(0u, edge, use, owner);
        }
    }
    // All lanes must have consumed the shared base before it is reused.
    GroupMemoryBarrierWithGroupSync();
}

public void collect_root_request(uint use)
{
    dg_roots[use] = uint4(0u);
    uint entry = dg_entry(rt_uses[use * RT_USE_WORDS].x);
    if (entry == RT_INVALID || dg_generic(entry)) return;
    collect_discovery_use(1u, use, use, RT_INVALID);
}
