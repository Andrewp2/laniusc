// Final method-call result publication and argument validation.
//
// This pass consumes the sorted-table method resolution written at the method
// name token plus parser-owned member/call-argument and expression-result
// records. It does not rediscover calls by scanning token neighborhoods,
// matching parentheses/commas in token ranges, or walking child lists.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_callee_path_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_signature_flags;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_value_path_call_path_id;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> module_value_path_associated_receiver_token;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF = 0xffffff01u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC = 0xffffff02u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE = 0xffffff03u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 4u;
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

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
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

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        return visible_type[payload];
    return TY_UNKNOWN;
}

uint receiver_arg_ref_index(uint method_i, uint slot)
{
    if (method_i >= active_token_count())
        return INVALID;

    uint receiver_tag = method_call_receiver_ref_tag[method_i];
    uint receiver_payload = method_call_receiver_ref_payload[method_i];
    if (receiver_tag != TYPE_REF_INSTANCE || !valid_token(receiver_payload))
        return INVALID;

    uint arg_count = type_instance_arg_count[receiver_payload];
    uint arg_start = type_instance_arg_start[receiver_payload];
    if (slot >= arg_count || arg_start == INVALID)
        return INVALID;

    uint arg_i = arg_start + slot;
    return arg_i < active_token_count() ? arg_i : INVALID;
}

uint receiver_arg_row_ref_index(uint instance_i, uint ordinal)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint row_ref_i = receiver_arg_row_ref_index(instance_i, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= PARAM_CACHE_STRIDE)
        return false;

    uint start = type_instance_arg_start[instance_i];
    uint arg_i = start == INVALID ? INVALID : start + ordinal;
    if (arg_i == INVALID || arg_i >= active_token_count())
        return false;

    tag = type_instance_arg_ref_tag[arg_i];
    payload = type_instance_arg_ref_payload[arg_i];
    return tag != TYPE_REF_INVALID;
}

bool receiver_arg_ref_for_method(uint method_i, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (method_i >= active_token_count())
        return false;

    uint receiver_tag = method_call_receiver_ref_tag[method_i];
    uint receiver_payload = method_call_receiver_ref_payload[method_i];
    if (receiver_tag != TYPE_REF_INSTANCE || !valid_token(receiver_payload))
        return false;
    return instance_arg_ref(receiver_payload, slot, tag, payload);
}

uint generic_param_slot_for_payload(uint payload)
{
    return valid_token(payload) ? type_generic_param_slot_by_token[payload] : payload;
}

uint generic_param_name_for_payload(uint payload)
{
    return valid_token(payload) ? name_id_by_token[payload] : INVALID;
}

bool same_generic_param_payload(uint left_payload, uint right_payload)
{
    uint left_slot = generic_param_slot_for_payload(left_payload);
    uint right_slot = generic_param_slot_for_payload(right_payload);
    if (left_slot != INVALID && right_slot != INVALID)
        return left_slot == right_slot;

    uint left_name = generic_param_name_for_payload(left_payload);
    uint right_name = generic_param_name_for_payload(right_payload);
    return left_name != INVALID && left_name == right_name;
}

uint receiver_decl_generic_slot(uint fn_i, uint generic_token)
{
    if (fn_i >= active_token_count() || !valid_token(generic_token))
        return INVALID;

    uint receiver_tag = method_decl_receiver_ref_tag[fn_i];
    uint receiver_payload = method_decl_receiver_ref_payload[fn_i];
    if (receiver_tag != TYPE_REF_INSTANCE || !valid_token(receiver_payload))
        return INVALID;

    uint arg_count = type_instance_arg_count[receiver_payload];
    for (uint slot = 0u; slot < arg_count; slot += 1u)
    {
        uint tag;
        uint payload;
        if (instance_arg_ref(receiver_payload, slot, tag, payload) &&
            tag == TYPE_REF_GENERIC_PARAM &&
            same_generic_param_payload(payload, generic_token))
            return slot;
    }

    return INVALID;
}

uint substituted_method_return_type(uint method_i, uint fn_i, uint fallback_ty)
{
    if (fn_i >= active_token_count())
        return fallback_ty;

    uint ret_tag = fn_return_ref_tag[fn_i];
    uint ret_payload = fn_return_ref_payload[fn_i];
    if (ret_tag != TYPE_REF_GENERIC_PARAM || !valid_token(ret_payload))
        return fallback_ty;

    uint slot = receiver_decl_generic_slot(fn_i, ret_payload);
    uint arg_tag;
    uint arg_payload;
    if (!receiver_arg_ref_for_method(method_i, slot, arg_tag, arg_payload))
        return fallback_ty;

    uint ty = type_code_for_ref(arg_tag, arg_payload);
    return ty == TY_UNKNOWN ? fallback_ty : ty;
}

uint resolved_method_return_type(uint method_i, uint fn_i)
{
    uint table_ty = valid_token(method_i) ? call_return_type[method_i] : TY_UNKNOWN;
    if (table_ty != TY_UNKNOWN)
        return table_ty;
    return substituted_method_return_type(method_i, fn_i, call_return_type[fn_i]);
}

uint resolved_method_return_token(uint method_i, uint fn_i)
{
    uint table_token = valid_token(method_i) ? call_return_type_token[method_i] : INVALID;
    return valid_token(table_token) ? table_token : call_return_type_token[fn_i];
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;
    uint call_node = hir_call_parent_by_callee[callee_node];
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;
    uint path_node = hir_call_callee_path_node[call_node];
    uint path_owner = valid_node(path_node) ? raw_to_compact_hir[path_node] : INVALID;
    uint path_i = path_owner < gParams.n_hir_nodes
        ? path_id_by_owner_hir[path_owner]
        : INVALID;
    return valid_path(path_i) ? path_i : INVALID;
}

uint path_leaf_token(uint path_i)
{
    uint count = valid_path(path_i) ? path_segment_count[path_i] : 0u;
    if (count == 0u)
        return INVALID;
    uint slot = path_segment_base[path_i] + count - 1u;
    return slot < active_token_count() ? path_segment_token[slot] : INVALID;
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

uint associated_method_token_for_path(uint path_i)
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

uint path_id_for_associated_call(uint call_node, uint callee_node)
{
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return INVALID;

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

uint associated_owner_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint path_i = path_id_for_associated_call(call_node, callee_node);
    if (valid_path(path_i))
        return path_owner_token[path_i];
    uint call_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    uint method_token = valid_token(call_token)
        ? module_value_path_associated_method_token[call_token]
        : INVALID;
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    if (!valid_token(method_token) && valid_token(callee_token))
        method_token = module_value_path_associated_method_token[callee_token];
    uint receiver_token = valid_token(method_token)
        ? module_value_path_associated_receiver_token[method_token]
        : INVALID;
    if (valid_token(receiver_token))
        return receiver_token;
    return valid_token(call_token) ? call_token : INVALID;
}

uint associated_method_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    uint call_token = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    uint path_i = path_id_for_associated_call(call_node, callee_node);
    uint method_token = valid_path(path_i) ? associated_method_token_for_path(path_i) : INVALID;
    if (valid_path(path_i) && valid_token(method_token) && method_token != path_owner_token[path_i])
        return method_token;
    method_token = valid_token(call_token) ? module_value_path_associated_method_token[call_token] : INVALID;
    if (valid_token(method_token) && method_token != call_token)
        return method_token;
    method_token = valid_token(callee_token) ? module_value_path_associated_method_token[callee_token] : INVALID;
    if (valid_token(method_token))
        return method_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool method_has_self_receiver(uint fn_i)
{
    uint mode = fn_i < active_token_count() ? method_decl_receiver_mode[fn_i] : METHOD_RECEIVER_NONE;
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

bool method_explicit_receiver_consumes_param(uint fn_i, uint receiver_ty)
{
    uint mode = fn_i < active_token_count() ? method_decl_receiver_mode[fn_i] : METHOD_RECEIVER_NONE;
    if (mode != METHOD_RECEIVER_EXPLICIT)
        return false;
    if (call_param_count[fn_i] == 0u)
        return false;
    uint first_ty = param_type_for_fn_ordinal(fn_i, 0u);
    return first_ty == receiver_ty;
}

bool param_row_matches(uint row, uint fn_i, uint ordinal)
{
    return row < call_param_row_count_out[0u] &&
           call_param_row_fn_token[row] == fn_i &&
           call_param_row_ordinal[row] == ordinal;
}

uint param_row_for_fn_ordinal(uint fn_i, uint ordinal)
{
    if (!valid_token(fn_i) || ordinal >= call_param_count[fn_i])
        return INVALID;

    uint start = call_param_row_start[fn_i];
    uint count = call_param_row_count[fn_i];
    if (start == INVALID || count == 0u || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    if (row < start || row >= call_param_row_count_out[0u])
        return INVALID;

    return param_row_matches(row, fn_i, ordinal) ? row : INVALID;
}

uint param_type_for_fn_ordinal(uint fn_i, uint ordinal)
{
    uint row = param_row_for_fn_ordinal(fn_i, ordinal);
    return row == INVALID ? TY_UNKNOWN : call_param_row_type[row];
}

uint call_node_for_method_token(uint method_i)
{
    if (method_i >= active_token_count())
        return INVALID;
    return call_arg_record[method_i].z;
}

uint call_node_for_member_node(uint member_node)
{
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return INVALID;

    uint call_node = hir_call_parent_by_callee[member_node];
    return valid_node(call_node) && hir_kind[call_node] == HIR_CALL_EXPR
        ? call_node
        : INVALID;
}

uint call_node_for_method_member(uint method_i, uint member_node)
{
    uint call_node = call_node_for_method_token(method_i);
    return valid_node(call_node) ? call_node : call_node_for_member_node(member_node);
}

uint call_arg_count_for_method_token(uint method_i)
{
    if (method_i >= active_token_count())
        return 0u;
    uint call_node = call_arg_record[method_i].z;
    uint record_count = call_arg_record[method_i].w;
    return valid_node(call_node) ? max(record_count, call_arg_row_count[call_node]) : record_count;
}

uint call_arg_count_for_call_node(uint method_i, uint call_node)
{
    uint record_count = valid_token(method_i) ? call_arg_record[method_i].w : 0u;
    if (!valid_node(call_node))
        return record_count;
    return max(max(record_count, hir_call_arg_count[call_node]), call_arg_row_count[call_node]);
}

uint receiver_token_for_member(uint member_node)
{
    return valid_node(member_node) ? hir_member_receiver_token[member_node] : INVALID;
}

bool validate_method_args(uint method_i, uint fn_i, uint receiver_ty, uint call_node)
{
    uint param_count = call_param_count[fn_i];
    bool has_self_receiver = method_has_self_receiver(fn_i);
    bool consumes_receiver = method_explicit_receiver_consumes_param(fn_i, receiver_ty);
    if (!has_self_receiver && !consumes_receiver)
    {
        record_error(method_i, ERR_CALL_MISMATCH, receiver_ty);
        return false;
    }

    bool receiver_consumed = has_self_receiver || consumes_receiver;
    uint expected_args = receiver_consumed && param_count > 0u ? param_count - 1u : param_count;
    uint actual_args = call_arg_count_for_call_node(method_i, call_node);
    if (actual_args != expected_args)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
        return false;
    }
    // Per-argument assignability is checked by the compact call-argument row pass after method resolution.
    return true;
}

bool validate_associated_args(uint method_i, uint fn_i, uint call_node)
{
    uint receiver_mode = method_decl_receiver_mode[fn_i];
    if (receiver_mode == METHOD_RECEIVER_SELF || receiver_mode == METHOD_RECEIVER_REF_SELF)
    {
        record_error(method_i, ERR_CALL_MISMATCH, receiver_mode);
        return false;
    }

    uint expected_args = call_param_count[fn_i];
    uint actual_args = call_arg_count_for_call_node(method_i, call_node);
    if (actual_args != expected_args)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
        return false;
    }
    // Per-argument assignability is checked by the compact call-argument row pass after method resolution.
    return true;
}

void resolve_method_member_node(uint member_node)
{
    uint method_i = valid_node(member_node) ? hir_member_name_token[member_node] : INVALID;
    if (method_i >= active_token_count())
        return;

    uint call_node = call_node_for_method_member(method_i, member_node);
    if (!valid_node(call_node))
        return;

    if (method_call_name_id[method_i] == INVALID)
        return;

    uint fn_i = call_fn_index[method_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
    {
        record_error(method_i, ERR_CALL_MISMATCH, method_call_name_id[method_i]);
        return;
    }

    uint receiver_i = receiver_token_for_member(member_node);
    if (receiver_i == INVALID || receiver_i >= active_token_count())
        return;
    uint receiver_ty = visible_type[receiver_i];
    if (receiver_ty == TY_UNKNOWN)
        receiver_ty = call_return_type[receiver_i];

    uint signature_flags = valid_token(fn_i) ? method_decl_signature_flags[fn_i] : 0u;
    if ((signature_flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC);
        return;
    }
    if ((signature_flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE);
        return;
    }

    uint ret_ty = resolved_method_return_type(method_i, fn_i);
    uint ret_token = resolved_method_return_token(method_i, fn_i);
    if ((ret_ty == TY_UNKNOWN && fn_return_ref_tag[fn_i] != TYPE_REF_INVALID) ||
        is_generic_type(ret_ty))
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF);
        return;
    }
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = ret_token;
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;

    validate_method_args(method_i, fn_i, receiver_ty, call_node);
}

void publish_associated_call_result(
    uint method_i,
    uint owner_token,
    uint call_open,
    uint fn_i,
    uint ret_ty,
    uint ret_token)
{
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = ret_token;
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;
    module_value_path_status[method_i] = PATH_RESOLVE_STATUS_INVALID;

    if (valid_token(owner_token))
    {
        call_fn_index[owner_token] = fn_i;
        call_return_type[owner_token] = ret_ty;
        call_return_type_token[owner_token] = ret_token;
        if (ret_ty != TY_UNKNOWN)
            visible_type[owner_token] = ret_ty;
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_INVALID;
    }

    if (valid_token(call_open))
    {
        call_fn_index[call_open] = fn_i;
        call_return_type[call_open] = ret_ty;
        call_return_type_token[call_open] = ret_token;
        if (ret_ty != TY_UNKNOWN)
            visible_type[call_open] = ret_ty;
    }
}

void resolve_associated_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint method_i = associated_method_token_for_call(call_node);
    if (!valid_token(method_i))
        return;
    if (method_call_name_id[method_i] == INVALID)
        return;

    uint fn_i = call_fn_index[method_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
    {
        record_error(method_i, ERR_CALL_MISMATCH, method_call_name_id[method_i]);
        return;
    }

    uint signature_flags = valid_token(fn_i) ? method_decl_signature_flags[fn_i] : 0u;
    if ((signature_flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC);
        return;
    }
    if ((signature_flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE);
        return;
    }

    uint ret_ty = resolved_method_return_type(method_i, fn_i);
    uint ret_token = resolved_method_return_token(method_i, fn_i);
    if ((ret_ty == TY_UNKNOWN && fn_return_ref_tag[fn_i] != TYPE_REF_INVALID) ||
        is_generic_type(ret_ty))
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF);
        return;
    }

    if (!validate_associated_args(method_i, fn_i, call_node))
        return;

    uint owner_token = associated_owner_token_for_call(call_node);
    uint call_open = hir_token_pos[call_node];
    publish_associated_call_result(method_i, owner_token, call_open, fn_i, ret_ty, ret_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    if (hir_kind[i] == HIR_MEMBER_EXPR)
    {
        resolve_method_member_node(i);
        return;
    }

    if (hir_kind[i] == HIR_CALL_EXPR)
        resolve_associated_call_node(i);
}
