// Pre-resolution GPU declaration record scatter.
//
// Scheduling contract:
// - Dispatch after decl_record_flag has an exclusive GPU prefix scan.
// - This pass scatters declaration identity records from parser-owned HIR fields
//   and interned name ids.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import scatter;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_record_flag;
StructuredBuffer<uint> decl_record_prefix;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
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

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint parent_enum_decl_for_variant(uint hir_i)
{
    uint enum_node = valid_node(hir_i) ? compact_hir_core[hir_i].parent : INVALID;
    if (!valid_node(enum_node) ||
        compact_hir_payload[enum_node].a != HIR_ITEM_KIND_ENUM ||
        decl_record_flag[enum_node] == 0u)
        return INVALID;
    return decl_record_prefix[enum_node];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;

    CompactScatterSlot slot = compact_scatter_slot(decl_record_flag[i], decl_record_prefix[i]);
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
