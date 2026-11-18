// shaders/parser/pack_varlen.slang
// Packs two dense streams in parallel, one GPU thread per token pair:
//  - out_sc   : stack-change codes (push=odd, pop=even) from sc_superseq
//  - out_emit : production IDs from pp_superseq
//
// Each thread finds its pair's one or two table runs. The workgroup then
// copies its 256 pairs' contiguous output range together: lane k writes
// output words k, k + 256, ..., and finds the pair that owns a word by a
// binary search over the pairs' output starts. A thread copying its own runs
// would store to a different word span in every lane of a warp.

struct PackParams
{
    uint n_tokens; // includes sentinel; n_pairs = n_tokens - 1
    uint n_kinds;
    uint total_sc;   // sum over pairs of sc_len
    uint total_emit; // sum over pairs of pp_len
    uint sc_capacity; // allocated out_sc words; resident HIR path may keep this as one placeholder word
    uint emit_capacity; // allocated production-stream words

    // Offsets (in u32 elements) into tables_blob:
    uint sc_superseq_off;
    uint sc_off_off;
    uint sc_len_off;
    uint pp_superseq_off;
    uint pp_off_off;
    uint pp_len_off;
};

ConstantBuffer<PackParams> gParams;

// Inputs
StructuredBuffer<uint> token_kinds;  // len = n_tokens
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> sc_offsets;   // len = n_pairs (exclusive)
StructuredBuffer<uint> emit_offsets; // len = n_pairs (exclusive)

// Single packed blob holding all 6 arrays (u32):
//  [ sc_superseq | sc_off | sc_len | pp_superseq | pp_off | pp_len ]
StructuredBuffer<uint> tables_blob;

// Outputs
RWStructuredBuffer<uint> out_sc;   // len = total_sc
RWStructuredBuffer<uint> out_emit; // len = emit_capacity
RWStructuredBuffer<uint> out_emit_pos; // len = emit_capacity

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * WG_SIZE + ltid.x;
}

// ----- Small helpers into the packed blob -----
uint tbl_at(uint base, uint i)
{
    return tables_blob[base + i];
}

uint sc_off_at(uint idx2d)
{
    return tbl_at(gParams.sc_off_off, idx2d);
}
uint sc_len_at(uint idx2d)
{
    return tbl_at(gParams.sc_len_off, idx2d);
}
uint sc_seq_at(uint i)
{
    return tbl_at(gParams.sc_superseq_off, i);
}

uint pp_off_at(uint idx2d)
{
    return tbl_at(gParams.pp_off_off, idx2d);
}
uint pp_len_at(uint idx2d)
{
    return tbl_at(gParams.pp_len_off, idx2d);
}
uint pp_seq_at(uint i)
{
    return tbl_at(gParams.pp_superseq_off, i);
}

bool valid_kind(uint kind)
{
    return kind < gParams.n_kinds;
}

bool is_generic_shr(uint raw_i) { return (token_kinds[raw_i + 1u] & 0x80000000u) != 0u; }
uint generic_shr_inner(uint raw_i) { return token_kinds[raw_i + 1u] & 0x7fffu; }
uint generic_shr_outer(uint raw_i) { return (token_kinds[raw_i + 1u] >> 15u) & 0x7fffu; }

uint table_index(uint prev_kind, uint this_kind)
{
    return prev_kind * gParams.n_kinds + this_kind;
}

bool source_file_boundary_pair(uint pair_i, uint token_count_value)
{
    if (pair_i == 0u || pair_i >= token_count_value)
        return false;

    uint prev_file = token_file_id[pair_i - 1u];
    uint this_file = token_file_id[pair_i];
    return prev_file != 0xffffffffu &&
           this_file != 0xffffffffu &&
           prev_file != this_file;
}

static const uint NO_RUN = 0xffffffffu;

// Per-lane pair runs: output start (from the offsets scan), first run's
// table index and length, second run's table index (NO_RUN when absent) and
// the total length.
groupshared uint g_sc_start[WG_SIZE];
groupshared uint g_sc_first_len[WG_SIZE];
groupshared uint g_sc_total[WG_SIZE];
groupshared uint g_emit_start[WG_SIZE];
groupshared uint g_emit_first_len[WG_SIZE];
groupshared uint g_emit_total[WG_SIZE];
groupshared uint g_first_idx[WG_SIZE];
groupshared uint g_second_idx[WG_SIZE];
groupshared uint g_sc_end;
groupshared uint g_emit_end;

// The last lane whose output starts at or before `pos`. Starts are an
// exclusive prefix over the lanes, so they never decrease.
uint owner_lane(uint pos, bool emit)
{
    uint lo = 0u;
    uint hi = WG_SIZE - 1u;
    while (lo < hi)
    {
        uint mid = (lo + hi + 1u) >> 1u;
        uint start = emit ? g_emit_start[mid] : g_sc_start[mid];
        if (start <= pos)
            lo = mid;
        else
            hi = mid - 1u;
    }
    return lo;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gParams.n_tokens < 2)
        return;

    uint lane = ltid.x;
    uint active_tokens = min(gParams.n_tokens, token_count[0] + 2u);
    uint n_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    uint i = linear_thread_id(gid, ltid);
    uint pair_base = i - lane;

    uint first_idx = NO_RUN;
    uint second_idx = NO_RUN;
    uint sc_start = NO_RUN;
    uint emit_start = NO_RUN;
    if (i < n_pairs)
    {
        sc_start = sc_offsets[i];
        emit_start = emit_offsets[i];
        uint count = min(token_count[0u], gParams.n_tokens > 2u ? gParams.n_tokens - 2u : 0u);
        uint prev = token_kinds[i];
        uint thisK = token_kinds[i + 1];
        bool prev_is_generic_shr = i > 0u && is_generic_shr(i - 1u);
        bool this_is_generic_shr = i < count && is_generic_shr(i);
        if (prev_is_generic_shr)
            prev = generic_shr_outer(i - 1u);
        uint checked_this = this_is_generic_shr ? generic_shr_inner(i) : thisK;
        if (valid_kind(prev) && valid_kind(checked_this))
        {
            if (source_file_boundary_pair(i, count))
            {
                first_idx = table_index(prev, 0u);
                second_idx = table_index(0u, thisK);
            }
            else if (this_is_generic_shr)
            {
                uint inner = generic_shr_inner(i);
                uint outer = generic_shr_outer(i);
                first_idx = table_index(prev, inner);
                second_idx = table_index(inner, outer);
            }
            else
            {
                first_idx = table_index(prev, thisK);
            }
        }
    }

    uint sc_first = first_idx != NO_RUN ? sc_len_at(first_idx) : 0u;
    uint sc_second = second_idx != NO_RUN ? sc_len_at(second_idx) : 0u;
    uint emit_first = first_idx != NO_RUN ? pp_len_at(first_idx) : 0u;
    uint emit_second = second_idx != NO_RUN ? pp_len_at(second_idx) : 0u;
    g_sc_start[lane] = sc_start;
    g_sc_first_len[lane] = sc_first;
    g_sc_total[lane] = sc_first + sc_second;
    g_emit_start[lane] = emit_start;
    g_emit_first_len[lane] = emit_first;
    g_emit_total[lane] = emit_first + emit_second;
    g_first_idx[lane] = first_idx;
    g_second_idx[lane] = second_idx;
    if (lane == 0u)
    {
        g_sc_end = 0u;
        g_emit_end = 0u;
    }
    GroupMemoryBarrierWithGroupSync();
    if (first_idx != NO_RUN)
    {
        InterlockedMax(g_sc_end, sc_start + sc_first + sc_second);
        InterlockedMax(g_emit_end, emit_start + emit_first + emit_second);
    }
    GroupMemoryBarrierWithGroupSync();

    // Lane 0 holds the group's first pair, so its start is the lowest.
    if (g_sc_start[0] != NO_RUN)
    {
        uint begin = g_sc_start[0];
        uint end = min(g_sc_end, gParams.sc_capacity);
        for (uint pos = begin + lane; pos < end; pos += WG_SIZE)
        {
            uint owner = owner_lane(pos, false);
            uint offset = pos - g_sc_start[owner];
            if (offset >= g_sc_total[owner])
                continue;
            uint first_len = g_sc_first_len[owner];
            uint idx = offset < first_len ? g_first_idx[owner] : g_second_idx[owner];
            uint k = offset < first_len ? offset : offset - first_len;
            out_sc[pos] = sc_seq_at(sc_off_at(idx) + k);
        }
    }
    if (g_emit_start[0] != NO_RUN)
    {
        uint begin = g_emit_start[0];
        uint end = min(g_emit_end, gParams.emit_capacity);
        for (uint pos = begin + lane; pos < end; pos += WG_SIZE)
        {
            uint owner = owner_lane(pos, true);
            uint offset = pos - g_emit_start[owner];
            if (offset >= g_emit_total[owner])
                continue;
            uint first_len = g_emit_first_len[owner];
            uint idx = offset < first_len ? g_first_idx[owner] : g_second_idx[owner];
            uint k = offset < first_len ? offset : offset - first_len;
            out_emit[pos] = pp_seq_at(pp_off_at(idx) + k);
            out_emit_pos[pos] = pair_base + owner;
        }
    }
}
