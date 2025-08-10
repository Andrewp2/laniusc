// shaders/lexer.slang
// Streaming-DFA evaluation via map → inclusive prefix-scan (merge table) → classify.

struct LexParams
{
    uint n;           // number of input chars
    uint m;           // number of function ids (merge is m*m)
    uint identity_id; // function id 0 = identity
};
ConstantBuffer<LexParams> gParams;

// Tables / streams
StructuredBuffer<uint> in_bytes;      // length n, bytes as uint
StructuredBuffer<uint> char_to_func;  // 256
StructuredBuffer<uint> merge_table;   // m*m, row-major: merge[a*m + b] = (b ∘ a)
StructuredBuffer<uint> emit_on_start; // m → {0,1}
StructuredBuffer<uint> token_of;      // m → token kind or 0xFFFF_FFFF

RWStructuredBuffer<uint> f_ping;  // length n (function ids)
RWStructuredBuffer<uint> f_pong;  // length n (function ids)
RWStructuredBuffer<uint> f_final; // length n (composed prefix ids)

RWStructuredBuffer<uint> end_flags; // length n (0/1)
RWStructuredBuffer<uint> tok_types; // length n (type at boundary)

uint merge_ids(uint left_id, uint right_id)
{
    // right ∘ left
    return merge_table[left_id * gParams.m + right_id];
}

// -------------------------------------
// Stage 1: chars → unary-function ids
// -------------------------------------
[shader("compute")]
[numthreads(128, 1, 1)]
void map_chars(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint b = in_bytes[i] & 255u;
    f_ping[i] = char_to_func[b];
}

// -------------------------------------
// Stage 2: inclusive scan (Hillis–Steele)
// We can’t alias resources into locals, so branch.
// -------------------------------------
struct ScanParams
{
    uint stride;
    uint use_ping_as_src;
};
ConstantBuffer<ScanParams> gScan;

[shader("compute")]
[numthreads(128, 1, 1)]
void scan_step(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    if (gScan.use_ping_as_src != 0)
    {
        uint val = f_ping[i];
        if (i >= gScan.stride)
        {
            uint left = f_ping[i - gScan.stride];
            val = merge_ids(left, val);
        }
        f_pong[i] = val;
    }
    else
    {
        uint val = f_pong[i];
        if (i >= gScan.stride)
        {
            uint left = f_pong[i - gScan.stride];
            val = merge_ids(left, val);
        }
        f_ping[i] = val;
    }
}

// -------------------------------------
// Stage 3: compute End[i] and Type[i]
// Host copies the “winning” buffer to f_final just before this.
// -------------------------------------
[shader("compute")]
[numthreads(128, 1, 1)]
void finalize_and_post(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint fid = f_final[i];

    // End-of-token decision comes from "emit flag of the last edge in the prefix"
    end_flags[i] = emit_on_start[fid];

    // Token type at boundary uses the state BEFORE the boundary (off-by-one rule)
    uint prev = (i == 0) ? gParams.identity_id : f_final[i - 1];
    tok_types[i] = token_of[prev];
}
