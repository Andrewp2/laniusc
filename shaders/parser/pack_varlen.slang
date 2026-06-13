// shaders/parser/pack_varlen.slang
// Packs two dense streams in parallel, one 256-lane wave per token pair:
//  - out_sc   : stack-change codes (push=odd, pop=even) from sc_superseq
//  - out_emit : production IDs from pp_superseq

struct PackParams
{
    uint n_tokens; // includes sentinel; n_pairs = n_tokens - 1
    uint n_kinds;
    uint total_sc;   // sum over pairs of sc_len
    uint total_emit; // sum over pairs of pp_len
    uint sc_capacity; // allocated out_sc words; resident HIR path may keep this as a one-word compatibility buffer
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

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
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

uint copy_sc_pair(uint idx2d, uint lane, uint dst_sc)
{
    uint sco = sc_off_at(idx2d);
    uint scl = sc_len_at(idx2d);

    if (lane < scl)
    {
        uint dst = dst_sc + lane;
        if (dst < gParams.sc_capacity)
            out_sc[dst] = sc_seq_at(sco + lane);
    }
    return scl;
}

uint copy_emit_pair(uint idx2d, uint lane, uint dst_emit, uint emit_pos)
{
    uint epo = pp_off_at(idx2d);
    uint epl = pp_len_at(idx2d);

    if (lane < epl)
    {
        uint dst = dst_emit + lane;
        if (dst < gParams.emit_capacity)
        {
            out_emit[dst] = pp_seq_at(epo + lane);
            out_emit_pos[dst] = emit_pos;
        }
    }
    return epl;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gParams.n_tokens < 2)
        return;

    uint active_tokens = min(gParams.n_tokens, token_count[0] + 2u);
    uint n_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    uint i = linear_group_id(gid);
    uint lane = ltid.x;
    if (i >= n_pairs)
        return;

    uint prev = token_kinds[i];
    uint thisK = token_kinds[i + 1];
    if (!valid_kind(prev) || !valid_kind(thisK))
        return;

    uint dst_sc = sc_offsets[i];
    uint dst_emit = emit_offsets[i];
    uint count = min(token_count[0u], gParams.n_tokens > 2u ? gParams.n_tokens - 2u : 0u);
    if (source_file_boundary_pair(i, count))
    {
        uint close_idx = table_index(prev, 0u);
        uint open_idx = table_index(0u, thisK);
        uint first_sc_len = copy_sc_pair(close_idx, lane, dst_sc);
        uint first_emit_len = copy_emit_pair(close_idx, lane, dst_emit, i);
        if (lane >= first_sc_len)
            copy_sc_pair(open_idx, lane - first_sc_len, dst_sc + first_sc_len);
        if (lane >= first_emit_len)
            copy_emit_pair(open_idx, lane - first_emit_len, dst_emit + first_emit_len, i);
        return;
    }

    uint idx2d = table_index(prev, thisK);
    copy_sc_pair(idx2d, lane, dst_sc);
    copy_emit_pair(idx2d, lane, dst_emit, i);
}
