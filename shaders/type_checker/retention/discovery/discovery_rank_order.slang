import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_workspace;
// Compare in the same order as the height buckets: height, then head,
// then children. Closed terms and their declaration keys are exactly
// interned, so the first unequal child determines the result.
int compare_environment(uint a, uint b)
{
    while (a != b)
    {
        if (!rt_is_stored_term(a) || !rt_is_stored_term(b)) return dg_cmp(a, b);
        int c = dg_cmp(rt_term_height(a), rt_term_height(b));
        if (c != 0) return c;
        uint4 x = rt_term_head[a];
        uint4 y = rt_term_head[b];
        c = dg_cmp(x.x, y.x);
        if (c != 0) return c;
        uint kind = x.x & 255u;
        c = kind == RT_KIND_NAMED || kind == RT_KIND_ENV
            ? dg_decl_cmp(x.y, y.y) : dg_cmp(x.y, y.y);
        if (c != 0) return c;
        c = dg_cmp(x.z, y.z);
        if (c != 0) return c;
        c = dg_cmp(x.w, y.w);
        if (c != 0) return c;
        uint arity = rt_term_arity(a);
        bool descend = false;
        for (uint i = 0u; i < arity; ++i)
        {
            uint left = rt_term_arg(a, i);
            uint right = rt_term_arg(b, i);
            if (left == right) continue;
            a = left;
            b = right;
            descend = true;
            break;
        }
        if (!descend) return 0;
    }
    return 0;
}

public int compare_instance_rows(uint4 x, uint4 y)
{
    int c = dg_decl_cmp(x.x, y.x);
    return c != 0 ? c : compare_environment(x.y, y.y);
}

int compare_instance(uint a, uint b)
{
    if (a == b) return 0;
    if (a == RT_INVALID) return 1;
    if (b == RT_INVALID) return -1;
    return compare_instance_rows(dg_instances[2u * a], dg_instances[2u * b]);
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
