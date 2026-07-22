// HIR declaration type-reference projection.
//
// This pass publishes declaration-token keyed type refs for local lets,
// constants, and named parameters. Later semantic passes consume these records
// instead of deriving declaration type heads from token offsets.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_const_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint HIR_ITEM_KIND_CONST = 3u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

uint name_or_path_token_for_node(uint node)
{
    if (!valid_compact_node(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         compact_hir_core[node].kind != HIR_PATH_EXPR))
        return INVALID;

    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

void publish_compact_decl_ref(uint decl_token, uint type_node)
{
    if (!valid_token(decl_token))
        return;
    if (!valid_compact_node(type_node))
        return;

    uint type_token = compact_hir_core[type_node].token_start;
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_INVALID)
        return;

    decl_type_ref_tag[decl_token] = tag;
    decl_type_ref_payload[decl_token] = payload;
}

void publish_decl_ref_value(uint decl_token, uint tag, uint payload)
{
    if (!valid_token(decl_token))
        return;
    if (tag == TYPE_REF_INVALID || tag == TYPE_REF_ERROR || payload == INVALID)
        return;

    decl_type_ref_tag[decl_token] = tag;
    decl_type_ref_payload[decl_token] = payload;
}

void publish_compact_stmt_decl_ref(uint node)
{
    if (!valid_compact_node(node))
        return;
    HirPayload statement = compact_hir_payload[node];
    uint kind = statement.a;
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;
    publish_compact_decl_ref(statement.b, statement.d);
}

void publish_compact_item_decl_ref(uint node)
{
    if (!valid_compact_node(node) || compact_hir_core[node].kind != HIR_CONST_ITEM)
        return;
    HirPayload item = compact_hir_payload[node];
    if (item.a != HIR_ITEM_KIND_CONST)
        return;
    publish_compact_decl_ref(item.b, compact_const_type[node]);
}

void publish_for_decl_ref(uint node)
{
    if (!valid_compact_node(node) ||
        (compact_hir_core[node].kind != HIR_STMT &&
         compact_hir_core[node].kind != HIR_FOR_STMT))
        return;

    HirPayload statement = compact_hir_payload[node];
    uint kind = statement.a;
    if (kind != STMT_RECORD_KIND_FOR)
        return;

    uint decl_token = statement.b;
    uint iterable_token = name_or_path_token_for_node(statement.c);
    uint iterable_decl = valid_token(iterable_token) ? visible_decl[iterable_token] : INVALID;
    if (!valid_token(iterable_decl))
        return;

    uint instance = decl_type_ref_payload[iterable_decl];
    if (decl_type_ref_tag[iterable_decl] != TYPE_REF_INSTANCE || !valid_token(instance))
        return;

    uint instance_kind = type_instance_kind[instance];
    if (instance_kind != TYPE_INSTANCE_ARRAY && instance_kind != TYPE_INSTANCE_SLICE)
        return;

    publish_decl_ref_value(
        decl_token,
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

void publish_param_decl_ref(uint row)
{
    uint count = min(compact_param_count[0u], gParams.n_tokens);
    if (row >= count)
        return;

    HirParam parameter = compact_params[row];
    publish_compact_decl_ref(parameter.name_token, parameter.type_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    publish_for_decl_ref(node);
    publish_compact_item_decl_ref(node);
    publish_compact_stmt_decl_ref(node);
    publish_param_decl_ref(node);
}
