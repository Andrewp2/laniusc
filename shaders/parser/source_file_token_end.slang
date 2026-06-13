// Publish the exclusive token end for each source-pack file.
//
// This is one thread per source token. File rows in later HIR passes consume
// this relation instead of rediscovering file bounds from parse-tree shape.

import atomics;

struct Params
{
    uint token_capacity;
};

ConstantBuffer<Params> gSourceFile;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> token_file_id;

RWStructuredBuffer<uint> source_file_token_end;

static const uint INVALID = 0xFFFFFFFFu;
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
    uint token_i = linear_thread_id(dtid);
    uint n_tokens = min(token_count[0u], gSourceFile.token_capacity);
    if (token_i >= n_tokens)
        return;

    uint file_id = token_file_id[token_i];
    if (file_id == INVALID || file_id >= gSourceFile.token_capacity)
        return;

    atomic_u32_max(source_file_token_end, file_id, token_i + 1u);
}
