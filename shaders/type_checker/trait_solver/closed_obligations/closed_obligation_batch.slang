// Closed instance obligations use the admitted program catalog. This producer
// writes only batch terms, environments, calls and hard obligations. Instances
// carry no assumptions; the existing solver owns implementation selection.
__exported import type_checker.retention.retention_store;
__exported import type_checker.trait_solver.retained_catalog.retained_route_abi;
// Discovery finished writing these tables before the closed batch starts.
public StructuredBuffer<uint> closed_rt_counts;
public StructuredBuffer<uint> closed_rt_decl_def;
public StructuredBuffer<uint4> closed_rt_dir;
public StructuredBuffer<uint4> closed_rt_dir_trait;
public StructuredBuffer<uint4> closed_rt_term_head;
public StructuredBuffer<uint4> closed_rt_term_meta;
public StructuredBuffer<uint> closed_rt_term_args;

public uint cw_term_kind(uint term) { return closed_rt_term_head[term].x & 0xffu; }
public uint cw_term_arity(uint term) { return (closed_rt_term_head[term].x >> 8u) & 0xffu; }
public uint3 cw_term_words(uint term) { return closed_rt_term_head[term].yzw; }
public uint cw_term_arg(uint term, uint index)
{
    if (index >= cw_term_arity(term)) return RT_NONE;
    return closed_rt_term_args[closed_rt_term_meta[term].x + index];
}
public bool cw_term_closed(uint term)
{
    return (closed_rt_term_meta[term].y & (RTF_TYPE_PARAM | RTF_CONST_PARAM | RTF_SLOT)) == 0u;
}

public StructuredBuffer<uint> cw_config;
public StructuredBuffer<uint4> cw_instances;
public StructuredBuffer<uint> cw_source_routes;
public StructuredBuffer<uint> cw_catalog;
public RWStructuredBuffer<uint> cw_state;
public RWStructuredBuffer<uint4> cw_decl; // nominal atom, owner row, callable row, reserved
public RWStructuredBuffer<uint> cw_param;
public globallycoherent RWStructuredBuffer<uint> cw_atom_slots;
public globallycoherent RWStructuredBuffer<uint> cw_reach;
public globallycoherent RWStructuredBuffer<uint> cw_front;
public RWStructuredBuffer<uint4> cw_scan_low;
public RWStructuredBuffer<uint4> cw_scan_high;
public RWStructuredBuffer<uint> cw_batch;
public RWStructuredBuffer<uint> cw_routes;

// cw_state words from publish_closed_obligation_batch_counts: the batch table counts (+ table), then
// the publication words copied into the route header (obligations, atoms,
// calls, fault), and the host's bound of each table count in cw_config.
public static const uint CW_COUNTS = 32u;
public static const uint CW_PUBLISH = 50u;
public static const uint CW_FAULT = 53u;
public static const uint CW_STATE_WORDS = 64u;
public static const uint CW_PROGRAM_FAILED = 6u;
public static const uint CW_CFG_RUN = 23u;
public static const uint CW_BOUNDS = 104u;
public uint cw_lane(uint3 id) { return id.x + id.y * 16776960u; }
public uint cw_terms() { return cw_config[0]; }
public uint cw_first() { return cw_config[3]; }
public uint cw_end() { return cw_config[4]; }
public uint cw_lanes() { return cw_terms() + cw_end()-cw_first(); }
public uint cw_cat_offset(uint t) { return cw_config[32u+t]; }
public uint cw_cat_count(uint t) { return cw_config[50u+t]; }
public uint cw_batch_offset(uint t) { return cw_config[68u+t]; }
public uint cw_word(uint t,uint row,uint w) { return cw_catalog[cw_cat_offset(t)+row*cw_config[86u+t]+w]; }
public uint cw_id(uint atom,uint kind)
{
    if (atom >= cw_source_routes[RP_H_ATOMS]) return RT_INVALID;
    uint at=cw_source_routes[RP_H_ATOM_IDS]+2u*atom;
    return cw_source_routes[at]==kind ? cw_source_routes[at+1u] : RT_INVALID;
}
public uint cw_entry(uint decl)
{
    if (decl==0u || decl>=cw_config[2]) return RT_INVALID;
    uint def=closed_rt_decl_def[decl];
    if (def==0u || def>closed_rt_counts[RT_A_DIR]) return RT_INVALID;
    uint e=def-1u;
    return closed_rt_dir[e*RT_DIR_WORDS].x==decl && closed_rt_dir[e*RT_DIR_WORDS].w==RT_DIR_COMMITTED &&
        closed_rt_dir[e*RT_DIR_WORDS+3u].w==0u ? e : RT_INVALID;
}
public uint cw_predicates(uint entry)
{
    uint count=closed_rt_dir_trait[entry].y;
    uint parent=cw_entry(closed_rt_dir[entry*RT_DIR_WORDS].z);
    return count+(parent==RT_INVALID ? 0u : closed_rt_dir_trait[parent].y);
}
public bool cw_selected(uint instance)
{
    uint4 q=cw_instances[2u*instance];
    uint e=cw_entry(q.x);
    return q.x!=0u && e!=RT_INVALID && cw_predicates(e)!=0u;
}
public void cw_fail(uint code,uint lane)
{
    InterlockedOr(cw_state[0],1u << min(code,31u));
    InterlockedMin(cw_state[1],lane);
}
public void cw_mark(uint term)
{
    if (term>0u && term<RT_FIRST_TERM) return;
    if (!rt_is_stored_term(term) || term>=cw_terms() || !cw_term_closed(term))
    { cw_fail(2u,term); return; }
    uint old; InterlockedCompareExchange(cw_reach[term],0u,1u,old);
    if (old==0u) { uint at; InterlockedAdd(cw_state[2],1u,at); cw_front[at]=term; }
}
public uint4 cw_constant(uint term)
{
    uint3 w=cw_term_words(term);
    return cw_term_kind(term)==RT_KIND_CC_COUNT ? uint4(12u,12u,w.x,0u) : uint4(12u,w);
}
public uint4 cw_atom_key(uint id)
{
    if ((id & 0x80000000u)==0u) return cw_constant(id);
    uint a=id & 0x7fffffffu;
    return uint4(cw_word(1u,a,0u),cw_word(1u,a,1u),cw_word(1u,a,2u),cw_word(1u,a,3u));
}
public uint cw_atom_slot(uint4 key)
{
    uint h=rt_mix(rt_mix(rt_mix(key.x,key.y),key.z),key.w);
    uint mask=cw_config[6]-1u;
    uint at=h & mask;
    for (uint k=0u;k<=mask;k++)
    {
        uint v=cw_atom_slots[at];
        if (v==0u || all(cw_atom_key(v)==key)) return at;
        at=(at+1u)&mask;
    }
    return RT_INVALID;
}
public void cw_insert_atom(uint id)
{
    uint4 key=cw_atom_key(id);
    for (uint attempt=0u;attempt<cw_config[6];attempt++)
    {
        uint at=cw_atom_slot(key);
        if (at==RT_INVALID) break;
        uint old; InterlockedCompareExchange(cw_atom_slots[at],0u,id,old);
        if (old==0u) return;
        if (all(cw_atom_key(old)==key))
        {
            if ((id & 0x80000000u)==0u && (old & 0x80000000u)==0u) InterlockedMin(cw_atom_slots[at],id);
            return;
        }
    }
    cw_fail(3u,id);
}
public uint cw_rank(uint lane, uint column)
{
    uint4 prefix = column < 4u ? cw_scan_low[lane] : cw_scan_high[lane];
    return prefix[column & 3u];
}
public uint2 cw_ref(uint t)
{
    if (t>0u && t<RT_FIRST_TERM) return uint2(1u,t);
    if (!rt_is_stored_term(t) || t>=cw_terms() || cw_reach[t]==0u) return uint2(RT_INVALID,RT_INVALID);
    uint kind=cw_term_kind(t);
    if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT)
    {
        uint slot=cw_atom_slot(cw_constant(t));
        if (slot==RT_INVALID) return uint2(RT_INVALID,RT_INVALID);
        uint id=cw_atom_slots[slot];
        uint atom=(id & 0x80000000u)!=0u ? id & 0x7fffffffu : cw_cat_count(1u)+cw_rank(id,0u);
        return uint2(0x80000001u,atom);
    }
    return uint2(3u,cw_cat_count(5u)+cw_rank(t,1u));
}
public void cw_put(uint table,uint row,uint field,uint value)
{
    cw_batch[cw_batch_offset(table)+row*cw_config[86u+table]+field]=value;
}
public void cw_put4(uint table,uint row,uint field,uint4 value)
{
    for (uint k=0u;k<4u;k++) cw_put(table,row,field+k,value[k]);
}
