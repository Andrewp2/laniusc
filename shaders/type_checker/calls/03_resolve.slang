// Resolve direct function calls and publish callee return metadata.
//
// This pass consumes compact HIR call/callee records plus module
// declaration visibility records. It does not inspect token kinds, token
// neighborhoods, source bytes, helper names, or function bodies.

import fixed.key;
import hir_records;
import range_query;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_value_key_count_out;
StructuredBuffer<uint> decl_value_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> import_visible_value_count_out;
StructuredBuffer<uint> import_visible_value_key_module_id;
StructuredBuffer<uint> import_visible_value_key_name_id;
StructuredBuffer<uint> import_visible_value_key_to_decl_id;
StructuredBuffer<uint> import_visible_value_status;
StructuredBuffer<uint> method_call_name_id;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint TY_UNKNOWN = 0u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;

static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint active_decl_count()
{
    return min(decl_value_key_count_out[0], gParams.n_tokens);
}

uint active_import_visible_count()
{
    return min(import_visible_value_count_out[0], gParams.n_tokens);
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = compact_hir_payload[call_node].a;
    return valid_node(callee_node) && compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_arg_count_for_callee(uint callee_i)
{
    if (!valid_token(callee_i))
        return 0u;
    uint4 record = call_arg_record[callee_i];
    uint call_node = record.z;
    if (!valid_node(call_node))
        return record.w;
    return max(record.w, compact_hir_payload[call_node].c);
}

uint path_node_for_callee(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    if (compact_hir_core[callee_node].kind == HIR_PATH_EXPR)
        return callee_node;
    if (compact_hir_core[callee_node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint child = compact_hir_links[callee_node].first_child;
    return valid_node(child) && compact_hir_core[child].kind == HIR_PATH_EXPR ? child : INVALID;
}

uint path_id_for_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[callee_node];
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
    {
        uint path_node = path_node_for_callee(callee_node);
        path_i = valid_node(path_node) ? path_id_by_owner_hir[path_node] : INVALID;
    }
    return path_i < gParams.n_hir_nodes ? path_i : INVALID;
}

bool path_is_qualified(uint path_i)
{
    return path_i != INVALID && path_i < gParams.n_hir_nodes && path_segment_count[path_i] > 1u;
}

uint resolved_function_for_call_path(uint call_node)
{
    uint path_i = path_id_for_call(call_node);
    if (path_i == INVALID)
        return INVALID;
    if (path_owner_module_id[path_i] == INVALID)
        return INVALID;

    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return INVALID;
    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_tokens)
        return INVALID;
    uint fn_i = decl_name_token[decl_i];
    return valid_token(fn_i) && call_fn_index[fn_i] == fn_i ? fn_i : INVALID;
}

public struct DeclLookupKey
{
    uint module_id;
    uint name_id;
}

public struct DeclFixedKey : IFixedU32RowKey<DeclLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint decl_i = decl_value_key_to_decl_id[row];
        uint value = INVALID;
        if (decl_i < gParams.n_tokens)
            value = lane == 0u ? decl_module_id[decl_i] : decl_name_id[decl_i];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(DeclLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct DeclKeyCompare : IRowQueryCompare<DeclLookupKey>
{
    public static int compare(uint row, DeclLookupKey key)
    {
        return fixed_u32_row_key_compare<DeclLookupKey, DeclFixedKey>(
            row,
            key,
            2u);
    }
}

public struct VisibleLookupKey
{
    uint module_id;
    uint name_id;
}

public struct VisibleFixedKey : IFixedU32RowKey<VisibleLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_value_key_module_id[row]
            : import_visible_value_key_name_id[row];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(VisibleLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct VisibleKeyCompare : IRowQueryCompare<VisibleLookupKey>
{
    public static int compare(uint row, VisibleLookupKey key)
    {
        return fixed_u32_row_key_compare<VisibleLookupKey, VisibleFixedKey>(
            row,
            key,
            2u);
    }
}

uint find_local_decl(uint module_id, uint name_id)
{
    DeclLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<DeclLookupKey, DeclKeyCompare>(active_decl_count(), key);
    return row == INVALID ? INVALID : decl_value_key_to_decl_id[row];
}

uint find_import_visible_decl(uint module_id, uint name_id)
{
    VisibleLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<VisibleLookupKey, VisibleKeyCompare>(
        active_import_visible_count(),
        key);
    if (row == INVALID || import_visible_value_status[row] != IMPORT_VISIBLE_STATUS_OK)
        return INVALID;
    return import_visible_value_key_to_decl_id[row];
}

uint module_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;
    uint file_id = token_file_id[token_i];
    uint module_id =
        file_id < gParams.n_source_files ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u && gParams.n_source_files <= 1u ? 0u : INVALID;
}

uint function_token_for_decl(uint decl_i)
{
    if (decl_i >= gParams.n_tokens)
        return INVALID;
    uint fn_i = decl_name_token[decl_i];
    return valid_token(fn_i) && call_fn_index[fn_i] == fn_i ? fn_i : INVALID;
}

uint visible_function_for_callee(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;

    uint name_id = name_id_by_token[callee_i];
    uint module_id = module_for_token(callee_i);
    if (name_id == INVALID || module_id == INVALID)
        return INVALID;

    uint fn_i = function_token_for_decl(find_local_decl(module_id, name_id));
    if (valid_token(fn_i))
        return fn_i;

    return function_token_for_decl(find_import_visible_decl(module_id, name_id));
}

bool check_call_arity(uint callee_i, uint fn_i)
{
    uint param_count = valid_token(fn_i) ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (param_count == arg_count)
        return true;

    call_return_type[callee_i] = TY_UNKNOWN;
    record_error(callee_i, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
    return false;
}

void resolve_callee_token(uint callee_i, uint call_node)
{
    if (!valid_token(callee_i))
        return;

    if (valid_token(call_fn_index[callee_i]))
        return;

    if (method_call_name_id[callee_i] != INVALID)
        return;

    if (call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint path_i = path_id_for_call(call_node);
    uint fn_i = INVALID;
    if (path_i != INVALID && path_owner_module_id[path_i] != INVALID)
    {
        fn_i = resolved_function_for_call_path(call_node);
        if (!valid_token(fn_i))
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }
    }
    else
    {
        fn_i = visible_function_for_callee(callee_i);
        if (!valid_token(fn_i))
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }
    }

    call_fn_index[callee_i] = fn_i;
    uint ret_ty = call_return_type[fn_i];
    if (!check_call_arity(callee_i, fn_i))
        return;
    call_return_type[callee_i] = ret_ty;
    call_return_type_token[callee_i] = call_return_type_token[fn_i];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (!valid_node(i) || compact_hir_core[i].kind != HIR_CALL_EXPR)
        return;
    if (call_record_is_member_call(i))
        return;

    uint callee_token = callee_token_for_hir_call(i);
    if (valid_token(callee_token) && method_call_name_id[callee_token] != INVALID)
        return;
    resolve_callee_token(callee_token, i);
}
