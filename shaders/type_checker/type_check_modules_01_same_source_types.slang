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

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint MODULE_ITEM_NONE = 0u;

static const uint TK_IDENT = 1u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_LPAREN = 4u;
static const uint TK_LT = 12u;
static const uint TK_ARROW = 75u;
static const uint TK_COMMA = 36u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;

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

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    [loop]
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

bool is_type_path_segment(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

uint leading_module_decl_end()
{
    if (token_kind(0u) != TK_MODULE)
        return INVALID;

    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (token_kind(j) == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

// The parser/HIR item pass owns module/import header spans. This pass only
// skips tokens that belong to those AST-derived metadata spans.
bool token_belongs_to_module_metadata_ast_span(uint i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 0u; j < n_active; j += 1u)
    {
        if (module_item_kind[j] == MODULE_ITEM_NONE)
            continue;
        if (i == j)
            return true;
        uint start = module_path_start[j];
        uint end = module_path_end[j];
        if (start != INVALID && end != INVALID && i >= start && i <= end)
            return true;
    }
    return false;
}

bool is_qualified_type_path_head(uint i)
{
    if (i + 1u >= active_token_count() || token_kind(i) != TK_COLON ||
        token_kind(i + 1u) != TK_COLON)
        return false;
    if (i == 0u)
        return false;
    if (i >= 2u && token_kind(i - 2u) == TK_IMPORT)
        return false;
    if (i >= 3u && token_kind(i - 2u) == TK_COLON && token_kind(i - 3u) == TK_COLON)
        return false;
    uint module_end = leading_module_decl_end();
    return module_end == INVALID || i > module_end;
}

uint qualified_path_start_for_segment(uint segment_i)
{
    uint start = segment_i;
    [loop]
    for (uint guard = 0u; guard < 32u && start >= 3u; guard += 1u)
    {
        if (token_kind(start - 1u) != TK_COLON || token_kind(start - 2u) != TK_COLON ||
            !is_type_path_segment(start - 3u))
            break;
        start -= 3u;
    }
    return start;
}

uint qualified_path_end(uint start)
{
    uint n_active = active_token_count();
    uint end = start;
    [loop]
    for (uint guard = 0u; guard < 32u && end + 3u < n_active; guard += 1u)
    {
        if (token_kind(end + 1u) != TK_COLON || token_kind(end + 2u) != TK_COLON ||
            !is_type_path_segment(end + 3u))
            break;
        end += 3u;
    }
    return end;
}

bool is_qualified_type_context(uint prev)
{
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_PARAM_COMMA;
}

bool is_qualified_value_call_path(uint start)
{
    uint leaf = qualified_path_end(start);
    if (leaf <= start)
        return false;
    uint next = token_kind(leaf + 1u);
    return next == TK_CALL_LPAREN || next == TK_LPAREN;
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

uint same_source_qualified_type_leaf(uint type_i)
{
    uint module_end = leading_module_decl_end();
    if (module_end == INVALID || type_i >= active_token_count())
        return INVALID;

    uint module_seg = 1u;
    uint path_seg = type_i;
    [loop]
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (module_seg >= module_end || !is_type_path_segment(module_seg) ||
            !is_type_path_segment(path_seg) || !same_text(module_seg, path_seg))
            return INVALID;

        bool module_has_next =
            module_seg + 3u < module_end && token_kind(module_seg + 1u) == TK_COLON &&
            token_kind(module_seg + 2u) == TK_COLON && is_type_path_segment(module_seg + 3u);
        if (module_has_next)
        {
            if (path_seg + 3u >= active_token_count() ||
                token_kind(path_seg + 1u) != TK_COLON || token_kind(path_seg + 2u) != TK_COLON ||
                !is_type_path_segment(path_seg + 3u))
                return INVALID;
            module_seg += 3u;
            path_seg += 3u;
            continue;
        }

        uint leaf = path_seg + 3u;
        if (leaf >= active_token_count() || token_kind(path_seg + 1u) != TK_COLON ||
            token_kind(path_seg + 2u) != TK_COLON || !is_type_path_segment(leaf))
            return INVALID;
        if (leaf + 2u < active_token_count() && token_kind(leaf + 1u) == TK_COLON &&
            token_kind(leaf + 2u) == TK_COLON)
            return INVALID;
        return leaf;
    }
    return INVALID;
}

bool is_struct_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_STRUCT;
}

uint find_struct_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_struct_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
}

bool is_enum_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_ENUM;
}

uint find_enum_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_enum_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(tid);
    if (i >= active_token_count())
        return;

    if (token_belongs_to_module_metadata_ast_span(i))
        return;

    if (!is_qualified_type_path_head(i))
        return;
    uint start = qualified_path_start_for_segment(i - 1u);
    uint prev = start > 0u ? token_kind(start - 1u) : 0u;
    if (!is_qualified_type_context(prev))
    {
        if (is_qualified_value_call_path(start))
            return;
        record_error(i, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    uint leaf = same_source_qualified_type_leaf(i - 1u);
    if (leaf == INVALID)
    {
        record_error(i, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    uint struct_decl = find_struct_decl_name(leaf);
    if (struct_decl != INVALID)
        return;

    uint enum_decl = find_enum_decl_name(leaf);
    if (enum_decl == INVALID)
        record_error(i, ERR_UNKNOWN_TYPE, 0u);
}
