// Attach method declaration metadata from GPU module/name/type tables.
//
// The receiver type is read from parser-owned impl-node keyed HIR method rows.
// This keeps method metadata tied to parser-owned records instead of rescanning
// impl children.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> hir_method_impl_receiver_type_node;
StructuredBuffer<uint> method_decl_impl_node;
StructuredBuffer<uint> method_decl_name_token;

RWStructuredBuffer<uint> method_decl_receiver_ref_tag;
RWStructuredBuffer<uint> method_decl_receiver_ref_payload;
RWStructuredBuffer<uint> method_decl_module_id;
RWStructuredBuffer<uint> method_decl_name_id;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

uint source_file_count()
{
    return max(gParams.n_source_files, 1u);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

uint module_for_token(uint i)
{
    uint file_id = i < active_token_count() ? token_file_id[i] : INVALID;
    if (file_id == INVALID)
        return INVALID;
    if (gParams.n_hir_nodes == 0u)
        return file_id == 0u ? module_id_by_file_id[0u] : INVALID;
    uint module_id = file_id < source_file_count() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

uint name_id_for_token(uint i)
{
    return i < active_token_count() ? name_id_by_token[i] : INVALID;
}

uint impl_receiver_type_node(uint impl_node)
{
    uint receiver = valid_node(impl_node) ? hir_method_impl_receiver_type_node[impl_node] : INVALID;
    return valid_node(receiver) ? receiver : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    uint impl_node = method_decl_impl_node[i];
    if (!valid_node(impl_node))
        return;

    uint impl_token = hir_token_pos[impl_node];
    uint type_node = impl_receiver_type_node(impl_node);
    uint type_i = type_node == INVALID ? INVALID : hir_token_pos[type_node];

    method_decl_receiver_ref_tag[i] =
        type_i == INVALID || type_i >= active_token_count() ? TYPE_REF_INVALID
                                                            : type_expr_ref_tag[type_i];
    method_decl_receiver_ref_payload[i] =
        type_i == INVALID || type_i >= active_token_count() ? INVALID : type_expr_ref_payload[type_i];
    method_decl_module_id[i] = module_for_token(impl_token);
    method_decl_name_id[i] = name_id_for_token(method_decl_name_token[i]);
}
