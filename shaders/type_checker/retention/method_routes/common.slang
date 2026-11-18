__exported import type_checker.retention.retention_store;
__exported import type_checker.trait_solver.retained_catalog.retained_route_abi;
__exported import type_checker.retention.substitution.sb_consumer;
// config: run, generation, requests, proof nodes, value parity, identity
// epoch/arena/serial, flag round mod 3, unused.
public StructuredBuffer<uint> mr_config;
public StructuredBuffer<uint> mr_routes;
public StructuredBuffer<uint> mr_catalog;
public StructuredBuffer<uint> mr_proof;
public StructuredBuffer<uint4> mr_instances;
public StructuredBuffer<uint4> mr_requests; // discovery metadata: root, edge, use, instance
public globallycoherent RWStructuredBuffer<uint> mr_state;
public RWStructuredBuffer<uint4> mr_selected; // target, binding first, count, receiver mode
public globallycoherent RWStructuredBuffer<uint> mr_reach;
public globallycoherent RWStructuredBuffer<uint> mr_values_a;
public globallycoherent RWStructuredBuffer<uint> mr_values_b;
public RWStructuredBuffer<uint> mr_args; // 64 terms per request
public RWStructuredBuffer<uint4> mr_out; // target, ENV, receiver mode, status (0 skip, 1 ready, >=2 failure)
public uint mr_lane(uint3 id) { return id.x+id.y*16776960u; }
public uint mr_h(uint h) { return mr_routes[h]; }
public uint mr_entry(uint d)
{
    if (d==0u || d>=rt_counts[RT_A_DECLS]) return RT_INVALID;
    uint e=rt_decl_def[d]; if (e==0u || e>rt_counts[RT_A_DIR]) return RT_INVALID; e--;
    return rt_dir[e*RT_DIR_WORDS].x==d && rt_dir[e*RT_DIR_WORDS].w==RT_DIR_COMMITTED && rt_dir[e*RT_DIR_WORDS+3u].w==0u ? e : RT_INVALID;
}
public uint mr_id(uint atom,uint kind)
{
    if (atom>=mr_h(RP_H_ATOMS)) return RT_INVALID;
    uint at=mr_h(RP_H_ATOM_IDS)+2u*atom;
    return mr_routes[at]==kind ? mr_routes[at+1u] : RT_INVALID;
}
public void mr_fail(uint request,uint code)
{
    mr_out[request]=uint4(0u,0u,0u,code);
    InterlockedOr(mr_state[14],1u<<min(code,31u));
    InterlockedAdd(mr_state[1],1u); InterlockedMin(mr_state[2],request);
}
public uint mr_binding(uint env,uint entry,uint param)
{
    if (entry==RT_INVALID || !rt_is_stored_term(env) || rt_term_kind(env)!=RT_KIND_ENV) return RT_UNKNOWN;
    uint4 d1=rt_dir[entry*RT_DIR_WORDS+1u];
    uint types=d1.y&0xffffu; uint n=types+(d1.y>>16u); uint3 head=rt_term_words(env);
    if (n>64u) return RT_UNKNOWN;
    for (uint k=0u;k<n;k++) if (rt_binders[d1.x+k]==param)
    {
        uint slot=k<types ? k : k-types; uint mask=k<types ? head.y : head.z;
        if (slot>=32u || ((mask>>slot)&1u)==0u) return RT_UNKNOWN;
        uint at=countbits(mask & ((1u<<slot)-1u))+(k<types ? 0u : countbits(head.y));
        return at<rt_term_arity(env) ? rt_term_arg(env,at) : RT_UNKNOWN;
    }
    return RT_UNKNOWN;
}
public uint4 mr_node(uint n,uint part)
{
    uint at=mr_h(RP_H_PROOF_NODES)+n*8u+part*4u;
    return uint4(mr_proof[at],mr_proof[at+1u],mr_proof[at+2u],mr_proof[at+3u]);
}
public uint mr_arity(uint4 low) { return low.x==1u ? low.w : low.x==2u ? 2u : low.x>=3u && low.x<=5u ? 1u : 0u; }
public uint2 mr_child(uint4 low,uint4 high,uint k)
{
    if (low.x==1u)
    {
        if (k>=low.w || low.z>mr_h(RP_H_PROOF_EDGE_ROWS) || low.w>mr_h(RP_H_PROOF_EDGE_ROWS)-low.z) return uint2(RT_INVALID,RT_INVALID);
        uint at=mr_h(RP_H_PROOF_EDGES)+(low.z+k)*2u; return uint2(mr_proof[at],mr_proof[at+1u]);
    }
    return k==0u ? high.xy : high.zw;
}
public bool mr_compound(uint2 r) { return r.x==3u || r.x==0x80000001u || r.x==0x80000003u; }
// Fixed-point levels (02_expand, 03_terms): level r sets its changed flag
// state[base + r%3], clears the flag of level r+1, and the loop stops at
// a level whose predecessor changed nothing (a fixed point). Three flags
// keep that clear apart from the flag a level reads. The selection pass
// marks with flag round 2, the predecessor of level 0.
public static const uint MR_LEVELS=65u; // proof depth is at most 64
public static const uint MR_EXPAND_CHANGED=20u;
public static const uint MR_TERMS_CHANGED=24u;
// Kept for consumers of the state words; one dispatch reaches the bound,
// so no pass sets it.
public static const uint MR_PENDING=28u;
public void mr_mark_at(uint2 r,uint round)
{
    if (r.x==1u && r.y>0u && r.y<RT_FIRST_TERM) return;
    if (!mr_compound(r) || r.y>=mr_config[3]) { InterlockedOr(mr_state[3],1u); return; }
    uint old; InterlockedOr(mr_reach[r.y],1u,old);
    if (old==0u) mr_state[MR_EXPAND_CHANGED+round]=1u;
}
public void mr_mark(uint2 r) { mr_mark_at(r,mr_config[10]); }
public uint mr_value_in(uint2 r,uint parity)
{
    if (r.x==1u && r.y>0u && r.y<RT_FIRST_TERM) return r.y;
    if (!mr_compound(r) || r.y>=mr_config[3]) return RT_UNKNOWN;
    return parity==0u ? mr_values_a[r.y] : mr_values_b[r.y];
}
public uint mr_value(uint2 r) { return mr_value_in(r,mr_config[4]); }
// Runs `level` once per fixed-point level in one 256-lane workgroup, with a
// workgroup barrier between levels, until a level's predecessor changed
// nothing or after MR_LEVELS levels.
groupshared uint mr_go;
public interface IMrLevel { void run(uint lane,uint level); }
public void mr_levels<L:IMrLevel>(uint lane,uint base,L level)
{
    for (uint r=0u;r<MR_LEVELS;r++)
    {
        if (lane==0u) { mr_state[base+(r+1u)%3u]=0u; mr_go=mr_state[base+(r+2u)%3u]; }
        AllMemoryBarrierWithGroupSync();
        if (mr_go==0u) break;
        level.run(lane,r);
        AllMemoryBarrierWithGroupSync();
    }
}
public struct MrArgs : IRtArgs { public uint base; public uint arg(uint k) { return mr_args[base+k]; } }
