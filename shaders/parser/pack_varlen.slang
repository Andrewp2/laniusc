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
StructuredBuffer<uint> sc_offsets;   // len = n_pairs (exclusive)
StructuredBuffer<uint> emit_offsets; // len = n_pairs (exclusive)

// Single packed blob holding all 6 arrays (u32):
//  [ sc_superseq | sc_off | sc_len | pp_superseq | pp_off | pp_len ]
StructuredBuffer<uint> tables_blob;

// Outputs
RWStructuredBuffer<uint> out_sc;   // len = total_sc
RWStructuredBuffer<uint> out_emit; // len = total_emit
RWStructuredBuffer<uint> out_emit_pos; // len = total_emit

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
    if (prev >= gParams.n_kinds || thisK >= gParams.n_kinds)
        return;

    uint idx2d = prev * gParams.n_kinds + thisK;

    // Stack-change copy
    uint sco = sc_off_at(idx2d);
    uint scl = sc_len_at(idx2d);
    uint dst_sc = sc_offsets[i];

    [loop]
    for (uint k = lane; k < scl; k += WG_SIZE)
    {
        out_sc[dst_sc + k] = sc_seq_at(sco + k);
    }

    // Emit copy
    uint epo = pp_off_at(idx2d);
    uint epl = pp_len_at(idx2d);
    uint dst_emit = emit_offsets[i];

    [loop]
    for (uint k = lane; k < epl; k += WG_SIZE)
    {
        out_emit[dst_emit + k] = pp_seq_at(epo + k);
        out_emit_pos[dst_emit + k] = i;
    }
}
