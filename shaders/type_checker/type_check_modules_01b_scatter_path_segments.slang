// Pre-resolution GPU path segment metadata foundation.
//
// Scheduling contract:
// - Dispatch after type_check_modules_01_scatter_paths.slang.
// - This pass reads compact path spans and scatters path segment ids from
//   name_id_by_token into fixed-width segment slots.
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
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> path_segment_count;
RWStructuredBuffer<uint> path_segment_name_id;
RWStructuredBuffer<uint> path_segment_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

static const uint TK_IDENT = 1u;
static const uint TK_COLON = 38u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;

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
           kind == TK_LET_IDENT;
}

uint qualified_path_head_end(uint start, uint limit)
{
    if (start >= limit || !is_path_segment(token_kind(start)))
        return start;

    uint end = start + 1u;
    [loop]
    for (uint guard = 0u; guard < MAX_PATH_SEGMENTS && end + 2u < limit; guard += 1u)
    {
        if (token_kind(end) != TK_COLON || token_kind(end + 1u) != TK_COLON ||
            !is_path_segment(token_kind(end + 2u)))
            break;
        end += 3u;
    }
    return end;
}

uint path_segment_end(uint path_slot)
{
    uint start = path_start[path_slot];
    uint end_exclusive = min(start + path_len[path_slot], gParams.n_tokens);
    if (path_kind[path_slot] == PATH_RECORD_KIND_HIR_TYPE_EXPR)
        return qualified_path_head_end(start, end_exclusive);
    return end_exclusive;
}

uint count_segments(uint start, uint len)
{
    uint count = 0u;
    uint end_exclusive = min(start + len, gParams.n_tokens);
    for (uint token_i = start; token_i < end_exclusive && count < MAX_PATH_SEGMENTS; token_i += 1u)
    {
        if (name_id_by_token[token_i] != INVALID)
            count += 1u;
    }
    return count;
}

void write_segment(uint path_slot, uint segment_i)
{
    uint base = path_segment_base[path_slot];
    uint dst = base + segment_i;
    path_segment_name_id[dst] = INVALID;
    path_segment_token[dst] = INVALID;

    uint start = path_start[path_slot];
    uint end_exclusive = path_segment_end(path_slot);
    uint seen = 0u;
    for (uint token_i = start; token_i < end_exclusive && seen <= segment_i; token_i += 1u)
    {
        uint name_id = name_id_by_token[token_i];
        if (name_id == INVALID)
            continue;

        if (seen == segment_i)
        {
            path_segment_name_id[dst] = name_id;
            path_segment_token[dst] = token_i;
            return;
        }
        seen += 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint path_slot = i / MAX_PATH_SEGMENTS;
    uint segment_i = i - path_slot * MAX_PATH_SEGMENTS;
    if (path_slot >= active_path_count())
        return;

    if (segment_i == 0u)
    {
        uint start = path_start[path_slot];
        uint end_exclusive = path_segment_end(path_slot);
        uint count = start < end_exclusive ? count_segments(start, end_exclusive - start) : 0u;
        path_segment_count[path_slot] = count;
    }

    write_segment(path_slot, segment_i);
}
