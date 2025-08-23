// TB3: re-run the local stack kernel, now *seeded* with the block's true start stack,
// and write final parents.

struct Params
{
    uint n;
    uint block_size;
};
ConstantBuffer<Params> gTB;

StructuredBuffer<uint> emit_stream;
StructuredBuffer<uint> prod_arity;

StructuredBuffer<uint> start_off;
StructuredBuffer<uint> start_nodes;
StructuredBuffer<uint> start_rem;

RWStructuredBuffer<uint> node_kind; // [n]
RWStructuredBuffer<uint> parent;    // [n]

groupshared uint s_nodes[1024];
groupshared uint s_rem[1024];

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 gid: SV_GroupID)
{
    uint b = gid.x;
    uint B = gTB.block_size;
    uint begin = b * B;
    if (begin >= gTB.n)
        return;
    uint end = min(gTB.n, begin + B);

    // seed from stitched start stack
    uint s0 = start_off[b];
    uint s1 = start_off[b + 1];
    uint top = 0;
    for (uint k = s0; k < s1; ++k)
    {
        s_nodes[top] = start_nodes[k];
        s_rem[top] = start_rem[k];
        top++;
    }

    // run local stack and write parents
    for (uint i = begin; i < end; ++i)
    {
        uint kind = emit_stream[i];
        node_kind[i] = kind;

        parent[i] = (top == 0) ? 0xFFFFFFFFu : s_nodes[top - 1];
        if (top > 0)
        {
            uint r = s_rem[top - 1];
            s_rem[top - 1] = r - 1;
        }

        uint ar = prod_arity[kind];
        if (ar > 0)
        {
            s_nodes[top] = i;
            s_rem[top] = ar;
            top++;
        }
        while (top > 0 && s_rem[top - 1] == 0)
        {
            top--;
        }
    }
}
