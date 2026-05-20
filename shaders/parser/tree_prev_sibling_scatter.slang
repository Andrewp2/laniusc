// Recover parser previous-sibling records by inverting `next_sibling`.
//
// This is the Pareas-style sibling surface used by later passes instead of
// asking every consumer shader to walk sibling chains locally.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gTreePrev;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> next_sibling;

RWStructuredBuffer<uint> prev_sibling;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gTreePrev.uses_ll1 != 0u ? min(gTreePrev.n, ll1_status[5u]) : gTreePrev.n;
}

bool valid_node(uint i, uint n)
{
    return i != INVALID && i < n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint next = next_sibling[i];
    if (valid_node(next, n))
        prev_sibling[next] = i;
}
