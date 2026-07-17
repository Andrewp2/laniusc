// Scatter compact enum variants into the declaration table.
//
// Variants are family rows, not grammar/HIR-item rediscoveries. Their owner is
// a dense enum HIR ID, so the core declaration prefix directly identifies the
// parent enum declaration record. `decl_hir_node` is kind-dependent during the
// migration: ordinary declarations store a dense HIR ID and variants store a
// compact variant-family row.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> decl_record_flag;
StructuredBuffer<uint> decl_record_prefix;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> decl_module_file_id;
RWStructuredBuffer<uint> decl_name_token;
RWStructuredBuffer<uint> decl_name_id;
RWStructuredBuffer<uint> decl_kind;
RWStructuredBuffer<uint> decl_namespace;
RWStructuredBuffer<uint> decl_visibility;
RWStructuredBuffer<uint> decl_hir_node;
RWStructuredBuffer<uint> decl_parent_type_decl;
RWStructuredBuffer<uint> decl_token_start;
RWStructuredBuffer<uint> decl_token_end;
RWStructuredBuffer<uint> decl_id_by_name_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_variant_count()
{
    return min(compact_variant_count[0u], gParams.n_hir_nodes);
}

uint core_decl_count()
{
    uint total = min(decl_count_out[0u], gParams.n_hir_nodes);
    uint variants = active_variant_count();
    return total >= variants ? total - variants : 0u;
}

uint parent_enum_decl(uint owner)
{
    if (owner >= gParams.n_hir_nodes ||
        compact_hir_payload[owner].a != HIR_ITEM_KIND_ENUM ||
        decl_record_flag[owner] == 0u)
        return INVALID;
    return decl_record_prefix[owner];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint variant_i = linear_thread_id(dtid);
    uint variant_count = active_variant_count();
    if (variant_i >= variant_count)
        return;

    uint dst = core_decl_count() + variant_i;
    if (dst >= gParams.n_hir_nodes)
        return;

    HirVariant variant = compact_variants[variant_i];
    uint parent_decl = parent_enum_decl(variant.owner);
    uint name_token = variant.name_token;
    uint visibility = variant.owner < gParams.n_hir_nodes
        ? compact_hir_payload[variant.owner].d
        : 0u;

    decl_module_file_id[dst] = variant.file_id;
    decl_name_token[dst] = name_token;
    decl_name_id[dst] = name_token < gParams.n_tokens
        ? name_id_by_token[name_token]
        : INVALID;
    decl_kind[dst] = HIR_ITEM_KIND_ENUM_VARIANT;
    decl_namespace[dst] = HIR_ITEM_NAMESPACE_VALUE;
    decl_visibility[dst] = visibility;
    decl_hir_node[dst] = variant_i;
    decl_parent_type_decl[dst] = parent_decl;
    decl_token_start[dst] = name_token;
    decl_token_end[dst] = name_token < gParams.n_tokens ? name_token + 1u : INVALID;
    if (name_token < gParams.n_tokens)
        decl_id_by_name_token[name_token] = dst;
}
