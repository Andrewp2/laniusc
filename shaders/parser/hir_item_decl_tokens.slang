// Project parser-owned declaration target ids for HIR items.
//
// This is split from hir_item_fields to keep both shaders inside the common
// 16-storage-buffer limit. The value is a declaration identity token, not a
// backend source scan: function items publish the token recorded as their HIR
// span start by the parser, and non-declaration/module path items publish
// INVALID.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirItemDecl;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_item_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirItemDecl.uses_ll1 != 0u ? min(gHirItemDecl.n, ll1_status[5u]) : gHirItemDecl.n;
}

bool has_declaration_target(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_CONST ||
           item_kind == HIR_ITEM_KIND_FN ||
           item_kind == HIR_ITEM_KIND_EXTERN_FN ||
           item_kind == HIR_ITEM_KIND_STRUCT ||
           item_kind == HIR_ITEM_KIND_ENUM ||
           item_kind == HIR_ITEM_KIND_TYPE_ALIAS ||
           item_kind == HIR_ITEM_KIND_ENUM_VARIANT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirItemDecl.n)
        return;

    hir_item_decl_token[i] = INVALID;
    if (i >= active_node_count())
        return;

    uint item_kind = hir_item_kind[i];
    if (!has_declaration_target(item_kind))
        return;

    hir_item_decl_token[i] = hir_token_pos[i];
}
