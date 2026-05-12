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
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_item_namespace;
StructuredBuffer<uint> hir_item_visibility;
StructuredBuffer<uint> hir_item_file_id;

RWStructuredBuffer<uint> decl_item_kind;
RWStructuredBuffer<uint> decl_name_hash;
RWStructuredBuffer<uint> decl_name_len;
RWStructuredBuffer<uint> decl_namespace;
RWStructuredBuffer<uint> decl_visibility;
RWStructuredBuffer<uint> decl_file_id;
RWStructuredBuffer<uint> decl_hir_node;

static const uint INVALID = 0xffffffffu;

static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;

static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

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

bool is_declaration_item(uint kind)
{
    return kind == HIR_ITEM_KIND_CONST || kind == HIR_ITEM_KIND_FN ||
           kind == HIR_ITEM_KIND_EXTERN_FN || kind == HIR_ITEM_KIND_STRUCT ||
           kind == HIR_ITEM_KIND_ENUM || kind == HIR_ITEM_KIND_TYPE_ALIAS;
}

void collect_declaration(uint hir_i)
{
    uint name_i = hir_item_name_token[hir_i];
    if (name_i == INVALID || name_i >= active_token_count())
        return;

    uint namespace = hir_item_namespace[hir_i];
    if (namespace != HIR_ITEM_NAMESPACE_VALUE && namespace != HIR_ITEM_NAMESPACE_TYPE)
        return;

    decl_item_kind[name_i] = hir_item_kind[hir_i];
    decl_name_hash[name_i] = token_hash(name_i);
    decl_name_len[name_i] = token_len(name_i);
    decl_namespace[name_i] = namespace;
    decl_visibility[name_i] = hir_item_visibility[hir_i];
    decl_file_id[name_i] = hir_item_file_id[hir_i];
    decl_hir_node[name_i] = hir_i;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir_i = linear_thread_id(dtid);
    if (hir_i >= active_hir_node_count())
        return;

    if (is_declaration_item(hir_item_kind[hir_i]))
        collect_declaration(hir_i);
}
