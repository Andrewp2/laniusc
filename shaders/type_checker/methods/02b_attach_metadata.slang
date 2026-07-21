// Attach method declaration metadata from GPU module/name/type tables.
//
// The receiver and owning file are read from compact method/dense-HIR records.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirMethodCore { uint node; uint owner; uint impl_node; uint name_token; };
struct HirMethodSignature
{
    uint first_param_token;
    uint impl_receiver_type;
    uint receiver_mode;
    uint metadata;
};
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> method_decl_name_token;

RWStructuredBuffer<uint> method_decl_receiver_ref_tag;
RWStructuredBuffer<uint> method_decl_receiver_ref_payload;
RWStructuredBuffer<uint> method_decl_module_id;
RWStructuredBuffer<uint> method_decl_name_id;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
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

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint source_file_count()
{
    return max(gParams.n_source_files, 1u);
}

bool valid_hir(uint i)
{
    return i != INVALID && i < active_hir_count();
}

uint name_id_for_token(uint i)
{
    return i < active_token_count() ? name_id_by_token[i] : INVALID;
}

uint module_for_file(uint file_id)
{
    if (file_id >= source_file_count())
        return INVALID;

    uint module_id = module_id_by_file_id[file_id];
    if (module_id != INVALID)
        return module_id;

    // A single source without an explicit module declaration lives in the
    // compiler's implicit root module. The module table has no source record
    // to scatter in that case, so preserve its canonical id directly.
    return file_id == 0u ? 0u : INVALID;
}

uint path_leaf_token_for_type_hir(uint type_hir)
{
    uint path = valid_hir(type_hir) ? path_id_by_owner_hir[type_hir] : INVALID;
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path >= path_count)
        return INVALID;

    uint count = path_segment_count[path];
    uint base = path_segment_base[path];
    if (count == 0u || base == INVALID)
        return INVALID;

    uint segment = base + count - 1u;
    return segment < gParams.n_hir_nodes ? path_segment_token[segment] : INVALID;
}

uint receiver_ref_token_for_type_hir(uint type_hir)
{
    uint owner_token = valid_hir(type_hir) ? compact_hir_core[type_hir].token_start : INVALID;
    uint leaf_token = path_leaf_token_for_type_hir(type_hir);

    if (owner_token < active_token_count() && type_expr_ref_tag[owner_token] == TYPE_REF_INSTANCE)
        return owner_token;
    if (leaf_token < active_token_count() && type_expr_ref_tag[leaf_token] == TYPE_REF_INSTANCE)
        return leaf_token;
    if (owner_token < active_token_count())
        return owner_token;
    return leaf_token < active_token_count() ? leaf_token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    uint method_row = method_decl_method_row[i];
    uint method_count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (method_row >= method_count)
        return;

    HirMethodCore core = compact_method_cores[method_row];
    HirMethodSignature signature = compact_method_signatures[method_row];
    if (!valid_hir(core.impl_node))
        return;
    uint type_i = receiver_ref_token_for_type_hir(signature.impl_receiver_type);

    method_decl_receiver_ref_tag[i] =
        type_i == INVALID || type_i >= active_token_count() ? TYPE_REF_INVALID
                                                            : type_expr_ref_tag[type_i];
    method_decl_receiver_ref_payload[i] =
        type_i == INVALID || type_i >= active_token_count() ? INVALID : type_expr_ref_payload[type_i];
    uint file_id = compact_hir_links[core.impl_node].file_id;
    method_decl_module_id[i] = module_for_file(file_id);
    method_decl_name_id[i] = name_id_for_token(method_decl_name_token[i]);
}
