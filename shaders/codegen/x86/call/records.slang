import utils;
import gpu_index;
import status;
import atomics;

// Direct x86_64 call-record projection.
//
// This pass projects parser-owned call nodes, resolver-owned call targets, and
// type-check return metadata into backend call records. It deliberately does
// not lower calls yet; later x86 ABI and instruction planning passes consume
// these rows instead of rediscovering call syntax.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
    uint scalar_inst_capacity;
    uint call_count;
    uint param_count;
    uint dependency_declaration_count;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> x86_compact_executable_raw;
StructuredBuffer<uint> x86_compact_expr_wrapper;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> method_decl_receiver_mode;

RWStructuredBuffer<uint4> x86_call_record;
RWStructuredBuffer<uint> x86_call_type_record;
RWStructuredBuffer<uint> x86_call_callee_root_call;
RWStructuredBuffer<uint> call_record_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_ERR_CALL_RECORDS = 62u;
static const uint X86_CALL_RECORD_ERROR_DENSE_MAPPING = 1u;
static const uint X86_CALL_RECORD_ERROR_CALLEE = 2u;
static const uint X86_CALL_RECORD_ERROR_SLOT = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;
static const uint X86_CALL_TARGET_DEPENDENCY_TAG = 0x80000000u;
static const uint X86_CALL_TARGET_DEPENDENCY_PAYLOAD_MASK = 0x7fffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node_i)
{
    return valid_index_or_invalid(node_i, active_hir_node_count(), INVALID);
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_dense(uint hir)
{
    return hir != INVALID && hir < active_compact_hir_count();
}

bool valid_token(uint token_i)
{
    return valid_index_or_invalid(token_i, gParams.n_tokens, INVALID);
}

uint raw_for_dense(uint hir)
{
    if (!valid_dense(hir))
        return INVALID;
    // Callee ownership must start at the same-kind executable row. Generic
    // HIR_EXPR forwarding wrappers can share a dense identity with a larger
    // surrounding expression and would suppress that expression's value.
    uint raw = x86_compact_executable_raw[hir];
    return valid_node(raw) ? raw : x86_compact_expr_wrapper[hir];
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint resolved_function_token_for_node(uint node)
{
    if (!valid_dense(node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[node];
    if (path_i >= active_path_count())
    {
        uint child = compact_hir_links[node].first_child;
        path_i = valid_dense(child) ? path_id_by_owner_hir[child] : INVALID;
    }
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return INVALID;
    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return INVALID;
    uint fn_token = decl_name_token[decl_i];
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint callee_token_for_call(uint call_hir)
{
    if (!valid_dense(call_hir))
        return INVALID;
    uint callee = compact_hir_payload[call_hir].a;
    if (!valid_dense(callee))
        return INVALID;
    return compact_hir_core[callee].kind == HIR_MEMBER_EXPR
               ? compact_hir_payload[callee].c
               : compact_hir_core[callee].token_start;
}

bool is_method_call(uint call_hir)
{
    uint callee = valid_dense(call_hir) ? compact_hir_payload[call_hir].a : INVALID;
    return valid_dense(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR &&
           valid_dense(compact_hir_payload[callee].b) &&
           valid_token(compact_hir_payload[callee].c);
}

bool method_takes_receiver(uint fn_token)
{
    uint mode = valid_token(fn_token) ? method_decl_receiver_mode[fn_token] : 0u;
    return mode == METHOD_RECEIVER_SELF ||
           mode == METHOD_RECEIVER_REF_SELF ||
           mode == METHOD_RECEIVER_EXPLICIT;
}

uint call_metadata_token(uint callee_token, uint call_slot, uint resolved_fn_token)
{
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;
    if (valid_token(call_slot) && valid_token(call_fn_index[call_slot]))
        return call_slot;
    if (valid_token(resolved_fn_token))
        return resolved_fn_token;
    return callee_token;
}

bool method_call_has_value_receiver(uint call_hir)
{
    uint member = valid_dense(call_hir) ? compact_hir_payload[call_hir].a : INVALID;
    return valid_dense(member) && compact_hir_core[member].kind == HIR_MEMBER_EXPR &&
           valid_dense(compact_hir_payload[member].b);
}

void mark_call_callee_root(uint call_node, uint root)
{
    if (valid_node(call_node) && valid_node(root))
        x86_call_callee_root_call[root] = call_node + 1u;
}

void mark_call_callee_name_wrapper(uint call_node, uint callee_node)
{
    if (!valid_node(callee_node))
        return;
    uint parent = x86_tree_parent[callee_node];
    if (valid_node(parent) && hir_kind[parent] == HIR_NAME_EXPR)
        mark_call_callee_root(call_node, parent);
}

void write_call_type_record(
    uint call_node,
    uint return_ty,
    uint return_ty_token,
    uint callee_token)
{
    row_major_store<uint>(x86_call_type_record, call_node, X86_CALL_TYPE_STRIDE, 0u, return_ty);
    row_major_store<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        1u,
        return_ty_token);
    row_major_store<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        2u,
        callee_token);
}

void clear_call_record(uint call_node)
{
    x86_call_record[call_node] = uint4(INVALID, INVALID, INVALID, INVALID);
    write_call_type_record(call_node, INVALID, INVALID, INVALID);
}

void publish_projected_call(
    uint call_node,
    uint target,
    uint call_slot,
    uint arg_count,
    uint return_ty,
    uint return_ty_token,
    uint abi_name_token)
{
    if (!valid_node(call_node))
        return;
    x86_call_record[call_node] = uint4(
        x86_node_func[call_node],
        target,
        valid_token(call_slot) ? call_slot : INVALID,
        arg_count);
    write_call_type_record(call_node, return_ty, return_ty_token, abi_name_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint call_node = linear_dispatch_id(tid);
    // The x86 instruction planner is still indexed by parser/backend rows.
    // Project the single dense call artifact onto every backend call row that
    // maps to it; semantic discovery remains entirely compact-HIR-owned.
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;
    atomic_u32_min(call_record_status, 2u, call_node);
    increment_stage_count4(call_record_status, 1u);
    uint call_hir = raw_to_compact_hir[call_node];
    if (!valid_dense(call_hir) || compact_hir_core[call_hir].kind != HIR_CALL_EXPR)
    {
        publish_stage_error_min_detail_extra4(
            call_record_status,
            X86_ERR_CALL_RECORDS,
            call_node,
            X86_CALL_RECORD_ERROR_DENSE_MAPPING);
        return;
    }

    uint callee_hir = compact_hir_payload[call_hir].a;
    if (!valid_dense(callee_hir))
    {
        publish_stage_error_min_detail_extra4(
            call_record_status,
            X86_ERR_CALL_RECORDS,
            call_node,
            X86_CALL_RECORD_ERROR_CALLEE);
        return;
    }
    uint callee_node = raw_for_dense(callee_hir);
    uint callee_token = callee_token_for_call(call_hir);
    uint resolved_fn_token = resolved_function_token_for_node(callee_hir);
    uint abi_name_token = valid_token(resolved_fn_token) ? resolved_fn_token : callee_token;
    bool method_call = is_method_call(call_hir);
    uint call_slot = compact_hir_core[call_hir].token_start;
    if (!valid_token(call_slot))
    {
        publish_stage_error_min_detail_extra4(
            call_record_status,
            X86_ERR_CALL_RECORDS,
            call_node,
            X86_CALL_RECORD_ERROR_SLOT);
        return;
    }
    uint metadata_token = call_metadata_token(callee_token, call_slot, resolved_fn_token);
    uint target_fn = valid_token(metadata_token) ? call_fn_index[metadata_token] : INVALID;
    if (!valid_token(target_fn) && valid_token(resolved_fn_token))
        target_fn = resolved_fn_token;
    // Dependency resolution is keyed by the parser-owned callee node's token
    // in the typechecker. Consume that exact semantic key; `callee_token` is
    // an ABI/name projection and can refer to a different wrapper node.
    uint dependency_callee_token = valid_dense(callee_hir)
                                       ? compact_hir_core[callee_hir].token_start
                                       : INVALID;
    uint dependency_decl = valid_token(dependency_callee_token)
                               ? call_dependency_decl[dependency_callee_token]
                               : INVALID;
    bool dependency_call = dependency_decl < gX86Features.dependency_declaration_count;
    uint target_fn_node = valid_token(target_fn) ? x86_decl_node_by_token[target_fn] : INVALID;
    uint target_name_token = valid_node(target_fn_node)
                                 ? hir_item_name_token[target_fn_node]
                                 : INVALID;
    if (valid_token(target_name_token))
        abi_name_token = target_name_token;
    uint return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : 0u;
    uint return_ty_token = valid_token(metadata_token) ? call_return_type_token[metadata_token] : INVALID;
    uint receiver_arg_count =
        method_call && method_takes_receiver(target_fn) && method_call_has_value_receiver(call_hir)
            ? 1u
            : 0u;
    uint explicit_arg_count = compact_hir_payload[call_hir].c;
    uint arg_count = explicit_arg_count + receiver_arg_count;

    uint target = dependency_call
        ? X86_CALL_TARGET_DEPENDENCY_TAG |
              (dependency_decl & X86_CALL_TARGET_DEPENDENCY_PAYLOAD_MASK)
        : target_fn;
    publish_projected_call(
        call_node, target, call_slot, arg_count,
        return_ty, return_ty_token, abi_name_token);
    mark_call_callee_root(call_node, callee_node);
    mark_call_callee_name_wrapper(call_node, callee_node);
}
