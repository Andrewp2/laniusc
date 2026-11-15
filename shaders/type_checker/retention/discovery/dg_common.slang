// GPU discovery over immutable retained calls. One request per reachable
// (instance, use); the host reads counts and errors, never semantic rows.
__exported import type_checker.retention.retention_store;
public StructuredBuffer<uint> dg_config;
public globallycoherent RWStructuredBuffer<uint> dg_status;
public globallycoherent RWStructuredBuffer<uint4> dg_instances;
public globallycoherent RWStructuredBuffer<uint> dg_slots;
public RWStructuredBuffer<uint> dg_scan_a;
public RWStructuredBuffer<uint> dg_scan_b;
public RWStructuredBuffer<uint4> dg_edges;
public RWStructuredBuffer<uint2> dg_targets;
public RWStructuredBuffer<uint2> dg_edge_owner;
public RWStructuredBuffer<uint4> dg_roots;
public RWStructuredBuffer<uint4> dg_errors;
public RWStructuredBuffer<uint4> dg_req_meta;
public RWStructuredBuffer<uint> dg_order;
public RWStructuredBuffer<uint> dg_rank;
public RWStructuredBuffer<uint> dg_term_order;
public RWStructuredBuffer<uint> dg_term_rank;
public globallycoherent RWStructuredBuffer<uint> dg_levels;
// config: mode, lo, hi, edge base, root phase, subst run, depth, hash mask,
//         scan distance, scan input, sort k, sort j, sort base, sort count,
//         level, generation.
// status: allocated instances, live instances, edges, overflow bits,
//         instance demand, edge demand, first error+1 (INVALID when none),
//         request demand, generation, roots, reserved...
public uint dg_lane(uint3 id) { return id.x + id.y * 16776960u; }
public uint dg_entry(uint decl)
{
    if (decl == 0u || decl >= rt_counts[RT_A_DECLS]) return RT_INVALID;
    uint value = rt_decl_def[decl];
    if (value == 0u || value > rt_counts[RT_A_DIR]) return RT_INVALID;
    uint entry = value - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    return d0.x == decl && d0.w == RT_DIR_COMMITTED && d3.w == 0u ? entry : RT_INVALID;
}
public bool dg_generic(uint entry) { return rt_dir[entry * RT_DIR_WORDS + 1u].y != 0u; }
public bool dg_predicates(uint entry)
{
    if (rt_dir_trait[entry].y != 0u) return true;
    uint parent = dg_entry(rt_dir[entry * RT_DIR_WORDS].z);
    return parent != RT_INVALID && rt_dir_trait[parent].y != 0u;
}
public void dg_fail(uint root, uint index, uint use, uint code, uint detail)
{
    uint error = root != 0u ? index : rt_counts[RT_A_USES] + index;
    dg_errors[error] = uint4(code, use, detail, root != 0u ? RT_INVALID : dg_edge_owner[index].x);
    InterlockedMin(dg_status[6], error);
}
public uint dg_insert(uint decl, uint env, uint root, uint index, uint use)
{
    uint capacity; uint stride; dg_instances.GetDimensions(capacity, stride); capacity /= 2u;
    uint slots; dg_slots.GetDimensions(slots, stride);
    uint slot = (rt_mix(decl, env) & dg_config[7]) & (slots - 1u);
    uint candidate = RT_INVALID;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = dg_slots[slot];
        if (value == 0u)
        {
            if (dg_config[6] > 64u) { dg_fail(root, index, use, 7u, dg_config[6]); return RT_INVALID; }
            if (candidate == RT_INVALID)
            {
                InterlockedAdd(dg_status[0], 1u, candidate);
                InterlockedMax(dg_status[4], candidate + 1u);
                if (candidate >= capacity) { InterlockedOr(dg_status[3], 1u); return RT_INVALID; }
                dg_instances[2u * candidate] = uint4(decl, env, dg_config[15], 0u);
                dg_instances[2u * candidate + 1u] = uint4(0u, 0u, dg_config[6], 0u);
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(dg_slots[slot], 0u, candidate + 1u, value);
            if (value == 0u) { InterlockedAdd(dg_status[1], 1u); return candidate; }
        }
        DeviceMemoryBarrier();
        uint4 key = dg_instances[2u * (value - 1u)];
        if (key.x == decl && key.y == env)
        {
            if (candidate != RT_INVALID) dg_instances[2u * candidate] = uint4(0u, 0u, 0u, 0u);
            return value - 1u;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    if (candidate != RT_INVALID) dg_instances[2u * candidate] = uint4(0u, 0u, 0u, 0u);
    InterlockedOr(dg_status[3], 1u);
    return RT_INVALID;
}
public uint dg_scan(uint index) { return dg_config[9] == 0u ? dg_scan_a[index] : dg_scan_b[index]; }
public uint4 dg_native(uint decl)
{
    uint4 key = rt_decl_key[decl];
    return uint4(key.x, key.y, key.w, dg_config[15]);
}
public int dg_cmp(uint a, uint b) { return a < b ? -1 : (a > b ? 1 : 0); }
public int dg_decl_cmp(uint a, uint b)
{
    if (a == b || a == 0u || b == 0u) return dg_cmp(a,b);
    uint4 x = rt_decl_key[a]; uint4 y = rt_decl_key[b];
    int c = dg_cmp(x.x,y.x); if(c != 0) return c;
    c = dg_cmp(x.y,y.y); if(c != 0) return c;
    c = dg_cmp(x.z,y.z); return c != 0 ? c : dg_cmp(x.w,y.w);
}
