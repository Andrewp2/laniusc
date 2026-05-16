// GPU HIR value-path context marker for qualified value path consumers.
//
// Scheduling contract:
// - Dispatch after type_check_modules_10d_clear_type_path_types.slang.
// - This pass marks HIR path-expression heads whose enclosing HIR name
//   expression is a value expression. The value-path projection consumes this
//   marker to distinguish value paths from module/import metadata paths. A
//   second marker identifies the subset followed by a sibling HIR call
//   expression.
// - It does not inspect source bytes, hash token text, resolve names, or
//   perform any CPU lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;

RWStructuredBuffer<uint> module_value_path_call_head;
RWStructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> module_value_path_expr_head;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;
    if (hir_kind[i] != HIR_PATH_EXPR)
        return;

    uint token_i = hir_token_pos[i];
    uint end_i = hir_token_end[i];
    if (token_i == INVALID || end_i == INVALID || token_i >= gParams.n_tokens ||
        token_i >= end_i)
        return;

    uint name_expr = parent[i];
    if (name_expr == INVALID || name_expr >= active_hir_node_count() ||
        hir_kind[name_expr] != HIR_NAME_EXPR)
        return;

    uint name_parent = parent[name_expr];
    if (name_parent == INVALID || name_parent >= active_hir_node_count())
        return;
    uint parent_kind = hir_kind[name_parent];
    if (parent_kind == HIR_MODULE_ITEM || parent_kind == HIR_IMPORT_ITEM ||
        parent_kind == HIR_TYPE)
        return;

    module_value_path_expr_head[token_i] = 1u;

    uint call_expr = next_sibling[name_expr];
    if (call_expr != INVALID && call_expr < active_hir_node_count() &&
        hir_kind[call_expr] == HIR_CALL_EXPR)
    {
        module_value_path_call_head[token_i] = 1u;
        module_value_path_call_open[token_i] = hir_token_pos[call_expr];
    }
}
