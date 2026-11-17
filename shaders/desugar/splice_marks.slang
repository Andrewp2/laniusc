// Per source token: how many tokens it stands for after the splice. A token
// outside the machines stands for itself. The first token of a machine item
// (`pub` or `machine`) stands for the tokens generated for the machine, the
// item's other tokens for none. The first token also records where the
// machine's generated tokens start.
import gpu_index;
import machines.machine_common;
import desugar_common;

StructuredBuffer<uint> sizes;
StructuredBuffer<uint> records;
// Inclusive prefix sums: machines, states, transitions, bracket depth.
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint> machines;
StructuredBuffer<uint4> count_scan0;
StructuredBuffer<uint4> count_scan1;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint4> text_scan;
// Per machine: its first generated token, their count and its first token.
RWStructuredBuffer<uint4> machine_tokens;
// Per token: (tokens it stands for, kind, machine): kind 0 for a removed
// token, 1 for a kept one, 2 for the first token of an item.
RWStructuredBuffer<uint4> splice_marks;

static const uint SPLICE_REMOVED = 0u;
static const uint SPLICE_KEPT = 1u;
static const uint SPLICE_ITEM = 2u;

uint rec(uint token, uint word)
{
    return records[token * REC_WORDS + word];
}

uint sum4(uint4 v)
{
    return v.x + v.y + v.z + v.w;
}

// The text offset where piece `index` starts.
uint piece_start(uint index)
{
    return index == 0u ? 0u : piece_scan[index - 1u].x;
}

// The generated tokens that start before text offset `at`.
uint tokens_before(uint at)
{
    return at == 0u ? 0u : text_scan[at - 1u].x;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint tokens = sizes[S_SPLICED];
    if (t >= tokens)
        return;
    bool public_head = t + 1u < tokens && rec(t + 1u, REC_ROLE) == ROLE_MACHINE &&
                       (rec(t + 1u, REC_FLAGS) & FLAG_PUBLIC) != 0u;
    uint head = MC_NONE;
    if (public_head)
        head = t + 1u;
    else if (rec(t, REC_ROLE) == ROLE_MACHINE && (rec(t, REC_FLAGS) & FLAG_PUBLIC) == 0u)
        head = t;
    if (head != MC_NONE)
    {
        uint ordinal = scan_a[head].x - 1u;
        uint close = rec(head, REC_END) - 1u;
        uint first_piece = head == 0u ? 0u : sum4(count_scan0[head - 1u]) + sum4(count_scan1[head - 1u]);
        uint end_piece = sum4(count_scan0[close]) + sum4(count_scan1[close]);
        uint first = tokens_before(piece_start(first_piece));
        uint end = tokens_before(piece_start(end_piece));
        machine_tokens[ordinal] = uint4(first, end - first, t, 0u);
        splice_marks[t] = uint4(end - first, SPLICE_ITEM, ordinal, 0u);
        return;
    }
    uint count = scan_a[t].x;
    uint inside = count > 0u ? machines[count - 1u] : MC_NONE;
    bool removed = inside != MC_NONE && t < rec(inside, REC_END);
    splice_marks[t] = removed ? uint4(0u, SPLICE_REMOVED, 0u, 0u) : uint4(1u, SPLICE_KEPT, 0u, 0u);
}
