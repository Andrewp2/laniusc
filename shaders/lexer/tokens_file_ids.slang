struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> source_file_count;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> source_file_len;
RWStructuredBuffer<uint> token_file_id;

static const uint INVALID = 0xffffffffu;
static const uint MAX_FILES_SCAN = 1024u;

[shader("compute")]
[numthreads(256, 1, 1)]
void tokens_file_ids(uint3 tid: SV_DispatchThreadID)
{
    uint k = tid.x;
    uint total = token_count[0];
    if (k >= total)
        return;

    uint start = tokens_out[k].start;
    uint files = min(source_file_count[0], MAX_FILES_SCAN);
    uint file_id = INVALID;
    [loop]
    for (uint f = 0u; f < files; f += 1u)
    {
        uint file_start = source_file_start[f];
        uint file_end = file_start + source_file_len[f];
        if (start >= file_start && start < file_end)
        {
            file_id = f;
            break;
        }
    }
    if (file_id == INVALID)
    {
        [loop]
        for (uint f = 0u; f < files; f += 1u)
        {
            if (start == source_file_start[f] + source_file_len[f])
            {
                file_id = f;
                break;
            }
        }
    }

    token_file_id[k] = file_id;
}
