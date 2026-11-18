// Clear parser previous-sibling records before the scatter pass.
//
// The next-sibling relation is already recovered by `tree_spans`. Previous
// siblings are the inverse relation, but scatter writes need a separate clear
// pass so first children do not keep stale values from reused buffers.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gTreePrev;

RWStructuredBuffer<uint> prev_sibling;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gTreePrev.n)
        return;

    prev_sibling[i] = INVALID;
}
