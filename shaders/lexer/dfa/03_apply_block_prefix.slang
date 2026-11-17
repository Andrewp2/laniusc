// Apply scanned DFA block prefixes and emit boundary flags/token kinds.
//
// One workgroup owns one 256-byte input block and one dispatch thread owns one
// input byte. The block's bytes go to groupshared memory; then one lane per
// chunk starts from the scanned block seed composed with the earlier chunk
// summaries and walks its chunk once, recording the DFA state before each
// byte. Every thread then evaluates its byte's emit/EOF flags from that state.

#define WORKGROUP_SIZE 256
#define N_STATES 83
#define CHUNK_COUNT 3
#define CHUNK_WIDTH_CAP ((WORKGROUP_SIZE + CHUNK_COUNT - 1) / CHUNK_COUNT)

import gpu_index;
import utils; // PF_* bits, load helpers, etc.
import generated_token_ids;

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
StructuredBuffer<uint> source_file_start_flags;
StructuredBuffer<uint> source_file_end_flags;
StructuredBuffer<uint> block_prefix_ping;
StructuredBuffer<uint> block_prefix_pong;
StructuredBuffer<uint> chunk_summaries;
StructuredBuffer<uint> token_map;
StructuredBuffer<uint> next_emit; // u16 packed: next_state (low 15) | HIGH_BIT for EMIT

RWStructuredBuffer<uint> flags_packed;
RWStructuredBuffer<uint> tok_types;
RWStructuredBuffer<uint> lex_error_offset;

// Byte in bits 0..7, FILE_START_BIT when a source file starts at the byte.
groupshared uint block_bytes[WORKGROUP_SIZE];
// DFA state before each byte of the block, before any file-start reset.
groupshared uint block_states[WORKGROUP_SIZE];

static const uint FILE_START_BIT = 0x100u;

bool is_skip(uint tk)
{
    return (tk == gParams.skip0) || (tk == gParams.skip1) || (tk == gParams.skip2) || (tk == gParams.skip3);
}

uint next_state_only(uint byte_value, uint state)
{
    return load_u16_packed(next_emit, byte_value * N_STATES + state) & 0x7FFFu;
}

bool is_file_start(uint i_abs)
{
    return source_file_start_flags[i_abs] != 0u;
}

bool is_file_end(uint i_abs)
{
    return source_file_end_flags[i_abs] != 0u;
}

bool is_decimal_digit(uint byte_value)
{
    return byte_value >= 48u && byte_value <= 57u;
}

// The input byte at i_abs, from groupshared memory inside the block that
// starts at block_base. Callers check i_abs < gParams.n.
uint byte_near(uint i_abs, uint block_base, uint block_len)
{
    return i_abs >= block_base && i_abs - block_base < block_len
               ? block_bytes[i_abs - block_base] & 0xffu
               : load_byte_at(in_bytes, i_abs);
}

// The byte tests come first: they read groupshared memory and almost always
// fail, so the file-boundary flags are read only around a real `..`.
bool starts_numeric_range(uint i_abs, uint block_base, uint block_len)
{
    return i_abs > 0u && i_abs + 2u < gParams.n &&
        byte_near(i_abs, block_base, block_len) == 46u &&
        byte_near(i_abs + 1u, block_base, block_len) == 46u &&
        is_decimal_digit(byte_near(i_abs - 1u, block_base, block_len)) &&
        is_decimal_digit(byte_near(i_abs + 2u, block_base, block_len)) &&
        !is_file_start(i_abs) && !is_file_end(i_abs) &&
        !is_file_start(i_abs + 1u) && !is_file_end(i_abs + 1u) &&
        !is_file_start(i_abs + 2u);
}

bool ends_numeric_range_operator(uint i_abs, uint block_base, uint block_len)
{
    return i_abs >= 3u && is_decimal_digit(byte_near(i_abs, block_base, block_len)) &&
        byte_near(i_abs - 1u, block_base, block_len) == 46u &&
        byte_near(i_abs - 2u, block_base, block_len) == 46u &&
        is_decimal_digit(byte_near(i_abs - 3u, block_base, block_len)) &&
        !is_file_start(i_abs - 1u) && !is_file_end(i_abs - 1u) &&
        !is_file_start(i_abs) && !is_file_end(i_abs);
}

bool block_prefix_is_pong(uint block_count)
{
    uint rounds = 0u;
    for (uint stride = 1u; stride < block_count; stride <<= 1u)
        rounds += 1u;
    return (rounds & 1u) != 0u;
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
    if (block >= nb || block_len == 0u)
        return;

    if (tIdx < block_len)
    {
        block_bytes[tIdx] = load_byte_at(in_bytes, i_abs) |
                            (is_file_start(i_abs) ? FILE_START_BIT : 0u);
    }
    GroupMemoryBarrierWithGroupSync();

    const uint chunk_width = (block_len + CHUNK_COUNT - 1u) / CHUNK_COUNT;
    if (tIdx < CHUNK_COUNT)
    {
        uint state = gParams.start_state;
        if (block > 0u)
        {
            const uint prevBase = (block - 1u) * N_STATES;
            const uint prefix_index = prevBase + state;
            state = block_prefix_is_pong(nb)
                        ? block_prefix_pong[prefix_index]
                        : block_prefix_ping[prefix_index];
        }
        const uint chunk = tIdx;
        for (uint c = 0u; c < CHUNK_COUNT; c += 1u)
        {
            if (c >= chunk)
                break;
            state = chunk_summaries[(block * CHUNK_COUNT + c) * N_STATES + state];
        }

        const uint chunk_begin = min(block_len, chunk * chunk_width);
        const uint chunk_end = min(block_len, chunk_begin + chunk_width);
        for (uint offset = 0u; offset < CHUNK_WIDTH_CAP; offset += 1u)
        {
            const uint k = chunk_begin + offset;
            if (k >= chunk_end)
                break;
            block_states[k] = state;
            const uint entry = block_bytes[k];
            if ((entry & FILE_START_BIT) != 0u)
                state = gParams.start_state;
            state = next_state_only(entry & 0xffu, state);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    if (tIdx >= block_len || i_abs >= gParams.n)
        return;

    uint state_before = block_states[tIdx];
    if ((block_bytes[tIdx] & FILE_START_BIT) != 0u)
        state_before = gParams.start_state;

    const uint b = block_bytes[tIdx] & 0xffu;
    const uint packed = load_u16_packed(next_emit, b * N_STATES + state_before);
    const bool emit_here = is_highest_bit_set(packed);
    const uint state_after = packed & 0x7FFFu;
    const bool at_eof = (i_abs + 1u == gParams.n) || is_file_end(i_abs + 1u);

    // Every malformed stream has one concrete first-failure position. Reject
    // transitions fail at the byte being consumed; a committed but incomplete
    // token at EOF fails at the exclusive file-end offset.
    const bool rejected = state_after == N_STATES - 1u;
    const bool incomplete_at_eof = at_eof && token_map[state_after] == TOKEN_INVALID;
    if (rejected || incomplete_at_eof)
    {
        uint error_offset = rejected ? i_abs : i_abs + 1u;
        uint ignored;
        // Zero is the no-error initializer. Inverting an offset lets atomicMax
        // select the earliest failure without a separate nonzero fill pass.
        InterlockedMax(lex_error_offset[0u], 0xffffffffu - error_offset, ignored);
    }

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

        const uint emit16 = (keep_emit && valid_emit) ? unpack_u16_pair_low(tk_emit) : 0xFFFFu;
        const uint eof16 = (keep_eof && valid_eof) ? unpack_u16_pair_low(tk_eof) : 0xFFFFu;
        if ((f & (PF_EMIT | PF_EOF)) != 0u)
            tok_types[i_abs] = pack_u16_pair(emit16, eof16);
    }

    // A streaming maximal-munch DFA sees `0..0` as `0.` followed by `.0`.
    // Publish the two missing byte boundaries before compaction so no source
    // byte is lost: integer end at the first dot, range end at the first digit
    // after the dots, then the ordinary integer continues to its own end.
    if (starts_numeric_range(i_abs, base, block_len) && token_map[state_before] == TK_INT)
    {
        f = PF_EMIT | PF_KEEP_EMIT;
        tok_types[i_abs] = pack_u16_pair(TK_INT, 0xFFFFu);
    }
    else if (i_abs > 0u && starts_numeric_range(i_abs - 1u, base, block_len) &&
             token_map[state_before] == TK_FLOAT)
    {
        f = 0u;
    }
    // Only repair a lexical dot, never matching bytes inside comments/strings.
    else if (ends_numeric_range_operator(i_abs, base, block_len) && token_map[state_before] == TK_DOT)
    {
        uint eof_flags = f & (PF_EOF | PF_KEEP_EOF);
        uint eof_kind = unpack_u16_pair_high(tok_types[i_abs]);
        f = PF_EMIT | PF_KEEP_EMIT | eof_flags;
        tok_types[i_abs] = pack_u16_pair(TK_DOT_DOT, eof_kind);
    }

    flags_packed[i_abs] = f;
}
