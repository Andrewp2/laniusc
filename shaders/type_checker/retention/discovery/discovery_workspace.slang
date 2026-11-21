// GPU discovery over immutable retained calls. One request per reachable
// (instance, use); the host reads counts and errors, never semantic rows.
__exported import type_checker.retention.retention_store;
public StructuredBuffer<uint> dg_config;
public globallycoherent RWStructuredBuffer<uint> dg_status;
public globallycoherent RWStructuredBuffer<uint4> dg_instances;
// (environment key, dense instance row). Resolution records the slot, and
// publish_discovery_wave reads its row after the dispatch that claimed it has finished.
public globallycoherent RWStructuredBuffer<uint2> dg_slots;
public RWStructuredBuffer<uint4> dg_edges;
public RWStructuredBuffer<uint2> dg_targets;
public RWStructuredBuffer<uint2> dg_edge_owner;
public RWStructuredBuffer<uint4> dg_roots;
public RWStructuredBuffer<uint4> dg_errors;
public RWStructuredBuffer<uint4> dg_req_meta;
public RWStructuredBuffer<uint> dg_order;
public RWStructuredBuffer<uint> dg_rank;
// config: mode, lo, hi, edge base, root phase, subst run, depth, hash mask,
//         wave index, reserved, receipt gate, reserved, wave range or sort size,
//         level, generation.
// status: allocated instances, live instances, edges, overflow bits,
//         instance demand, edge demand, first error+1 (INVALID when none),
//         request demand, generation, roots, failure, predicated instances,
//         requests blocked (failure or overflow before resolution), reserved...
public uint dg_lane(uint3 id) { return id.x + id.y * 16776960u; }
[noinline]
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
[noinline]
public uint dg_insert_at_depth(uint decl, uint env, uint root, uint index, uint use, uint depth)
{
    uint capacity; uint stride; dg_instances.GetDimensions(capacity, stride); capacity /= 2u;
    uint slots; dg_slots.GetDimensions(slots, stride);
    uint slot = (rt_mix(decl, env) & dg_config[7]) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        // The environment names its callee, so its ID is the complete key.
        uint value = dg_slots[slot].x;
        if (value == 0u)
        {
            if (depth > 64u) { dg_fail(root, index, use, 7u, depth); return RT_INVALID; }
            InterlockedCompareExchange(dg_slots[slot].x, 0u, env, value);
            if (value == 0u)
            {
                uint candidate;
                InterlockedAdd(dg_status[0], 1u, candidate);
                InterlockedMax(dg_status[4], candidate + 1u);
                if (candidate >= capacity) { InterlockedOr(dg_status[3], 1u); return RT_INVALID; }
                dg_instances[2u * candidate] = uint4(decl, env, dg_config[15], 0u);
                dg_instances[2u * candidate + 1u] = uint4(0u, 0u, depth, 0u);
                dg_slots[slot].y = candidate;
                InterlockedAdd(dg_status[1], 1u);
                // Instances whose closed predicates need a solver wave.
                uint entry = dg_entry(decl);
                if (entry != RT_INVALID && dg_predicates(entry)) InterlockedAdd(dg_status[11], 1u);
                return slot;
            }
        }
        if (value == env) return slot;
        slot = (slot + 1u) & (slots - 1u);
    }
    InterlockedOr(dg_status[3], 1u);
    return RT_INVALID;
}

public uint dg_insert(uint decl, uint env, uint root, uint index, uint use)
{
    return dg_insert_at_depth(decl, env, root, index, use, dg_config[6]);
}

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
// Bitonic sort steps with j < DG_SORT_BLOCK/2 stay inside one 512-element
// block, so one workgroup runs them in shared memory with the same
// compare-exchange network as the global steps (identical output, ties
// included). k == 0 sorts each block completely (k = 2 .. min(512, count));
// otherwise it finishes stage k with j = 256 .. 1. count is a power of two.
public static const uint DG_SORT_BLOCK = 512u;
groupshared uint dg_sort_keys[DG_SORT_BLOCK];
public void dg_sort_block<C : IDgCompare>(C order, uint group, uint thread, uint count, uint k)
{
    uint block = group * DG_SORT_BLOCK;
    for (uint e = thread; e < DG_SORT_BLOCK; e += 256u)
        dg_sort_keys[e] = block + e < count ? order.load(block + e) : RT_INVALID;
    GroupMemoryBarrierWithGroupSync();
    uint first = k == 0u ? 2u : k;
    uint last = k == 0u ? min(DG_SORT_BLOCK, count) : k;
    for (uint kk = first; kk <= last; kk <<= 1u)
    {
        for (uint j = k == 0u ? kk >> 1u : DG_SORT_BLOCK >> 1u; j != 0u; j >>= 1u)
        {
            uint i = (thread / j) * 2u * j + thread % j;
            if (block + i < count)
            {
                uint a = dg_sort_keys[i]; uint b = dg_sort_keys[i + j];
                bool ascending = ((block + i) & kk) == 0u;
                if ((order.compare(a, b) > 0) == ascending) { dg_sort_keys[i] = b; dg_sort_keys[i + j] = a; }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }
    for (uint e = thread; e < DG_SORT_BLOCK; e += 256u)
        if (block + e < count) order.store(block + e, dg_sort_keys[e]);
}
public interface IDgCompare
{
    int compare(uint a, uint b);
    uint load(uint index);
    void store(uint index, uint value);
}
