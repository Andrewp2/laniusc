// GPU path segment count pass.
//
// Scheduling contract:
// - Dispatch after type_check_modules_01_scatter_paths.slang.
// - Count the interned-name segments in each compact path span.
// - A GPU counted prefix scan over path_segment_count must produce
//   path_segment_base before the segment scatter pass runs.
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
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> path_segment_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint PATH_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS + 1u;
static const uint PATH_SEGMENT_OVERFLOW_COUNT = PATH_SEGMENT_ROW_WIDTH + 1u;

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

uint count_segments(uint start, uint end_exclusive)
{
    if (!segment_exists(start, end_exclusive, 0u))
        return 0u;
    if (!segment_exists(start, end_exclusive, 1u))
        return 1u;
    if (!segment_exists(start, end_exclusive, 2u))
        return 2u;
    if (!segment_exists(start, end_exclusive, 3u))
        return 3u;
    if (!segment_exists(start, end_exclusive, 4u))
        return 4u;
    if (!segment_exists(start, end_exclusive, 5u))
        return 5u;
    if (!segment_exists(start, end_exclusive, 6u))
        return 6u;
    if (!segment_exists(start, end_exclusive, 7u))
        return 7u;
    if (!segment_exists(start, end_exclusive, 8u))
        return 8u;
    if (!segment_exists(start, end_exclusive, 9u))
        return 9u;
    return PATH_SEGMENT_OVERFLOW_COUNT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_slot = linear_thread_id(dtid);
    if (path_slot >= active_path_count())
        return;

    uint start = path_start[path_slot];
    uint end_exclusive = min(start + path_len[path_slot], gParams.n_tokens);
    uint count = start < end_exclusive ? count_segments(start, end_exclusive) : 0u;
    path_segment_count[path_slot] = count;
}
