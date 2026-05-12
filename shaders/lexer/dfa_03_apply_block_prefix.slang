// Apply scanned DFA block prefixes and emit boundary flags/token kinds.
//
// One dispatch thread owns one input byte. It recomputes the short in-block DFA
// prefix up to that byte from the scanned block seed, then evaluates the byte's
// emit/EOF flags.

#define WORKGROUP_SIZE 256
#define N_STATES 80
#define CHUNK_COUNT 3

import utils; // PF_* bits, load helpers, etc.

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> source_file_count;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> block_prefix;
StructuredBuffer<uint> chunk_summaries;
StructuredBuffer<uint> token_map;
StructuredBuffer<uint> next_emit; // u16 packed: next_state (low 15) | HIGH_BIT for EMIT

RWStructuredBuffer<uint> flags_packed;
RWStructuredBuffer<uint> tok_types;

static const uint MAX_FILES_SCAN = 1024u;

inline bool is_skip(uint tk)
{
    return (tk == gParams.skip0) || (tk == gParams.skip1) || (tk == gParams.skip2) || (tk == gParams.skip3);
}

uint next_state_only(uint byte_value, uint state)
{
    return load_u16_packed(next_emit, byte_value * N_STATES + state) & 0x7FFFu;
}

bool is_file_start(uint i_abs)
{
    uint files = min(source_file_count[0], MAX_FILES_SCAN);
    [loop]
    for (uint f = 0u; f < files; f += 1u)
    {
        if (source_file_start[f] == i_abs)
            return true;
    }
    return false;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_03_apply_block_prefix(uint3 tid: SV_GroupThreadID,
                               uint3 /*gid*/: SV_DispatchThreadID,
                               uint3 ggrp: SV_GroupID)
{
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = (nb < 65535u) ? nb : 65535u;
    const uint block = ggrp.y * groupsX + ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint tIdx = tid.x;
    const uint i_abs = base + tIdx;

    const uint block_len = (base < gParams.n)
                               ? ((gParams.n - base) < WORKGROUP_SIZE ? (gParams.n - base) : WORKGROUP_SIZE)
                               : 0u;
    if (block >= nb || tIdx >= block_len || i_abs >= gParams.n)
        return;

    uint state_before = gParams.start_state;
    if (block > 0u)
    {
        const uint prevBase = (block - 1u) * N_STATES;
        state_before = block_prefix[prevBase + state_before];
    }

    const uint chunk_width = (block_len + CHUNK_COUNT - 1u) / CHUNK_COUNT;
    const uint chunk = min(tIdx / chunk_width, CHUNK_COUNT - 1u);
    [unroll]
    for (uint c = 0u; c < CHUNK_COUNT; c += 1u)
    {
        if (c >= chunk)
            break;
        state_before = chunk_summaries[(block * CHUNK_COUNT + c) * N_STATES + state_before];
    }

    const uint chunk_begin = min(block_len, chunk * chunk_width);
    [loop]
    for (uint k = chunk_begin; k < tIdx; k += 1u)
    {
        uint prev_abs = base + k;
        if (is_file_start(prev_abs))
            state_before = gParams.start_state;
        uint b_prev = load_byte_at(in_bytes, base + k);
        state_before = next_state_only(b_prev, state_before);
    }

    if (is_file_start(i_abs))
        state_before = gParams.start_state;

    const uint b = load_byte_at(in_bytes, i_abs);
    const uint packed = load_u16_packed(next_emit, b * N_STATES + state_before);
    const bool emit_here = is_highest_bit_set(packed);
    const uint state_after = packed & 0x7FFFu;
    const bool at_eof = (i_abs + 1u == gParams.n);

    uint f = 0u;
    if (emit_here | at_eof)
    {
        const uint tk_emit = token_map[state_before];
        const uint tk_eof = token_map[state_after];

        const bool valid_emit = (tk_emit != 0xFFFFffffu);
        const bool valid_eof = (tk_eof != 0xFFFFffffu);
        const bool eof_accept = (at_eof && valid_eof);

        const bool keep_emit = (valid_emit && !is_skip(tk_emit));
        const bool keep_eof = (valid_eof && !is_skip(tk_eof));

        f |= emit_here ? PF_EMIT : 0u;
        f |= eof_accept ? PF_EOF : 0u;
        f |= keep_emit ? PF_KEEP_EMIT : 0u;
        f |= keep_eof ? PF_KEEP_EOF : 0u;

        const uint emit16 = (keep_emit && valid_emit) ? (tk_emit & 0xFFFFu) : 0xFFFFu;
        const uint eof16 = (keep_eof && valid_eof) ? (tk_eof & 0xFFFFu) : 0xFFFFu;
        if ((f & (PF_EMIT | PF_EOF)) != 0u)
            tok_types[i_abs] = (eof16 << 16) | emit16;
    }

    flags_packed[i_abs] = f;
}
