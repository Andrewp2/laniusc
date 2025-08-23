// TB1: run the simple stack within each fixed-size block, starting from EMPTY.
// We emit only the block *end stack* summary; parents are written in TB3.

struct Params
{
    uint n;
    uint block_size;
};
ConstantBuffer<Params> gTB;

StructuredBuffer<uint> emit_stream; // [n]
StructuredBuffer<uint> prod_arity;  // [nKinds]

// End-stack summaries (CSR-style)
RWStructuredBuffer<uint> end_off;   // [numBlocks+1] exclusive offsets into end_nodes/end_rem
RWStructuredBuffer<uint> end_nodes; // concatenated nodes for each block's end-stack
RWStructuredBuffer<uint> end_rem;   // concatenated remcounts for each block's end-stack

// Scratch in LDS
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

    uint top = 0;
    for (uint i = begin; i < end; ++i)
    {
        uint ar = prod_arity[emit_stream[i]];
        if (top > 0)
        {
            uint r = s_rem[top - 1];
            s_rem[top - 1] = r - 1;
        }
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

    // write end-stack snapshot into the concatenated buffers
    uint base = end_off[b];
    for (uint k = 0; k < top; ++k)
    {
        end_nodes[base + k] = s_nodes[k];
        end_rem[base + k] = s_rem[k];
    }
    // end_off[b+1] must be prefilled on the host (or by a small prefix pass)
}
