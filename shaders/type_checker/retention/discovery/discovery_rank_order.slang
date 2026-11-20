import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_workspace;
// Complete structural order, without hashes or a recursive per-lane walk.
// Children have smaller heights and already have deterministic ranks.
int compare_term(uint a, uint b)
{
    if (a == b) return 0;
    if (a == RT_INVALID) return 1; if (b == RT_INVALID) return -1;
    uint4 x = rt_term_head[a]; uint4 y = rt_term_head[b];
    int c = dg_cmp(x.x,y.x); if(c != 0) return c;
    uint kind = x.x & 255u;
    if(kind == RT_KIND_NAMED || kind == RT_KIND_ENV) c = dg_decl_cmp(x.y,y.y);
    else c = dg_cmp(x.y,y.y);
    if(c != 0) return c;
    c = dg_cmp(x.z,y.z); if(c != 0) return c;
    c = dg_cmp(x.w,y.w); if(c != 0) return c;
    uint arity = rt_term_arity(a);
    for(uint i=0u;i<arity;i++)
    {
        uint left = rt_term_arg(a,i); uint right = rt_term_arg(b,i);
        left = left < RT_FIRST_TERM ? left : dg_term_rank[left];
        right = right < RT_FIRST_TERM ? right : dg_term_rank[right];
        c = dg_cmp(left,right); if(c != 0) return c;
    }
    return 0;
}
public struct TermOrder : IDgCompare
{
    public uint base;
    int compare(uint a, uint b) { return compare_term(a, b); }
    uint load(uint index) { return dg_term_order[base + index]; }
    void store(uint index, uint value) { dg_term_order[base + index] = value; }
}
int compare_instance(uint a,uint b)
{
    if(a==b) return 0;
    if(a==RT_INVALID) return 1; if(b==RT_INVALID) return -1;
    uint4 x=dg_instances[2u*a]; uint4 y=dg_instances[2u*b];
    int c=dg_decl_cmp(x.x,y.x);
    return c!=0 ? c : dg_cmp(dg_term_rank[x.y],dg_term_rank[y.y]);
}
public struct InstanceOrder : IDgCompare
{
    int compare(uint a, uint b) { return compare_instance(a, b); }
    uint load(uint index) { return dg_order[index]; }
    void store(uint index, uint value) { dg_order[index] = value; }
}

bool sort_blocks<C : IDgCompare>(inout StepProgram program, C order, uint count, uint span)
{
    uint group = program.lane / STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % STEP_PROGRAM_GROUP_LANES;
    uint blocks = 1u + (count - 1u) / DG_SORT_BLOCK;
    for (uint block = group; block < blocks; block += program.groups)
    {
        dg_sort_block(order, block, lane, count, span);
        GroupMemoryBarrierWithGroupSync();
    }
    return step_barrier(program);
}

public bool sort_discovery_order<C : IDgCompare>(inout StepProgram program, C order, uint count)
{
    if (count < 2u) return true;
    if (!sort_blocks(program, order, count, 0u)) return false;
    for (uint span = DG_SORT_BLOCK * 2u; span <= count; span *= 2u)
    {
        for (uint gap = span / 2u; gap >= DG_SORT_BLOCK; gap /= 2u)
        {
            for (uint row = program.lane; row < count / 2u; row += program.lanes)
            {
                uint left = (row / gap) * 2u * gap + row % gap;
                uint right = left + gap;
                uint a = order.load(left);
                uint b = order.load(right);
                bool ascending = (left & span) == 0u;
                if ((order.compare(a, b) > 0) == ascending)
                {
                    order.store(left, b);
                    order.store(right, a);
                }
            }
            if (!step_barrier(program)) return false;
        }
        if (!sort_blocks(program, order, count, span)) return false;
    }
    return true;
}
