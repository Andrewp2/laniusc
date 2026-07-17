// Mark compact-HIR value paths and calls for downstream value consumers.
//
// Paths, their owners, and call callees all use dense compact-HIR ids. The
// token-indexed call summary is retained only as a migration bridge for the
// downstream call passes that have not yet moved to compact call-argument
// rows; it is never used to discover whether a path is a call.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint4> call_arg_record;

RWStructuredBuffer<uint> module_value_path_call_head;
RWStructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> module_value_path_call_path_id;
RWStructuredBuffer<uint> module_value_path_call_leaf;
RWStructuredBuffer<uint> module_value_path_associated_method_token;
RWStructuredBuffer<uint> module_value_path_associated_receiver_token;
RWStructuredBuffer<uint> module_value_path_expr_head;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_CALL_EXPR = 19u;
static const uint PATH_KIND_VALUE = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_path_count() { return min(path_count_out[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_path(uint path) { return path != INVALID && path < active_path_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint path_for_callee(uint callee)
{
    if (!valid_hir(callee))
        return INVALID;
    uint path = path_id_by_owner_hir[callee];
    if (valid_path(path))
        return path;

    // A name expression normally owns its compact path directly. Preserve
    // the equally valid representation where its durable path child owns it.
    uint child = compact_hir_links[callee].first_child;
    return valid_hir(child) ? path_id_by_owner_hir[child] : INVALID;
}

uint path_leaf_token(uint path)
{
    uint count = valid_path(path) ? path_segment_count[path] : 0u;
    if (count == 0u)
        return INVALID;
    uint row = path_segment_base[path] + count - 1u;
    return row < gParams.n_tokens ? path_segment_token[row] : INVALID;
}

uint path_receiver_token(uint path, uint leaf_token)
{
    uint count = valid_path(path) ? path_segment_count[path] : 0u;
    if (count <= 1u)
        return leaf_token;
    uint row = path_segment_base[path] + count - 2u;
    uint token = row < gParams.n_tokens ? path_segment_token[row] : INVALID;
    return valid_token(token) ? token : leaf_token;
}

void mark_value_path(uint path)
{
    if (!valid_path(path) || path_kind[path] != PATH_KIND_VALUE)
        return;
    uint owner_token = path_owner_token[path];
    if (valid_token(owner_token))
        module_value_path_expr_head[owner_token] = 1u;
}

void mark_value_call(uint call_node)
{
    if (!valid_hir(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;
    uint path = path_for_callee(compact_hir_payload[call_node].a);
    if (!valid_path(path) || path_kind[path] != PATH_KIND_VALUE)
        return;

    uint owner_token = path_owner_token[path];
    uint call_token = compact_hir_core[call_node].token_start;
    if (!valid_token(owner_token) || !valid_token(call_token))
        return;

    module_value_path_expr_head[owner_token] = 1u;

    // This field still carries a raw call id. Keep it behind this explicit
    // compatibility boundary until the downstream call-row migration.
    uint legacy_call_node = call_arg_record[owner_token].z;
    module_value_path_call_head[owner_token] =
        legacy_call_node != INVALID ? legacy_call_node + 1u : 1u;
    module_value_path_call_open[owner_token] = call_token;
    module_value_path_call_path_id[owner_token] = path;
    module_value_path_call_path_id[call_token] = path;

    uint leaf_token = path_leaf_token(path);
    if (!valid_token(leaf_token))
        return;
    module_value_path_call_path_id[leaf_token] = path;
    module_value_path_call_leaf[leaf_token] = 1u;
    if (leaf_token != owner_token)
    {
        uint receiver_token = path_receiver_token(path, leaf_token);
        module_value_path_associated_method_token[owner_token] = leaf_token;
        module_value_path_associated_method_token[leaf_token] = leaf_token;
        module_value_path_associated_receiver_token[leaf_token] = receiver_token;
        if (valid_token(receiver_token))
            module_value_path_call_path_id[receiver_token] = path;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row < active_path_count())
        mark_value_path(row);
    if (row < active_hir_count())
        mark_value_call(row);
}
