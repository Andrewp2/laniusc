import hir_records;

// GPU method-call key marking for call-result receivers.
//
// Scheduling contract:
// - Dispatch after function and module-qualified call resolution have populated
//   call_fn_index and after type-instance collection has populated
//   fn_return_ref_*.
// - For each HIR call whose callee is a HIR member expression and whose
//   receiver is itself a resolved call expression, publish the method lookup
//   key from the resolved callee's declared return type ref.
// - This pass complements type_check_methods_06_mark_call_keys.slang without
//   exceeding the adapter storage-buffer binding limit. It does not inspect
//   source bytes, hash token text, perform CPU lookup, or compare names by
//   spelling.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> module_id_by_file_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_value_path_call_open;
StructuredBuffer<uint> module_value_path_call_path_id;
StructuredBuffer<uint> module_value_path_associated_method_token;

RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_name_id;
RWStructuredBuffer<uint> method_call_site_module_id;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
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

uint active_compact_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint source_file_count()
{
    return max(gParams.n_source_files, 1u);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_dense(uint i)
{
    return i != INVALID && i < active_compact_hir_count();
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_path(uint i)
{
    return i != INVALID && i < active_path_count();
}

uint receiver_token_for_member_hir(uint member_hir)
{
    if (!valid_dense(member_hir) || compact_hir_core[member_hir].kind != HIR_MEMBER_EXPR)
        return INVALID;
    HirPayload member = compact_hir_payload[member_hir];
    uint receiver_token = member.d;
    if (valid_token(receiver_token))
        return receiver_token;

    uint receiver_hir = member.b;
    uint token = valid_dense(receiver_hir) ? compact_hir_core[receiver_hir].token_start : INVALID;
    return valid_token(token) ? token : INVALID;
}

uint module_for_compact_hir(uint hir)
{
    uint token_i = valid_dense(hir) ? compact_hir_core[hir].token_start : INVALID;
    uint file_id = token_i < active_token_count() ? token_file_id[token_i] : INVALID;
    uint module_id = file_id < source_file_count() ? module_id_by_file_id[file_id] : INVALID;
    if (module_id != INVALID)
        return module_id;
    return file_id == 0u || file_id == INVALID ? 0u : INVALID;
}

bool receiver_call_return_type_ref(uint receiver_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    if (receiver_i >= active_token_count())
        return false;

    uint fn_i = call_fn_index[receiver_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
        return false;

    uint ret_ty = call_return_type[receiver_i];
    if (ret_ty == TY_UNKNOWN)
        ret_ty = call_return_type[fn_i];
    if (ret_ty != TY_UNKNOWN && ret_ty != TY_VOID)
    {
        tag = TYPE_REF_SCALAR;
        payload = ret_ty;
        return true;
    }

    uint return_token = call_return_type_token[receiver_i];
    if (!valid_token(return_token))
        return_token = call_return_type_token[fn_i];
    if (valid_token(return_token))
    {
        tag = decl_type_ref_tag[return_token];
        payload = decl_type_ref_payload[return_token];
        if (tag != TYPE_REF_INVALID && payload != INVALID)
            return true;
    }

    tag = fn_return_ref_tag[fn_i];
    payload = fn_return_ref_payload[fn_i];
    if (tag != TYPE_REF_INVALID && payload != INVALID)
        return true;

    tag = TYPE_REF_INVALID;
    payload = INVALID;
    return false;
}

uint path_id_for_callee_hir(uint callee_hir)
{
    if (!valid_dense(callee_hir))
        return INVALID;
    uint path_i = path_id_by_owner_hir[callee_hir];
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

uint associated_method_token_for_call(uint call_hir)
{
    if (!valid_dense(call_hir) || compact_hir_core[call_hir].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee_hir = compact_hir_payload[call_hir].a;
    uint path_i = path_id_for_callee_hir(callee_hir);
    if (valid_path(path_i))
    {
        uint owner_token = path_owner_token[path_i];
        uint method_token = valid_token(owner_token)
            ? module_value_path_associated_method_token[owner_token]
            : INVALID;
        if (valid_token(method_token))
            return method_token;
        uint receiver_token = path_leaf_token(path_i);
        method_token = valid_token(receiver_token)
            ? module_value_path_associated_method_token[receiver_token]
            : INVALID;
        return valid_token(method_token) ? method_token : receiver_token;
    }

    uint call_token = compact_hir_core[call_hir].token_start;
    uint method_token = valid_token(call_token)
        ? module_value_path_associated_method_token[call_token]
        : INVALID;
    if (valid_token(method_token))
        return method_token;
    uint callee_token = valid_dense(callee_hir) ? compact_hir_core[callee_hir].token_start : INVALID;
    return valid_token(callee_token) ? module_value_path_associated_method_token[callee_token] : INVALID;
}

uint callee_token_for_call(uint call_hir)
{
    if (!valid_dense(call_hir) || compact_hir_core[call_hir].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_hir = compact_hir_payload[call_hir].a;
    if (!valid_dense(callee_hir))
        return INVALID;

    if (compact_hir_core[callee_hir].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_hir].c;
        return member_token < active_token_count() ? member_token : INVALID;
    }

    uint associated_method = associated_method_token_for_call(call_hir);
    if (valid_token(associated_method))
        return associated_method;

    uint token = compact_hir_core[callee_hir].token_start;
    return token < active_token_count() ? token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (!valid_dense(i) || compact_hir_core[i].kind != HIR_CALL_EXPR)
        return;

    uint member_hir = compact_hir_payload[i].a;
    if (!valid_dense(member_hir) || compact_hir_core[member_hir].kind != HIR_MEMBER_EXPR)
        return;

    HirPayload member = compact_hir_payload[member_hir];
    uint method_i = member.c;
    if (method_i >= active_token_count())
        return;

    method_call_name_id[method_i] = name_id_by_token[method_i];
    method_call_site_module_id[method_i] = module_for_compact_hir(member_hir);

    if (method_call_receiver_ref_tag[method_i] != TYPE_REF_INVALID)
        return;

    uint receiver_i = receiver_token_for_member_hir(member_hir);
    if (!valid_token(receiver_i))
        return;

    uint receiver_hir = member.b;
    if (valid_dense(receiver_hir) && compact_hir_core[receiver_hir].kind == HIR_CALL_EXPR)
    {
        uint receiver_callee = callee_token_for_call(receiver_hir);
        if (receiver_callee < active_token_count())
            receiver_i = receiver_callee;
    }

    uint tag;
    uint payload;
    if (!receiver_call_return_type_ref(receiver_i, tag, payload))
        return;

    method_call_receiver_ref_tag[method_i] = tag;
    method_call_receiver_ref_payload[method_i] = payload;
}
