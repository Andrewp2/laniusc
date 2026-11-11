// Per source file: its first token, the closures and captures before it,
// and the byte where `import core::function;` goes. Row `file_count` is the
// end of the pack.
import gpu_index;
import generated_token_ids;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

struct LayoutParams
{
    uint file_count;
    uint closure_count;
    uint capture_count;
    uint piece_count;
    uint byte_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<LayoutParams> gLayout;
StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<uint4> capture_scan;
StructuredBuffer<uint> source_file_start;
RWStructuredBuffer<uint4> file_info;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint file = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    if (file > gLayout.file_count)
        return;
    if (file == gLayout.file_count)
    {
        file_info[file] = uint4(count, gLayout.closure_count, gLayout.capture_count, gLayout.byte_count);
        return;
    }

    // The first token of this file or a later one.
    uint lo = 0u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (token_file_id[mid] < file)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint first = lo;
    uint closures_before = first > 0u ? depth_scan[first - 1u].y : 0u;
    uint captures_before = first > 0u ? capture_scan[first - 1u].x : 0u;

    // The import goes after the module line, or first in a file without one.
    uint import_at = source_file_start[file];
    if (first < count && token_file_id[first] == file && tokens_out[first].kind == TK_MODULE)
    {
        for (uint q = first + 1u; q < count && q < first + 256u && token_file_id[q] == file; q += 1u)
        {
            if (tk_semicolon(tokens_out[q].kind))
            {
                import_at = tokens_out[q].start + tokens_out[q].len;
                break;
            }
        }
    }
    file_info[file] = uint4(first, closures_before, captures_before, import_at);
}
