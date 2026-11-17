// Per byte of generated text where a token starts: the token's row. Its
// bytes are the text bytes in the region, its kind the kind its first
// piece gives it, or a name when it joins pieces. Its file and machine are
// those of its piece's anchor token.
import gpu_index;
import generated_token_ids;
import machines.machine_common;
import desugar_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> pieces;
StructuredBuffer<uint> byte_piece;
StructuredBuffer<uint> byte_info;
StructuredBuffer<uint4> text_scan;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
RWStructuredBuffer<TokenOut> generated;
RWStructuredBuffer<uint> generated_file;
RWStructuredBuffer<uint> generated_machine;

static const uint INFO_STARTS = 2u;
static const uint INFO_CONTINUES = 4u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint at = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint region = sizes[S_REGION];
    if (at >= region || sizes[S_GENERATED] == 0u)
        return;
    uint info = byte_info[at];
    if ((info & INFO_STARTS) == 0u)
        return;
    uint piece = byte_piece[at];
    uint end = at + 1u;
    bool joined = false;
    for (; end < region; end += 1u)
    {
        if ((byte_info[end] & INFO_CONTINUES) == 0u)
            break;
        if (byte_piece[end] != piece)
            joined = true;
    }
    uint ordinal = text_scan[at].x - 1u;
    TokenOut row;
    row.kind = joined ? TK_IDENT : info >> 8u;
    row.start = sizes[S_REGION_BASE] + at;
    row.len = end - at;
    generated[ordinal] = row;
    uint anchor = pieces[piece].w;
    generated_file[ordinal] = token_file_id[anchor];
    generated_machine[ordinal] = scan_a[anchor].x - 1u;
}
