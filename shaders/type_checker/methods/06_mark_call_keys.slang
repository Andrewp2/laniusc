// GPU method-call key marking from parser/HIR call, member, and path records.
//
// Scheduling contract:
// - Dispatch after visible declarations, type refs, name ids, and module-file
//   maps are available.
// - For each HIR call whose callee is a HIR member expression or a
//   type-qualified path expression, this pass publishes a lookup key from
//   parser-owned metadata:
//   (receiver type-ref tag/payload, interned method name id, call-site module
//   id). The resolver derives the receiver owner module from GPU type/module
//   maps and uses the call-site module id for private method visibility.
// - Receiver type refs are read from declaration-token keyed type-reference
//   records, or from member-result type refs for chained field receivers whose
//   receiver is not itself a declaration. A follow-up pass handles receiver
//   expressions that are already resolved calls. Associated call receivers are
//   represented as token-keyed type instances so the existing generic method
//   table can resolve Vec<T>::new-style calls. Associated calls may also be
//   discovered from token-owned receiver syntax when parser wrapper call rows
//   are outside the semantic HIR dispatch range. This pass does not inspect
//   source bytes, hash token text, perform CPU lookup, or compare names by
//   spelling.

import fixed.key;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_type_arg_start;
StructuredBuffer<uint> hir_type_arg_count;
StructuredBuffer<uint> hir_type_arg_next;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> import_visible_type_count_out;
StructuredBuffer<uint> import_visible_type_key_module_id;
StructuredBuffer<uint> import_visible_type_key_name_id;
StructuredBuffer<uint> import_visible_type_key_to_decl_id;
StructuredBuffer<uint> import_visible_type_status;
StructuredBuffer<uint> module_value_path_call_open;
StructuredBuffer<uint> module_value_path_call_path_id;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> module_value_path_associated_receiver_token;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count;

RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_name_id;
RWStructuredBuffer<uint> method_call_site_module_id;
RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint LANGUAGE_SYMBOL_COUNT = 19u;
static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 9u;

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

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint active_decl_type_count()
{
    return min(decl_type_key_count_out[0], gParams.n_hir_nodes);
}

uint active_import_visible_type_count()
{
    return min(import_visible_type_count_out[0], gParams.n_hir_nodes);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_path(uint i)
{
    return i != INVALID && i < active_path_count();
}

bool receiver_decl_type_ref(uint receiver_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint decl_i = receiver_i < active_token_count() ? visible_decl[receiver_i] : INVALID;
    if (decl_i != INVALID && decl_i < active_token_count())
    {
        tag = decl_type_ref_tag[decl_i];
        payload = decl_type_ref_payload[decl_i];
    }
    else if (receiver_i < active_token_count())
    {
        tag = member_result_ref_tag[receiver_i];
        payload = member_result_ref_payload[receiver_i];
    }
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

uint semantic_receiver_token(uint receiver_node, uint fallback_token)
{
    if (valid_node(receiver_node) && hir_kind[receiver_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[receiver_node];
        if (valid_token(member_token))
            return member_token;
    }
    return fallback_token;
}

uint module_for_hir_node(uint node)
{
    uint token_i = node < active_hir_node_count() ? hir_token_pos[node] : INVALID;
    uint file_id = token_i < active_token_count() ? token_file_id[token_i] : INVALID;
    uint module_id = file_id < source_file_count() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

uint module_for_path(uint path_i)
{
    if (valid_path(path_i))
    {
        uint module_id = path_owner_module_id[path_i];
        if (module_id != INVALID)
            return module_id;
    }
    return INVALID;
}

uint module_for_decl_token(uint decl_i)
{
    uint file_id = decl_i < active_token_count() ? token_file_id[decl_i] : INVALID;
    uint module_id = file_id < source_file_count() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
}

uint module_for_token(uint token_i)
{
    uint file_id = token_i < active_token_count() ? token_file_id[token_i] : INVALID;
    uint module_id = file_id < source_file_count() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u ? 0u : INVALID;
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
        uint decl_i = decl_type_key_to_decl_id[row];
        uint value = INVALID;
        if (decl_i < gParams.n_hir_nodes)
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

uint find_local_type_decl(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    DeclLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<DeclLookupKey, DeclKeyCompare>(active_decl_type_count(), key);
    return row == INVALID ? INVALID : decl_type_key_to_decl_id[row];
}

public struct ImportVisibleLookupKey
{
    uint module_id;
    uint name_id;
}

public struct ImportVisibleFixedKey : IFixedU32RowKey<ImportVisibleLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_type_key_module_id[row]
            : import_visible_type_key_name_id[row];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(ImportVisibleLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct ImportVisibleCompare : IRowQueryCompare<ImportVisibleLookupKey>
{
    public static int compare(uint row, ImportVisibleLookupKey key)
    {
        return fixed_u32_row_key_compare<ImportVisibleLookupKey, ImportVisibleFixedKey>(
            row,
            key,
            2u);
    }
}

uint find_imported_type_decl(uint module_id, uint name_id)
{
    if (module_id == INVALID || name_id == INVALID)
        return INVALID;

    ImportVisibleLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row =
        find_equal_query<ImportVisibleLookupKey, ImportVisibleCompare>(
            active_import_visible_type_count(),
            key);
    if (row == INVALID || import_visible_type_status[row] != IMPORT_VISIBLE_STATUS_OK)
        return INVALID;
    return import_visible_type_key_to_decl_id[row];
}

uint segment_name_id(uint path_i, uint segment_i)
{
    if (!valid_path(path_i) || segment_i >= min(path_segment_count[path_i], MAX_PATH_SEGMENTS))
        return INVALID;
    uint slot = path_segment_base[path_i] + segment_i;
    return slot < active_token_count() * MAX_PATH_SEGMENTS ? path_segment_name_id[slot] : INVALID;
}

uint segment_token(uint path_i, uint segment_i)
{
    if (!valid_path(path_i) || segment_i >= min(path_segment_count[path_i], MAX_PATH_SEGMENTS))
        return INVALID;
    uint slot = path_segment_base[path_i] + segment_i;
    return slot < active_token_count() * MAX_PATH_SEGMENTS ? path_segment_token[slot] : INVALID;
}

uint path_leaf_token(uint path_i)
{
    uint count = valid_path(path_i) ? min(path_segment_count[path_i], MAX_PATH_SEGMENTS) : 0u;
    return count == 0u ? INVALID : segment_token(path_i, count - 1u);
}

uint path_id_for_owner_token(uint owner_token)
{
    if (!valid_token(owner_token))
        return INVALID;
    uint path_i = path_id_by_owner_token[owner_token];
    return valid_path(path_i) ? path_i : INVALID;
}

uint path_id_for_call_open(uint call_open)
{
    if (!valid_token(call_open))
        return INVALID;
    uint path_i = module_value_path_call_path_id[call_open];
    return valid_path(path_i) ? path_i : INVALID;
}

uint associated_method_token(uint path_i)
{
    if (!valid_path(path_i))
        return INVALID;
    uint owner_token = path_owner_token[path_i];
    uint method_token = valid_token(owner_token)
        ? module_value_path_associated_method_token[owner_token]
        : INVALID;
    if (valid_token(method_token))
        return method_token;
    uint leaf = path_leaf_token(path_i);
    method_token = valid_token(leaf) ? module_value_path_associated_method_token[leaf] : INVALID;
    return valid_token(method_token) ? method_token : leaf;
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;

    if (hir_kind[callee_node] == HIR_PATH_EXPR || hir_kind[callee_node] == HIR_TYPE)
    {
        uint path_i = path_id_by_owner_hir[callee_node];
        return valid_path(path_i) ? path_i : INVALID;
    }

    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && (hir_kind[child] == HIR_PATH_EXPR || hir_kind[child] == HIR_TYPE))
        {
            uint path_i = path_id_by_owner_hir[child];
            return valid_path(path_i) ? path_i : INVALID;
        }
    }

    return INVALID;
}

uint path_id_for_associated_call(uint call_node, uint callee_node)
{
    uint path_i = path_id_for_callee_node(callee_node);
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    uint call_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;

    if (!valid_path(path_i))
        path_i = path_id_for_call_open(call_token);
    if (!valid_path(path_i))
        path_i = path_id_for_call_open(callee_token);
    if (!valid_path(path_i))
        path_i = path_id_for_owner_token(call_token);
    if (!valid_path(path_i))
        path_i = path_id_for_owner_token(callee_token);
    return valid_path(path_i) ? path_i : INVALID;
}

uint local_or_imported_type_decl_for_segment(uint path_i, uint segment_i)
{
    uint module_id = module_for_path(path_i);
    uint name_id = segment_name_id(path_i, segment_i);
    uint decl_i = find_local_type_decl(module_id, name_id);
    if (decl_i != INVALID)
        return decl_i;
    return find_imported_type_decl(module_id, name_id);
}

uint local_or_imported_type_decl_for_token(uint owner_node, uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;

    uint module_id = module_for_hir_node(owner_node);
    uint name_id = name_id_by_token[token_i];
    uint decl_i = find_local_type_decl(module_id, name_id);
    if (decl_i != INVALID)
        return decl_i;
    return find_imported_type_decl(module_id, name_id);
}

uint local_or_imported_type_decl_for_source_token(uint token_i)
{
    if (!valid_token(token_i))
        return INVALID;

    uint module_id = module_for_token(token_i);
    uint name_id = name_id_by_token[token_i];
    uint decl_i = find_local_type_decl(module_id, name_id);
    if (decl_i != INVALID)
        return decl_i;
    return find_imported_type_decl(module_id, name_id);
}

uint associated_receiver_segment_count(uint path_i, uint method_i)
{
    uint count = valid_path(path_i) ? min(path_segment_count[path_i], MAX_PATH_SEGMENTS) : 0u;
    if (count == 0u)
        return 0u;

    uint leaf = path_leaf_token(path_i);
    if (method_i == leaf && count > 1u)
        return count - 1u;
    return count;
}

uint associated_receiver_decl(uint path_i, uint receiver_segment_count)
{
    if (!valid_path(path_i) || receiver_segment_count == 0u)
        return INVALID;

    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (receiver_segment_count == count)
    {
        uint decl_i = resolved_type_decl[path_i];
        if (decl_i != INVALID && decl_i < gParams.n_hir_nodes)
            return decl_i;
    }

    if (receiver_segment_count == 1u)
        return local_or_imported_type_decl_for_segment(path_i, 0u);

    return INVALID;
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

void clear_instance_arg_refs(uint instance_i)
{
    type_instance_arg_start[instance_i] = INVALID;
    type_instance_arg_count[instance_i] = 0u;

    uint out_0 = arg_ref_index(instance_i, 0u);
    uint out_1 = arg_ref_index(instance_i, 1u);
    uint out_2 = arg_ref_index(instance_i, 2u);
    uint out_3 = arg_ref_index(instance_i, 3u);
    type_instance_arg_ref_tag[out_0] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_0] = INVALID;
    type_instance_arg_ref_tag[out_1] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_1] = INVALID;
    type_instance_arg_ref_tag[out_2] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_2] = INVALID;
    type_instance_arg_ref_tag[out_3] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[out_3] = INVALID;
}

uint language_type_code_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint name_id = name_id_by_token[token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return TY_UNKNOWN;

    return language_type_code_by_name_id[name_id];
}

uint resolved_path_decl_for_owner_token(uint owner_token)
{
    uint path_i = path_id_for_owner_token(owner_token);
    if (!valid_path(path_i))
        path_i = path_id_for_call_open(owner_token);
    return valid_path(path_i) ? resolved_type_decl[path_i] : INVALID;
}

uint receiver_decl_for_source_token(uint receiver_token)
{
    uint decl_i = resolved_path_decl_for_owner_token(receiver_token);
    if (decl_i != INVALID && decl_i < gParams.n_hir_nodes)
        return decl_i;
    return local_or_imported_type_decl_for_source_token(receiver_token);
}

uint fallback_type_code_for_arg_token(uint arg_token)
{
    if (!valid_token(arg_token))
        return TY_UNKNOWN;

    uint ty = module_type_path_type[arg_token];
    if (ty != TY_UNKNOWN)
        return ty;

    ty = language_type_code_for_token(arg_token);
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl_i = resolved_path_decl_for_owner_token(arg_token);
    uint decl_token = decl_i < gParams.n_hir_nodes ? decl_name_token[decl_i] : INVALID;
    return nominal_type_code(decl_i, decl_token);
}

bool publish_type_arg_ref(uint instance_i, uint slot, uint arg_token)
{
    if (slot >= TYPE_INSTANCE_ARG_REF_STRIDE || !valid_token(arg_token))
        return false;

    uint out_i = arg_ref_index(instance_i, slot);
    uint tag = type_expr_ref_tag[arg_token];
    uint payload = type_expr_ref_payload[arg_token];
    if (tag == TYPE_REF_INVALID)
    {
        uint ty = fallback_type_code_for_arg_token(arg_token);
        if (ty != TY_UNKNOWN)
        {
            type_instance_arg_ref_tag[out_i] = TYPE_REF_SCALAR;
            type_instance_arg_ref_payload[out_i] = ty;
            return true;
        }

        type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
        type_instance_arg_ref_payload[out_i] = instance_i;
        return false;
    }

    type_instance_arg_ref_tag[out_i] = tag;
    type_instance_arg_ref_payload[out_i] = payload;
    return true;
}

uint type_node_for_instance_token(uint instance_i)
{
    uint path_i = path_id_for_owner_token(instance_i);
    if (!valid_path(path_i))
        path_i = path_id_for_call_open(instance_i);
    if (!valid_path(path_i))
        return INVALID;
    uint node = path_owner_hir[path_i];
    return valid_node(node) && hir_kind[node] == HIR_TYPE ? node : INVALID;
}

bool publish_type_arg_node_ref(uint instance_i, uint slot, uint node, out uint next_node)
{
    next_node = INVALID;
    if (!valid_node(node))
        return false;
    bool ok = publish_type_arg_ref(instance_i, slot, hir_token_pos[node]);
    next_node = hir_type_arg_next[node];
    return ok;
}

bool compact_type_arg_rows_valid(uint instance_i, uint arg_count)
{
    if (arg_count == 0u)
        return true;

    uint row_start = type_instance_arg_row_start[instance_i];
    if (row_start == INVALID)
        return false;

    uint total_rows = type_instance_arg_row_count_out[0u];
    [loop]
    for (uint ordinal = 0u; ordinal < arg_count; ordinal += 1u)
    {
        uint row_i = row_start + ordinal;
        if (row_i >= total_rows ||
            type_instance_arg_row_ref_tag[row_i] == TYPE_REF_INVALID ||
            type_instance_arg_row_ref_payload[row_i] == INVALID)
            return false;
    }
    return true;
}

uint publish_path_type_args(uint instance_i)
{
    clear_instance_arg_refs(instance_i);
    if (!valid_token(instance_i))
        return 0u;

    uint type_node = type_node_for_instance_token(instance_i);
    uint method_i = module_value_path_associated_method_token[instance_i];
    if (!valid_node(type_node) && valid_token(method_i))
    {
        type_instance_state[instance_i] = TYPE_INSTANCE_UNSUPPORTED;
        return INVALID;
    }

    uint arg_count = valid_node(type_node) ? hir_type_arg_count[type_node] : 0u;

    bool unsupported = false;
    uint slot = 0u;
    uint node = valid_node(type_node) ? hir_type_arg_start[type_node] : INVALID;
    uint next_node = INVALID;
    if (arg_count > 0u)
    {
        unsupported = unsupported || !publish_type_arg_node_ref(instance_i, 0u, node, next_node);
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 1u)
    {
        unsupported = unsupported || !publish_type_arg_node_ref(instance_i, 1u, node, next_node);
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 2u)
    {
        unsupported = unsupported || !publish_type_arg_node_ref(instance_i, 2u, node, next_node);
        slot += 1u;
        node = next_node;
    }
    if (arg_count > 3u)
    {
        unsupported = unsupported || !publish_type_arg_node_ref(instance_i, 3u, node, next_node);
        slot += 1u;
        node = next_node;
    }

    bool short_list_mismatch = arg_count <= TYPE_INSTANCE_ARG_REF_STRIDE &&
                               (slot != arg_count || valid_node(node));
    if (unsupported || short_list_mismatch || !compact_type_arg_rows_valid(instance_i, arg_count))
    {
        type_instance_state[instance_i] = TYPE_INSTANCE_UNSUPPORTED;
        return INVALID;
    }

    type_instance_arg_count[instance_i] = arg_count;
    type_instance_arg_start[instance_i] = arg_count == 0u ? INVALID : arg_ref_index(instance_i, 0u);
    return arg_count;
}

uint nominal_type_code(uint decl_i, uint decl_token)
{
    uint ty = valid_token(decl_token) ? module_type_path_type[decl_token] : TY_UNKNOWN;
    if (ty != TY_UNKNOWN)
        return ty;

    if (decl_i >= gParams.n_hir_nodes || !valid_token(decl_token))
        return TY_UNKNOWN;

    uint kind = decl_kind[decl_i];
    if (kind == HIR_ITEM_KIND_STRUCT)
        return TY_STRUCT_BASE + decl_token;
    if (kind == HIR_ITEM_KIND_ENUM)
        return TY_ENUM_BASE + decl_token;
    return TY_UNKNOWN;
}

bool associated_receiver_ref(
    uint receiver_token,
    uint decl_i,
    uint decl_token,
    out uint receiver_tag,
    out uint receiver_payload)
{
    receiver_tag = TYPE_REF_INVALID;
    receiver_payload = INVALID;
    if (!valid_token(receiver_token) || !valid_token(decl_token))
        return false;

    uint expected_count = type_decl_generic_param_count[decl_token];
    if (expected_count == 0u)
    {
        uint ty = nominal_type_code(decl_i, decl_token);
        if (ty == TY_UNKNOWN)
            return false;
        receiver_tag = TYPE_REF_SCALAR;
        receiver_payload = ty;
        return true;
    }

    uint arg_count = publish_path_type_args(receiver_token);
    if (arg_count != expected_count)
    {
        type_instance_state[receiver_token] = TYPE_INSTANCE_UNSUPPORTED;
        return false;
    }

    type_instance_kind[receiver_token] = TYPE_INSTANCE_NAMED;
    type_instance_decl_token[receiver_token] = decl_token;
    type_instance_state[receiver_token] = TYPE_INSTANCE_RESOLVED;
    receiver_tag = TYPE_REF_INSTANCE;
    receiver_payload = receiver_token;
    return true;
}

void publish_associated_method_call(uint call_node, uint callee_node)
{
    uint path_i = path_id_for_associated_call(call_node, callee_node);
    bool has_path = valid_path(path_i) &&
                    (path_kind[path_i] == PATH_RECORD_KIND_HIR_PATH_EXPR ||
                     path_kind[path_i] == PATH_RECORD_KIND_HIR_TYPE_EXPR);
    uint call_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    if (!has_path && !valid_token(call_token))
        return;

    uint owner_token = has_path ? path_owner_token[path_i] : call_token;
    if (!valid_token(owner_token))
        return;

    uint method_i = has_path
        ? associated_method_token(path_i)
        : module_value_path_associated_method_token[owner_token];
    uint receiver_segment_count = has_path ? associated_receiver_segment_count(path_i, method_i) : 1u;
    uint receiver_token = has_path
        ? (receiver_segment_count == 0u
               ? INVALID
               : segment_token(path_i, receiver_segment_count - 1u))
        : (valid_token(method_i) ? module_value_path_associated_receiver_token[method_i] : owner_token);
    if (!valid_token(method_i) || method_i == owner_token)
        return;

    uint receiver_decl = has_path
        ? associated_receiver_decl(path_i, receiver_segment_count)
        : local_or_imported_type_decl_for_token(call_node, receiver_token);
    uint receiver_decl_token =
        receiver_decl < gParams.n_hir_nodes ? decl_name_token[receiver_decl] : INVALID;
    uint receiver_tag;
    uint receiver_payload;
    if (!associated_receiver_ref(
            receiver_token,
            receiver_decl,
            receiver_decl_token,
            receiver_tag,
            receiver_payload))
        return;

    method_call_name_id[method_i] = name_id_by_token[method_i];
    method_call_site_module_id[method_i] = has_path ? module_for_path(path_i) : INVALID;
    if (method_call_site_module_id[method_i] == INVALID)
        method_call_site_module_id[method_i] = module_for_hir_node(
            valid_node(callee_node) ? callee_node : call_node);
    method_call_receiver_ref_tag[method_i] = receiver_tag;
    method_call_receiver_ref_payload[method_i] = receiver_payload;
    module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_INVALID;
}

void publish_associated_method_call_for_method_token(uint method_i)
{
    if (!valid_token(method_i))
        return;

    uint receiver_token = module_value_path_associated_receiver_token[method_i];
    if (!valid_token(receiver_token) || method_i == receiver_token)
        return;

    uint receiver_decl = receiver_decl_for_source_token(receiver_token);
    uint receiver_decl_token =
        receiver_decl < gParams.n_hir_nodes ? decl_name_token[receiver_decl] : INVALID;
    uint receiver_tag;
    uint receiver_payload;
    if (!associated_receiver_ref(
            receiver_token,
            receiver_decl,
            receiver_decl_token,
            receiver_tag,
            receiver_payload))
        return;

    method_call_name_id[method_i] = name_id_by_token[method_i];
    method_call_site_module_id[method_i] = module_for_token(method_i);
    method_call_receiver_ref_tag[method_i] = receiver_tag;
    method_call_receiver_ref_payload[method_i] = receiver_payload;
    module_value_path_status[receiver_token] = PATH_RESOLVE_STATUS_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (i < active_token_count())
        publish_associated_method_call_for_method_token(i);

    if (i >= active_hir_node_count() || hir_kind[i] != HIR_CALL_EXPR)
        return;

    uint callee_node = hir_call_callee_node[i];
    if (!valid_node(callee_node) || hir_kind[callee_node] != HIR_MEMBER_EXPR)
    {
        publish_associated_method_call(i, callee_node);
        return;
    }

    uint method_i = hir_member_name_token[callee_node];
    if (method_i >= active_token_count())
        return;

    uint receiver_i = hir_member_receiver_token[callee_node];
    if (receiver_i == INVALID || receiver_i >= active_token_count())
        return;
    uint raw_receiver_i = receiver_i;
    receiver_i = semantic_receiver_token(hir_member_receiver_node[callee_node], receiver_i);

    method_call_name_id[method_i] = name_id_by_token[method_i];
    uint decl_i = visible_decl[raw_receiver_i];
    uint call_site_module = module_for_decl_token(decl_i);
    method_call_site_module_id[method_i] =
        call_site_module == INVALID ? module_for_hir_node(callee_node) : call_site_module;

    uint tag;
    uint payload;
    if (!receiver_decl_type_ref(receiver_i, tag, payload))
        return;

    method_call_receiver_ref_tag[method_i] = tag;
    method_call_receiver_ref_payload[method_i] = payload;
}
