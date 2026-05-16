// GPU HIR enum unit-variant consumer.
//
// Scheduling contract:
// - Dispatch after value status projection and after declaration records include
//   enum variants with parent enum declaration ids.
// - Consume resolved_value_decl/status path rows produced by the sorted
//   module/import resolver.
// - For resolved, non-call HIR paths to unit enum variants, including local
//   one-segment variants and qualified module variants, project the variant
//   declaration and enum type onto the path head, then clear any fail-closed
//   value-path status for that head.
// - Tuple/payload variants are deliberately left to the enum-call and
//   match-payload consumers; this pass only consumes unit variants.
// - It does not inspect source bytes, hash token text, scan for "::", perform
//   unqualified lookup, or ask the CPU to resolve values.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> module_value_path_call_head;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;

static const uint TY_ENUM_BASE = 6144u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_hir_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_unit_enum_variant_decl(uint decl_i, out uint variant_token, out uint enum_token)
{
    variant_token = INVALID;
    enum_token = INVALID;
    uint token_i = decl_name_token[decl_i];
    if (token_i == INVALID || token_i >= active_token_count())
        return false;

    uint variant_node = decl_hir_node[decl_i];
    if (!valid_hir_node(variant_node) || hir_variant_payload_count[variant_node] != 0u)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    uint enum_start = decl_name_token[enum_decl_i];
    if (enum_start == INVALID || enum_start >= active_token_count())
        return false;

    variant_token = token_i;
    enum_token = enum_start;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;
    uint owner_token = path_owner_token[path_i];
    if (owner_token >= gParams.n_tokens)
        return;
    if (module_value_path_call_head[owner_token] != 0u)
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_VALUE ||
        decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return;

    uint variant_token;
    uint enum_token;
    if (!valid_unit_enum_variant_decl(decl_i, variant_token, enum_token))
        return;

    visible_decl[owner_token] = variant_token;
    visible_type[owner_token] = TY_ENUM_BASE + enum_token;
    module_value_path_status[owner_token] = INVALID;
}
