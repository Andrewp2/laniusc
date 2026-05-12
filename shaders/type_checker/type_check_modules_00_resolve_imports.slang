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
StructuredBuffer<uint> module_item_kind;
StructuredBuffer<uint> module_path_start;
StructuredBuffer<uint> module_path_end;
StructuredBuffer<uint> module_path_hash;
StructuredBuffer<uint> import_enclosing_module_token;
StructuredBuffer<uint> import_target_kind;

RWStructuredBuffer<uint> import_resolved_module_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;

static const uint MODULE_ITEM_MODULE = 1u;
static const uint MODULE_ITEM_IMPORT = 2u;

static const uint IMPORT_TARGET_PATH = 1u;
static const uint IMPORT_TARGET_STRING = 2u;

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

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool token_text_equal(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint start_a = token_start(a);
    uint start_b = token_start(b);
    [loop]
    for (uint d = 0u; d < len; d += 1u)
    {
        if (source_at(start_a, d) != source_at(start_b, d))
            return false;
    }
    return true;
}

bool path_tokens_equal(uint left_item, uint right_item)
{
    uint left_start = module_path_start[left_item];
    uint left_end = module_path_end[left_item];
    uint right_start = module_path_start[right_item];
    uint right_end = module_path_end[right_item];
    if (left_start == INVALID || left_end == INVALID || right_start == INVALID ||
        right_end == INVALID)
        return false;
    if (left_end < left_start || right_end < right_start)
        return false;
    if ((left_end - left_start) != (right_end - right_start))
        return false;

    uint count = left_end - left_start + 1u;
    [loop]
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint a = left_start + offset;
        uint b = right_start + offset;
        if (token_kind(a) != token_kind(b) || !token_text_equal(a, b))
            return false;
    }
    return true;
}

uint find_module_for_import(uint import_i)
{
    uint n_active = active_token_count();
    uint wanted_hash = module_path_hash[import_i];
    [loop]
    for (uint module_i = 0u; module_i < n_active; module_i += 1u)
    {
        if (module_item_kind[module_i] != MODULE_ITEM_MODULE)
            continue;
        if (module_path_hash[module_i] != wanted_hash)
            continue;
        if (path_tokens_equal(import_i, module_i))
            return module_i;
    }
    return INVALID;
}

void validate_duplicate_module(uint module_i)
{
    uint n_active = active_token_count();
    uint module_hash = module_path_hash[module_i];
    [loop]
    for (uint other_i = module_i + 1u; other_i < n_active; other_i += 1u)
    {
        if (module_item_kind[other_i] != MODULE_ITEM_MODULE)
            continue;
        if (module_path_hash[other_i] == module_hash && path_tokens_equal(module_i, other_i))
        {
            record_error(other_i, ERR_BAD_HIR, MODULE_ITEM_MODULE);
            return;
        }
    }
}

void resolve_import(uint import_i)
{
    uint target_kind = import_target_kind[import_i];
    if (target_kind == IMPORT_TARGET_STRING)
    {
        record_error(import_i, ERR_BAD_HIR, IMPORT_TARGET_STRING);
        return;
    }
    if (target_kind != IMPORT_TARGET_PATH)
    {
        record_error(import_i, ERR_BAD_HIR, target_kind);
        return;
    }

    uint target_module = find_module_for_import(import_i);
    if (target_module == INVALID)
    {
        record_error(import_i, ERR_UNRESOLVED_IDENT, MODULE_ITEM_MODULE);
        return;
    }
    if (target_module == import_enclosing_module_token[import_i])
    {
        record_error(import_i, ERR_BAD_HIR, IMPORT_TARGET_PATH);
        return;
    }

    import_resolved_module_token[import_i] = target_module;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    uint kind = module_item_kind[i];
    if (kind == MODULE_ITEM_MODULE)
        validate_duplicate_module(i);
    else if (kind == MODULE_ITEM_IMPORT)
        resolve_import(i);
}
