// Closed instance obligations use the admitted program catalog. This producer
// writes only batch terms, environments, calls and hard obligations. Instances
// carry no assumptions; the existing solver owns implementation selection.
__exported import type_checker.retention.retention_store;
__exported import type_checker.trait_solver.retained.route_abi;
public StructuredBuffer<uint> cw_config;
public StructuredBuffer<uint4> cw_instances;
public StructuredBuffer<uint> cw_source_routes;
public StructuredBuffer<uint> cw_catalog;
public globallycoherent RWStructuredBuffer<uint> cw_state;
public RWStructuredBuffer<uint4> cw_decl; // nominal atom, owner row, callable row, reserved
public RWStructuredBuffer<uint> cw_param;
public globallycoherent RWStructuredBuffer<uint> cw_atom_slots;
public globallycoherent RWStructuredBuffer<uint> cw_reach;
public globallycoherent RWStructuredBuffer<uint> cw_front;
public RWStructuredBuffer<uint4> cw_scan_a;
public RWStructuredBuffer<uint4> cw_scan_b;
// Per 256-lane block of the count scan: its two totals, then their
// exclusive prefixes.
public RWStructuredBuffer<uint4> cw_blocks;
public StructuredBuffer<uint2> cw_step;
public RWStructuredBuffer<uint> cw_batch;
public RWStructuredBuffer<uint> cw_routes;

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
    uint def=rt_decl_def[decl];
    if (def==0u || def>rt_counts[RT_A_DIR]) return RT_INVALID;
    uint e=def-1u;
    return rt_dir[e*RT_DIR_WORDS].x==decl && rt_dir[e*RT_DIR_WORDS].w==RT_DIR_COMMITTED &&
        rt_dir[e*RT_DIR_WORDS+3u].w==0u ? e : RT_INVALID;
}
public uint cw_predicates(uint entry)
{
    uint count=rt_dir_trait[entry].y;
    uint parent=cw_entry(rt_dir[entry*RT_DIR_WORDS].z);
    return count+(parent==RT_INVALID ? 0u : rt_dir_trait[parent].y);
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
    if (!rt_is_stored_term(term) || term>=cw_terms() || !rt_term_closed(term))
    { cw_fail(2u,term); return; }
    uint old; InterlockedCompareExchange(cw_reach[term],0u,1u,old);
    if (old==0u) { uint at; InterlockedAdd(cw_state[2],1u,at); cw_front[at]=term; }
}
public uint4 cw_constant(uint term)
{
    uint3 w=rt_term_words(term);
    return rt_term_kind(term)==RT_KIND_CC_COUNT ? uint4(12u,12u,w.x,0u) : uint4(12u,w);
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
public uint4 cw_scan(uint lane,uint part)
{
    return cw_config[7]==0u ? cw_scan_a[lane*2u+part] : cw_scan_b[lane*2u+part];
}
public uint cw_rank(uint lane,uint c) { return lane==0u ? 0u : cw_scan(lane-1u,c/4u)[c&3u]; }
public uint2 cw_ref(uint t)
{
    if (t>0u && t<RT_FIRST_TERM) return uint2(1u,t);
    if (!rt_is_stored_term(t) || t>=cw_terms() || cw_reach[t]==0u) return uint2(RT_INVALID,RT_INVALID);
    uint kind=rt_term_kind(t);
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
