// Publish each function's parser-owned return type node.
//
// A prior parse-tree pointer-jump pass marks, for every parse node, the nearest
// function owner and nearest return_type_opt production owner. This pass
// consumes those grammar-owned records plus HIR type records and scatters the
// preorder-first type node inside each function's return type production.
// Downstream type checking can consume the published record instead of
// searching function subtrees.
struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirFnReturnType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_fn_signature_return_owner;
StructuredBuffer<uint> hir_fn_signature_function_owner;

RWStructuredBuffer<uint> hir_fn_return_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirFnReturnType.uses_ll1 != 0u
               ? min(gHirFnReturnType.n, ll1_status[5u])
               : gHirFnReturnType.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_semantic_row(row))
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_original_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] == HIR_TYPE_FORM_NONE)
        return;

    uint return_owner = hir_fn_signature_return_owner[node];
    if (!valid_original_node(return_owner))
        return;

    uint function_owner = hir_fn_signature_function_owner[node];
    if (!valid_original_node(function_owner) || hir_kind[function_owner] != HIR_FN)
        return;

    InterlockedMin(hir_fn_return_type_node[function_owner], node);
}
