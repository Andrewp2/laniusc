import type_checker.constant_parameter_slots;
// GPU hash-indexed method-key validation.
//
// Scheduling contract:
// - Dispatch after compact method rows have been inserted into the structural-head/name
//   candidate index.
// - Alpha-equivalent complete receiver patterns are duplicate inherent methods in the
//   same module for the same receiver type-ref, receiver type arguments, and
//   interned method name. Receivers are compared as canonical IDs: each
//   pattern matches the other (ct_match), which keeps independent and
//   repeated type and constant leaves apart.
// - This pass writes per-method validation results and reduces invalid or
//   duplicate method declarations into the compiler-wide type-check status. It
//   does not resolve calls, inspect source bytes, hash token text, perform CPU
//   lookup, or apply same-source shortcuts.

import hir_records;
import status;
import type_checker.methods.lookup;
import type_checker.instance_arguments;
import type_checker.constant_atoms;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_spare;
import type_checker.match.ct_match;

StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> type_generic_param_slot_by_token;
struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_token;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> method_decl_visibility;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;

RWStructuredBuffer<uint> method_key_status;
RWStructuredBuffer<uint> method_key_duplicate_of;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint METHOD_KEY_STATUS_PRIVATE_OK = 0u;
static const uint METHOD_KEY_STATUS_DUPLICATE = 1u;
static const uint METHOD_KEY_STATUS_INVALID_MODULE = 2u;
static const uint METHOD_KEY_STATUS_INVALID_RECEIVER = 3u;
static const uint METHOD_KEY_STATUS_INVALID_NAME = 4u;
static const uint METHOD_KEY_STATUS_PUBLIC_OK = 5u;
static const uint METHOD_KEY_STATUS_INVALID_RECEIVER_ARG = 6u;
static const uint METHOD_VIS_PUBLIC = 1u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_DUPLICATE_METHOD = 0xffffff07u;

#include "receiver_graph.slang"

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return max(1u, min(module_count_out[0], gParams.method_capacity));
}

[ForceInline]
uint active_token_count()
{
    return min(token_count[0], gParams.method_capacity);
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.method_capacity);
}

bool is_method_decl(uint fn_i)
{
    return fn_i < active_token_count() && method_decl_method_row[fn_i] != INVALID;
}

bool receiver_head(uint fn_i, out MethodReceiverHead head)
{
    return method_receiver_head<MethodReceiverGraph>(
        method_decl_receiver_ref_tag[fn_i], method_decl_receiver_ref_payload[fn_i],
        method_receiver_type_capacity(), active_token_count(), head);
}

// Binding slots of the receivers' own impl parameters.
struct ReceiverSlots : ICtSlots
{
    uint type_slot(uint token)
    { return token < active_token_count() ? type_generic_param_slot_by_token[token] : CT_SLOT_NONE; }
    uint const_slot(uint token)
    { return token < active_token_count() ? type_const_param_slot_by_token[token] : CT_SLOT_NONE; }
    uint const_scalar(uint token) { return checked_constant_parameter_scalar(token); }
}

// The canonical ID of a method's declared receiver pattern (interned with
// the declared rows, before method validation).
uint receiver_id(uint fn_i)
{
    return ct_ref(method_decl_receiver_ref_tag[fn_i], method_decl_receiver_ref_payload[fn_i]);
}

bool receiver_graph_valid(uint fn_i)
{
    MethodReceiverHead head;
    return receiver_head(fn_i, head) && ct_is_resolved(receiver_id(fn_i));
}

uint invalid_method_status(uint fn_i)
{
    if (!is_method_decl(fn_i))
        return METHOD_KEY_STATUS_INVALID_NAME;

    uint module_id = method_decl_module_id[fn_i];
    if (module_id == INVALID || module_id >= active_module_count())
        return METHOD_KEY_STATUS_INVALID_MODULE;
    if (method_decl_receiver_ref_tag[fn_i] == TYPE_REF_INVALID ||
        method_decl_receiver_ref_payload[fn_i] == INVALID)
        return METHOD_KEY_STATUS_INVALID_RECEIVER;
    if (!receiver_graph_valid(fn_i))
        return METHOD_KEY_STATUS_INVALID_RECEIVER_ARG;
    if (method_decl_name_id[fn_i] == INVALID)
        return METHOD_KEY_STATUS_INVALID_NAME;

    return METHOD_KEY_STATUS_PRIVATE_OK;
}

// Alpha-equivalent receivers match each other in both directions. Token
// identities may differ between the two impl declarations.
bool receiver_arg_rows_equal(uint left_fn_i, uint right_fn_i)
{
    uint left = receiver_id(left_fn_i);
    uint right = receiver_id(right_fn_i);
    ReceiverSlots slots;
    CtSpare spare = ct_spare_none();
    for (uint direction = 0u; direction < 2u; direction++)
    {
        uint count_mask;
        if (ct_match<ReceiverSlots>(slots, direction == 0u ? left : right, direction == 0u ? right : left,
            CT_NONE, CT_NONE, CT_NONE, 0u, false, spare, count_mask) != CT_MATCH_OK) return false;
    }
    return true;
}

bool method_keys_equal(uint left_fn_i, uint right_fn_i)
{
    // Each root receives one full validation in its owning invocation. Do
    // not inline another full graph hash per bucket candidate; the complete
    // bidirectional constraints below reject incompatible/malformed graphs.
    // Read immutable inputs here, never another invocation's output status.
    if (!is_method_decl(left_fn_i) || !is_method_decl(right_fn_i)) return false;
    MethodReceiverHead left_head; MethodReceiverHead right_head;
    return method_decl_module_id[left_fn_i] == method_decl_module_id[right_fn_i] &&
        method_decl_name_id[left_fn_i] == method_decl_name_id[right_fn_i] &&
        receiver_head(left_fn_i, left_head) && receiver_head(right_fn_i, right_head) &&
        method_receiver_heads_equal(left_head, right_head) &&
        receiver_arg_rows_equal(left_fn_i, right_fn_i);
}

uint method_lookup_bucket_for_fn(uint fn_i, uint method_count)
{
    MethodReceiverHead head;
    // Called only after receiver_graph_valid has admitted the entire root.
    if (!receiver_head(fn_i, head)) return INVALID;
    return method_lookup_bucket(head, method_decl_name_id[fn_i], method_count);
}

uint previous_duplicate(uint fn_i, uint method_count)
{
    uint bucket = method_lookup_bucket_for_fn(fn_i, method_count);
    if (bucket == INVALID) return INVALID;
    uint encoded_row = method_lookup_head[bucket];
    uint duplicate = INVALID;
    for (uint visited = 0u; encoded_row != 0u && visited < method_count; visited += 1u)
    {
        uint row = encoded_row - 1u;
        if (row >= method_count)
            break;
        encoded_row = method_lookup_next[row];
        uint candidate = compact_method_cores[row].name_token;
        if (candidate < fn_i && method_keys_equal(candidate, fn_i))
            duplicate = duplicate == INVALID ? candidate : max(duplicate, candidate);
    }
    return duplicate;
}

uint error_token_for_method(uint fn_i)
{
    if (fn_i < active_token_count())
    {
        uint name_token = method_decl_name_token[fn_i];
        if (name_token != INVALID)
            return name_token;
        if (fn_i != INVALID)
            return fn_i;
    }
    return 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint method_count = active_method_count();
    if (i >= method_count)
        return;

    uint fn_i = compact_method_cores[i].name_token;
    if (fn_i >= active_token_count())
        return;

    method_key_duplicate_of[fn_i] = INVALID;
    if (!is_method_decl(fn_i))
    {
        method_key_status[fn_i] = METHOD_KEY_STATUS_PRIVATE_OK;
        return;
    }

    uint status = invalid_method_status(fn_i);
    if (status != METHOD_KEY_STATUS_PRIVATE_OK)
    {
        method_key_status[fn_i] = status;
        // Receiver type-argument shape and arity belong to the impl-header
        // validator, which can produce a source-level diagnostic. Keep this
        // method out of the lookup without replacing that diagnostic with an
        // internal method-key error.
        if (status != METHOD_KEY_STATUS_INVALID_RECEIVER_ARG)
            record_error(error_token_for_method(fn_i), ERR_BAD_HIR, status);
        return;
    }

    method_key_status[fn_i] =
        method_decl_visibility[fn_i] == METHOD_VIS_PUBLIC ? METHOD_KEY_STATUS_PUBLIC_OK
                                                          : METHOD_KEY_STATUS_PRIVATE_OK;
    uint prev_fn_i = previous_duplicate(fn_i, method_count);
    if (prev_fn_i == INVALID)
        return;
    method_key_status[fn_i] = METHOD_KEY_STATUS_DUPLICATE;
    method_key_duplicate_of[fn_i] = prev_fn_i;
    record_error(error_token_for_method(fn_i), ERR_CALL_MISMATCH, CALL_MISMATCH_DUPLICATE_METHOD);
}
