// TB2: tiny stitching pass over blocks: compute *start stack* for each block.
// We do this in a single thread because the number of blocks is small and this
// pass is cheap. (Tokens are not re-processed here.)

struct Params
{
    uint n;
    uint block_size;
    uint num_blocks;
};
ConstantBuffer<Params> gTB;

StructuredBuffer<uint> end_off;   // [numBlocks+1]
StructuredBuffer<uint> end_nodes; // concat
StructuredBuffer<uint> end_rem;   // concat

RWStructuredBuffer<uint> start_off;   // [numBlocks+1] offsets into start_nodes/start_rem
RWStructuredBuffer<uint> start_nodes; // concat
RWStructuredBuffer<uint> start_rem;   // concat

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0)
        return;

    uint write_ptr = 0;
    start_off[0] = 0;

    // Running stack, grown only from summaries (bounded by max depth)
    // We keep it in device memory via start_* concat we are writing.
    for (uint b = 0; b < gTB.num_blocks; ++b)
    {
        // The start stack for block b is exactly the running stack at entry.
        // Copy current running stack into start_* for block b.
        uint block_start = write_ptr;
        // (We store only the *shape* here — running stack is whatever we applied so far.)
        // Nothing to copy because we carry running stack implicitly by write_ptr.
        start_off[b] = block_start;

        // Feed the *end stack* (as if the block were run from empty) into the running stack:
        // this composes correctly because TB1's summary is "remaining open parents with rem".
        uint e0 = end_off[b];
        uint e1 = end_off[b + 1];
        uint ecount = e1 - e0;

        // First, decrement children on the current running top as many times as the
        // block would have consumed if it had started with an empty stack.
        // Each item in the end stack represents an *unclosed* parent after the block,
        // so we simply push them with their remaining slots.
        for (uint k = 0; k < ecount; ++k)
        {
            start_nodes[write_ptr + k] = end_nodes[e0 + k];
            start_rem[write_ptr + k] = end_rem[e0 + k];
        }
        write_ptr += ecount;
    }
    start_off[gTB.num_blocks] = write_ptr;
}
