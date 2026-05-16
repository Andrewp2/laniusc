// Pre-resolution GPU declaration record scatter.
//
// Scheduling contract:
// - Dispatch after decl_record_flag has an exclusive GPU prefix scan.
// - This pass scatters declaration identity records from parser-owned HIR fields
//   and interned name ids.
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

StructuredBuffer<uint> decl_record_flag;
StructuredBuffer<uint> decl_record_prefix;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_namespace;
StructuredBuffer<uint> hir_item_visibility;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> decl_module_file_id;
RWStructuredBuffer<uint> decl_name_id;
RWStructuredBuffer<uint> decl_kind;
RWStructuredBuffer<uint> decl_namespace;
RWStructuredBuffer<uint> decl_visibility;
RWStructuredBuffer<uint> decl_hir_node;
RWStructuredBuffer<uint> decl_parent_type_decl;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint name_id_for_decl(uint name_token)
{
    return name_token < gParams.n_tokens ? name_id_by_token[name_token] : INVALID;
}

uint parent_enum_decl_for_variant(uint hir_i)
{
    uint cur = hir_i;
    [loop]
    for (uint guard = 0u; guard < 16u; guard += 1u)
    {
        uint p = parent[cur];
        if (p == INVALID || p >= gParams.n_hir_nodes)
            return INVALID;
        if (hir_item_kind[p] == HIR_ITEM_KIND_ENUM && decl_record_flag[p] != 0u)
            return decl_record_prefix[p];
        cur = p;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes || decl_record_flag[i] == 0u)
        return;

    uint slot = decl_record_prefix[i];
    uint name_token = hir_item_name_token[i];
    decl_module_file_id[slot] = hir_item_file_id[i];
    decl_name_id[slot] = name_id_for_decl(name_token);
    decl_kind[slot] = hir_item_kind[i];
    decl_namespace[slot] = hir_item_namespace[i];
    decl_visibility[slot] = hir_item_visibility[i];
    decl_hir_node[slot] = i;
    decl_parent_type_decl[slot] =
        hir_item_kind[i] == HIR_ITEM_KIND_ENUM_VARIANT ? parent_enum_decl_for_variant(i) : INVALID;
}
