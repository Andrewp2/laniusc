import utils;

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
StructuredBuffer<uint> token_count;
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_path_start;
StructuredBuffer<uint> hir_item_path_end;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> hir_item_import_target_kind;

RWStructuredBuffer<uint> module_item_kind;
RWStructuredBuffer<uint> module_path_start;
RWStructuredBuffer<uint> module_path_end;
RWStructuredBuffer<uint> module_path_hash;
RWStructuredBuffer<uint> import_enclosing_module_token;
RWStructuredBuffer<uint> import_target_kind;

static const uint INVALID = 0xffffffffu;

static const uint MODULE_ITEM_NONE = 0u;
static const uint MODULE_ITEM_MODULE = 1u;
static const uint MODULE_ITEM_IMPORT = 2u;

static const uint IMPORT_TARGET_NONE = 0u;
static const uint IMPORT_TARGET_PATH = 1u;
static const uint IMPORT_TARGET_STRING = 2u;

static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;
static const uint HIR_ITEM_IMPORT_TARGET_STRING = 2u;

static const uint HIR_ITEM_KIND_MODULE = 1u;
static const uint HIR_ITEM_KIND_IMPORT = 2u;

static const uint TK_IDENT = 1u;
static const uint TK_STRING = 32u;
static const uint TK_COLON = 38u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

uint token_hash(uint i)
{
    uint h = 2166136261u;
    uint start = token_start(i);
    uint len = token_len(i);
    [loop]
    for (uint d = 0u; d < len; d += 1u)
    {
        h = (h ^ source_at(start, d)) * 16777619u;
    }
    return h ^ len;
}

uint path_hash(uint start_i, uint end_i)
{
    if (start_i == INVALID || end_i == INVALID || start_i > end_i)
        return 0u;

    uint h = 2166136261u;
    [loop]
    for (uint j = start_i; j <= end_i && j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (is_path_segment(kind) || kind == TK_COLON || kind == TK_STRING)
            h = (h ^ token_hash(j)) * 16777619u;
    }
    return h ^ (end_i - start_i + 1u);
}

uint item_token_for_path_start(uint path_start)
{
    if (path_start == INVALID || path_start == 0u)
        return INVALID;
    return path_start - 1u;
}

uint file_module_token(uint file_id, uint before_token)
{
    if (file_id == INVALID)
        return INVALID;

    uint n_hir = active_hir_node_count();
    [loop]
    for (uint j = 0u; j < n_hir; j += 1u)
    {
        if (hir_item_kind[j] != HIR_ITEM_KIND_MODULE || hir_item_file_id[j] != file_id)
            continue;
        uint module_token = item_token_for_path_start(hir_item_path_start[j]);
        if (module_token != INVALID && module_token < before_token)
            return module_token;
    }
    return INVALID;
}

void collect_module(uint hir_i)
{
    uint path_start_i = hir_item_path_start[hir_i];
    uint path_end_exclusive = hir_item_path_end[hir_i];
    uint item_start = item_token_for_path_start(path_start_i);
    if (item_start == INVALID || path_end_exclusive == INVALID ||
        path_start_i >= path_end_exclusive ||
        item_start >= active_token_count())
        return;
    uint path_end_i = path_end_exclusive - 1u;

    module_item_kind[item_start] = MODULE_ITEM_MODULE;
    module_path_start[item_start] = path_start_i;
    module_path_end[item_start] = path_end_i;
    module_path_hash[item_start] = path_hash(path_start_i, path_end_i);
    import_enclosing_module_token[item_start] = INVALID;
    import_target_kind[item_start] = IMPORT_TARGET_NONE;
}

void collect_import(uint hir_i)
{
    uint path_start_i = hir_item_path_start[hir_i];
    uint path_end_exclusive = hir_item_path_end[hir_i];
    uint item_start = item_token_for_path_start(path_start_i);
    if (item_start == INVALID || path_end_exclusive == INVALID ||
        path_start_i >= path_end_exclusive ||
        item_start >= active_token_count())
        return;
    uint path_end_i = path_end_exclusive - 1u;

    uint parser_target = hir_item_import_target_kind[hir_i];
    uint target_kind = parser_target == HIR_ITEM_IMPORT_TARGET_STRING ? IMPORT_TARGET_STRING :
                       parser_target == HIR_ITEM_IMPORT_TARGET_PATH ? IMPORT_TARGET_PATH :
                       IMPORT_TARGET_NONE;
    if (target_kind == IMPORT_TARGET_NONE)
        return;
    module_item_kind[item_start] = MODULE_ITEM_IMPORT;
    module_path_start[item_start] = path_start_i;
    module_path_end[item_start] = path_end_i;
    module_path_hash[item_start] = path_hash(path_start_i, path_end_i);
    import_enclosing_module_token[item_start] =
        file_module_token(hir_item_file_id[hir_i], item_start);
    import_target_kind[item_start] = target_kind;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir_i = linear_thread_id(dtid);
    if (hir_i >= active_hir_node_count())
        return;

    uint kind = hir_item_kind[hir_i];
    if (kind == HIR_ITEM_KIND_MODULE)
        collect_module(hir_i);
    else if (kind == HIR_ITEM_KIND_IMPORT)
        collect_import(hir_i);
}
