import shared.syntax.hir_records;
import shared.collectives.scatter;

public struct Params
{
    public uint n_tokens;
    public uint source_len;
    public uint n_hir_nodes;
};
public ConstantBuffer<Params> gParams;

public StructuredBuffer<HirLinks> compact_hir_links;
public StructuredBuffer<HirCore> compact_hir_core;
public StructuredBuffer<uint> path_id_by_owner_token;
public StructuredBuffer<uint> path_kind;
public RWStructuredBuffer<uint> module_file_id;
public RWStructuredBuffer<uint> module_path_id;
public RWStructuredBuffer<uint> module_owner_hir;
public StructuredBuffer<HirPayload> compact_hir_payload;
public RWStructuredBuffer<uint> import_module_file_id;
public RWStructuredBuffer<uint> import_path_id;
public RWStructuredBuffer<uint> import_kind;
public RWStructuredBuffer<uint> import_owner_hir;
public StructuredBuffer<uint> name_id_by_token;
public RWStructuredBuffer<uint> decl_module_file_id;
public RWStructuredBuffer<uint> decl_name_id;
public RWStructuredBuffer<uint> decl_kind;
public RWStructuredBuffer<uint> decl_namespace;
public RWStructuredBuffer<uint> decl_visibility;
public RWStructuredBuffer<uint> decl_hir_node;
public RWStructuredBuffer<uint> decl_parent_type_decl;
public RWStructuredBuffer<uint> decl_name_token;
public RWStructuredBuffer<uint> decl_token_start;
public RWStructuredBuffer<uint> decl_token_end;
public RWStructuredBuffer<uint> decl_id_by_name_token;
public StructuredBuffer<HirVariant> compact_variants;
public RWStructuredBuffer<uint> module_record_family_flag;
public RWStructuredBuffer<uint> module_record_prefix;
public RWStructuredBuffer<uint> decl_count_out;
public StructuredBuffer<uint> compact_variant_count;
public StructuredBuffer<uint> module_record_family_bits;
public StructuredBuffer<uint> hir_active_count;
public RWStructuredBuffer<uint> module_record_count_out;
public RWStructuredBuffer<uint> import_record_count_out;
public RWStructuredBuffer<uint> record_scan_group_sums;

static const uint INVALID = 0xffffffffu;
static const uint PATH_KIND_MODULE_DECL = 1u;
static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;
static const uint PATH_KIND_IMPORT = 2u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;

public void scatter_module_records(uint i, uint module_capacity)
{
    CompactScatterSlot slot = compact_scatter_slot(module_record_family_flag[i], module_record_prefix[i]);
    if (slot.active == 0u || slot.dst >= module_capacity)
        return;

    // The compact scatter writes every live destination.
    module_file_id[slot.dst] = compact_hir_links[i].file_id;
    HirCore core = compact_hir_core[i];
    uint path_id = INVALID;
    for (uint token = core.token_start;
         token < core.token_end && token < gParams.n_tokens;
         token += 1u)
    {
        uint candidate = path_id_by_owner_token[token];
        if (candidate != INVALID && path_kind[candidate] == PATH_KIND_MODULE_DECL)
        {
            path_id = candidate;
            break;
        }
    }
    module_path_id[slot.dst] = path_id;
    module_owner_hir[slot.dst] = i;
}

public void scatter_import_records(uint i)
{
    CompactScatterSlot slot = compact_scatter_slot(module_record_family_flag[i], module_record_prefix[i]);
    if (slot.active == 0u)
        return;

    uint kind = compact_hir_payload[i].d;
    HirCore core = compact_hir_core[i];
    uint path_id = INVALID;
    for (uint token = core.token_start;
         token < core.token_end && token < gParams.n_tokens;
         token += 1u)
    {
        uint candidate = path_id_by_owner_token[token];
        if (candidate != INVALID && path_kind[candidate] == PATH_KIND_IMPORT)
        {
            path_id = candidate;
            break;
        }
    }
    import_module_file_id[slot.dst] = compact_hir_links[i].file_id;
    import_path_id[slot.dst] = kind == HIR_ITEM_IMPORT_TARGET_PATH
        ? path_id
        : INVALID;
    import_kind[slot.dst] = kind;
    import_owner_hir[slot.dst] = i;
}

uint name_id_for_decl(uint name_token)
{
    return name_token < gParams.n_tokens ? name_id_by_token[name_token] : INVALID;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint parent_enum_decl_for_variant(uint hir_i)
{
    uint enum_node = valid_node(hir_i) ? compact_hir_core[hir_i].parent : INVALID;
    if (!valid_node(enum_node) ||
        compact_hir_payload[enum_node].a != HIR_ITEM_KIND_ENUM ||
        module_record_family_flag[enum_node] == 0u)
        return INVALID;
    return module_record_prefix[enum_node];
}

public void scatter_decl_core_records(uint i)
{
    CompactScatterSlot slot = compact_scatter_slot(module_record_family_flag[i], module_record_prefix[i]);
    if (slot.active == 0u)
        return;

    HirPayload payload = compact_hir_payload[i];
    uint name_token = payload.b;
    decl_module_file_id[slot.dst] = compact_hir_links[i].file_id;
    decl_name_id[slot.dst] = name_id_for_decl(name_token);
    decl_kind[slot.dst] = payload.a;
    decl_namespace[slot.dst] = payload.c;
    decl_visibility[slot.dst] = payload.d;
    decl_hir_node[slot.dst] = i;
    decl_parent_type_decl[slot.dst] =
        payload.a == HIR_ITEM_KIND_ENUM_VARIANT ? parent_enum_decl_for_variant(i) : INVALID;
}

public void scatter_decl_span_records(uint i)
{
    CompactScatterSlot slot = compact_scatter_slot(module_record_family_flag[i], module_record_prefix[i]);
    if (slot.active == 0u)
        return;

    HirCore core = compact_hir_core[i];
    uint name_token = compact_hir_payload[i].b;
    decl_name_token[slot.dst] = name_token;
    decl_token_start[slot.dst] = core.token_start;
    decl_token_end[slot.dst] = core.token_end;
    if (name_token < gParams.n_tokens)
        decl_id_by_name_token[name_token] = slot.dst;
}

uint parent_enum_decl(uint owner)
{
    if (owner >= gParams.n_hir_nodes ||
        compact_hir_payload[owner].a != HIR_ITEM_KIND_ENUM ||
        module_record_family_flag[owner] == 0u)
        return INVALID;
    return module_record_prefix[owner];
}

public void scatter_variant_decl_records(uint variant_i, uint core_count)
{
    uint dst = core_count + variant_i;
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
