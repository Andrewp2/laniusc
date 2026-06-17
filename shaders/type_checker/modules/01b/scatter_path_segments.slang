// Pre-resolution GPU path segment metadata foundation.
//
// Scheduling contract:
// - Dispatch after type_check_modules_01b_count_path_segments.slang and a GPU
//   counted prefix scan over path_segment_count.
// - This pass reads compact path spans and scatters path segment ids from
//   name_id_by_token into packed segment slots.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_start;
StructuredBuffer<uint> path_len;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> path_segment_name_id;
RWStructuredBuffer<uint> path_segment_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_IDENT = 1u;
static const uint TK_COLON = 38u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PATH_GENERIC_IDENT = 187u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint token_kind(uint i)
{
    return i < gParams.n_tokens ? token_words[i].kind : 0u;
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT || kind == TK_PATH_GENERIC_IDENT;
}

bool segment_exists(uint start, uint end_exclusive, uint segment_i)
{
    uint token_i = start + segment_i * 3u;
    if (token_i >= end_exclusive || name_id_by_token[token_i] == INVALID ||
        !is_path_segment(token_kind(token_i)))
        return false;

    if (segment_i == 0u)
        return true;

    uint sep = token_i - 2u;
    return token_kind(sep) == TK_COLON && token_kind(sep + 1u) == TK_COLON;
}

uint segment_token(uint start, uint end_exclusive, uint segment_i)
{
    return segment_exists(start, end_exclusive, segment_i) ? start + segment_i * 3u : INVALID;
}

void write_segment(uint path_slot, uint segment_i)
{
    uint base = path_segment_base[path_slot];
    uint dst = base + segment_i;
    if (dst >= gParams.n_tokens)
        return;
    path_segment_name_id[dst] = INVALID;
    path_segment_token[dst] = INVALID;

    uint start = path_start[path_slot];
    uint end_exclusive = min(start + path_len[path_slot], gParams.n_tokens);
    uint token_i = segment_token(start, end_exclusive, segment_i);
    if (token_i == INVALID)
        return;

    path_segment_name_id[dst] = name_id_by_token[token_i];
    path_segment_token[dst] = token_i;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_slot = linear_thread_id(dtid);
    if (path_slot >= active_path_count())
        return;

    uint count = path_segment_count[path_slot];
    [loop]
    for (uint segment_i = 0u; segment_i < count; segment_i += 1u)
        write_segment(path_slot, segment_i);
}
