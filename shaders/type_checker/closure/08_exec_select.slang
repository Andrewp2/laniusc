// Execution-row selection (instance_exec.slang): one lane per table entry.
// An entry is lowered in this job only when every rule below holds; any
// other entry stays a replay body, as before. The rules:
//
// - the table is complete (no IT_COUNT_FLAGS) and the body is this job's;
// - the template is a function declared at file level or a method of an
//   impl (inherent or trait), with no constant parameters and no trait or
//   function owner: the entry's environment binds the impl's parameters and
//   the function's own, so the copy has no environment left to bind. A
//   receiver parameter's type is realized at the function row
//   (table_rows.slang);
// - the template is not instantiated in place (inplace_read.slang): its
//   own rows already are that instance;
// - the body declares no nested item or function;
// - every row's type realized under the environment (instance_row_refs);
// - every call is routed: a call of a local generic body, or a
//   bound-member call whose receiver selects a generic method, names its
//   callee's table entry (IT_CALL_ENTRY), and a method call's receiver
//   dereferences under the environment as the template's did; any other
//   call keeps the template's callee (IT_CALL_NONE) and needs no type
//   argument from the environment, as a variant constructor does; a call
//   routed to a nongeneric method, a dependency-generic call or an
//   unresolved call replays;
// - an index, iteration or array row whose type the environment changes
//   replays, and so does a function whose result becomes an array: its
//   length, stride or result width is derived by passes that run before the
//   table; a member row's receiver must be a row of the subtree, and when
//   the environment changes it, 08a_exec_members derives the field layout
//   or rejects the entry;
// - each side-table block of the subtree is contiguous (checked here).
//
// Lanes write the entry's head, token span and template blocks; the layout
// lane assigns the virtual bases.
import hir_records;
import checked_semantic_artifact;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;
import type_checker.closure.instance_exec;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<HirString> compact_strings;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
#include "inplace_read.slang"

static const uint INVALID = 0xffffffffu;
// TYPE_REF_INSTANCE and an array instance (type_instance_kind).
static const uint TYPE_REF_ARRAY_INSTANCE = 3u;
static const uint TYPE_INSTANCE_KIND_ARRAY = 2u;
static const uint HIR_FILE = 1u;
static const uint HIR_ITEM = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_IMPL = 35u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_STMT = 7u;
static const uint HIR_STMT_FOR = 7u;

uint hir_count()
{
    uint rows; uint stride;
    compact_hir_core.GetDimensions(rows, stride);
    return min(compact_hir_count[0u], rows);
}

// A function declared at file level, or a method of an impl declared at
// file level, outside any trait, function or other generic owner. The copy
// is private to this job whatever the template's visibility.
bool exec_owner_function(uint row)
{
    if (compact_hir_core[row].kind != HIR_FN) return false;
    bool free_function = compact_hir_payload[row].a == HIR_ITEM_KIND_FN;
    uint count = hir_count();
    uint node = compact_hir_core[row].parent;
    bool impl_seen = false;
    for (uint depth = 0u; depth < count && node < count; depth++)
    {
        uint kind = compact_hir_core[node].kind;
        if (kind == HIR_FILE) return free_function || impl_seen;
        if (kind == HIR_IMPL) { impl_seen = true; }
        else if (kind == HIR_FN || compact_generic_param_ranges[node].count != 0u ||
            (kind == HIR_ITEM && compact_hir_payload[node].a == HIR_ITEM_KIND_TRAIT)) return false;
        uint parent = compact_hir_core[node].parent;
        if (parent >= node) break;
        node = parent;
    }
    return false;
}

bool nested_declaration(uint kind)
{
    return kind == HIR_ITEM || kind == HIR_FN || kind == HIR_CONST_ITEM || kind == HIR_ENUM_ITEM ||
        kind == HIR_STRUCT_ITEM || kind == HIR_TYPE_ALIAS_ITEM || kind == HIR_MODULE_ITEM ||
        kind == HIR_IMPORT_ITEM || kind == HIR_IMPL;
}

// The key of row `index` of side table k: the HIR row the table is sorted by.
uint table_key(uint k, uint index)
{
    if (k == EX_TABLE_CALL_ARGS) return compact_call_args[index].call;
    if (k == EX_TABLE_FIELDS) return compact_fields[index].owner;
    if (k == EX_TABLE_MATCH_ARMS) return compact_match_arms[index].owner;
    if (k == EX_TABLE_MATCH_PAYLOADS) return compact_match_payloads[index].pattern;
    if (k == EX_TABLE_ARRAY_ELEMENTS) return compact_array_elements[index].array;
    if (k == EX_TABLE_STRINGS) return compact_strings[index].node;
    return compact_params[index].owner;
}

uint table_rows(uint k)
{
    uint rows; uint stride;
    if (k == EX_TABLE_CALL_ARGS) { compact_call_args.GetDimensions(rows, stride); return min(compact_call_arg_count[0u], rows); }
    if (k == EX_TABLE_FIELDS) { compact_fields.GetDimensions(rows, stride); return min(compact_field_count[0u], rows); }
    if (k == EX_TABLE_MATCH_ARMS) { compact_match_arms.GetDimensions(rows, stride); return min(compact_match_arm_count[0u], rows); }
    if (k == EX_TABLE_MATCH_PAYLOADS) { compact_match_payloads.GetDimensions(rows, stride); return min(compact_match_payload_row_count[0u], rows); }
    if (k == EX_TABLE_ARRAY_ELEMENTS) { compact_array_elements.GetDimensions(rows, stride); return min(compact_array_element_row_count[0u], rows); }
    if (k == EX_TABLE_STRINGS) { compact_strings.GetDimensions(rows, stride); return min(compact_string_count[0u], rows); }
    compact_params.GetDimensions(rows, stride);
    return min(compact_param_count[0u], rows);
}

// The first index of side table k whose key is at least `row`. Tables
// are in key order (each family is scattered in HIR row order); the
// caller checks the block it bounds.
uint lower_bound(uint k, uint rows, uint row)
{
    uint lo = 0u;
    uint hi = rows;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (table_key(k, mid) < row) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

// Whether the template call at `row` keeps its callee in every instance:
// no environment-dependent argument reaches the callee and no receiver
// is adjusted under a type parameter.
bool call_keeps_callee(uint row)
{
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    if (call.symbolic_type_environment != 0u && call.callable_kind != 4u) return false;
    if (call.receiver_adjustment_kind != 0u || call.receiver_deref_count != 0u) return false;
    return call.receiver_parameter_ref_tag != 2u && call.receiver_matched_ref_tag != 2u;
}

// The receiver type a method call matched: `receiver` after `count`
// dereferences through reference instances; (EX_INVALID, 0) when one is not
// a reference.
uint2 ex_dereferenced(uint2 receiver, uint count)
{
    uint rows; uint stride;
    type_instance_kind.GetDimensions(rows, stride);
    for (uint step = 0u; step < count; step++)
    {
        if (receiver.x != 3u || receiver.y >= rows || type_instance_kind[receiver.y] != 4u)
            return uint2(EX_INVALID, 0u);
        receiver = uint2(type_instance_elem_ref_tag[receiver.y], type_instance_elem_ref_payload[receiver.y]);
    }
    return receiver;
}

// Whether a method call at template row `row` of entry `key`, routed to
// table entry `callee`, has a realized receiver (09_exec_rows): the callee's
// receiver parameter realized, and a receiver that dereferences as the
// template's did.
bool entry_receiver_realizes(uint row, uint4 key, uint callee)
{
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    if (call.receiver_adjustment_kind == 0u) return true;
    uint2 parameter = instance_row_refs[instance_table[2u * callee].w];
    if (parameter.x == 0u || parameter.x == IT_ROW_FAILED) return false;
    uint receiver = call.receiver_hir;
    if (receiver < key.x || receiver - key.x >= key.y) return false;
    uint2 realized = instance_row_refs[key.w + (receiver - key.x)];
    return ex_dereferenced(uint2(realized.x - 1u, realized.y), call.receiver_deref_count).x != EX_INVALID;
}

uint reject(uint entry, uint reason)
{
    ex_set_quad(entry, EX_Q_HEAD, uint4(reason, 0u, 0u, 0u));
    return reason;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint entry = dtid.x + dtid.y * 16776960u;
    uint entries = min(instance_table_counts[IT_COUNT_ENTRIES], IT_RANK_LIMIT);
    if (entry >= entries || entry >= ex_entry_capacity()) return;
    uint4 key = instance_table[2u * entry];
    uint4 origin = instance_table[2u * entry + 1u];
    uint function = key.x;
    uint count = key.y;
    uint count_rows = hir_count();
    if (instance_table_counts[IT_COUNT_FLAGS] != 0u || origin.z != IT_SOURCE_LOCAL ||
        function >= count_rows || count == 0u || count > count_rows - function)
    {
        reject(entry, EX_REJECT_TABLE);
        return;
    }
    if (!exec_owner_function(function) || inplace_instance(function) != INPLACE_NONE)
    {
        reject(entry, EX_REJECT_OWNER);
        return;
    }
    uint4 extra = instance_closure_instances[2u * origin.x + 1u];
    if ((extra.w >> 16u) != (extra.w & 0xffffu))
    {
        reject(entry, EX_REJECT_CONSTANTS);
        return;
    }
    uint return_row = compact_fn_return_type[function];
    if (return_row != INVALID && return_row >= function && return_row - function < count)
    {
        uint2 result = instance_row_refs[key.w + (return_row - function)];
        bool changed = result.x - 1u != semantic_expr_ref_tag_by_hir[return_row] ||
            result.y != semantic_expr_ref_payload_by_hir[return_row];
        uint rows; uint stride;
        type_instance_kind.GetDimensions(rows, stride);
        if (changed && result.x - 1u == TYPE_REF_ARRAY_INSTANCE && result.y < rows &&
            type_instance_kind[result.y] == TYPE_INSTANCE_KIND_ARRAY)
        {
            reject(entry, EX_REJECT_FACT);
            return;
        }
    }
    uint last_token = compact_hir_core[function].token_start;
    for (uint offset = 0u; offset < count; offset++)
    {
        uint row = function + offset;
        HirCore core = compact_hir_core[row];
        if (offset != 0u && nested_declaration(core.kind))
        {
            reject(entry, EX_REJECT_SYNTAX);
            return;
        }
        if (core.token_end != INVALID) last_token = max(last_token, core.token_end);
        uint2 realized = instance_row_refs[key.w + offset];
        if (realized.x == 0u || realized.x == IT_ROW_FAILED)
        {
            reject(entry, EX_REJECT_ROW);
            return;
        }
        uint2 call = instance_row_calls[key.w + offset];
        if (call.x != IT_CALL_NONE && call.x != IT_CALL_ENTRY)
        {
            reject(entry, EX_REJECT_CALL);
            return;
        }
        if (core.kind == HIR_CALL_EXPR && call.x == IT_CALL_ENTRY && !entry_receiver_realizes(row, key, call.y))
        {
            reject(entry, EX_REJECT_CALL);
            return;
        }
        if (core.kind == HIR_CALL_EXPR && call.x == IT_CALL_NONE && !call_keeps_callee(row))
        {
            reject(entry, EX_REJECT_CALL);
            return;
        }
        bool changed = realized.x - 1u != semantic_expr_ref_tag_by_hir[row] ||
            realized.y != semantic_expr_ref_payload_by_hir[row];
        bool for_stmt = core.kind == HIR_FOR_STMT ||
            (core.kind == HIR_STMT && compact_hir_payload[row].a == HIR_STMT_FOR);
        if (changed && (core.kind == HIR_INDEX_EXPR || core.kind == HIR_ARRAY_EXPR || for_stmt))
        {
            reject(entry, EX_REJECT_FACT);
            return;
        }
        if (core.kind == HIR_MEMBER_EXPR)
        {
            uint receiver = compact_hir_payload[row].b;
            if (receiver < function || receiver - function >= count)
            {
                reject(entry, EX_REJECT_FACT);
                return;
            }
        }
    }
    uint4 tstart0 = uint4(0u, 0u, 0u, 0u);
    uint4 tstart1 = uint4(0u, 0u, 0u, 0u);
    uint4 tlen0 = uint4(0u, 0u, 0u, 0u);
    uint4 tlen1 = uint4(0u, 0u, 0u, 0u);
    for (uint k = 0u; k < EX_TABLES; k++)
    {
        uint rows = table_rows(k);
        uint start = lower_bound(k, rows, function);
        uint end = lower_bound(k, rows, function + count);
        // A block is every row keyed inside the subtree; the bounds above
        // assume key order, so check it within and at the edges.
        for (uint index = start; index < end; index++)
        {
            uint owner = table_key(k, index);
            if (owner < function || owner - function >= count ||
                (index > start && table_key(k, index - 1u) > owner))
            {
                reject(entry, EX_REJECT_BLOCK);
                return;
            }
        }
        if ((start > 0u && table_key(k, start - 1u) >= function) ||
            (end < rows && table_key(k, end) < function + count))
        {
            reject(entry, EX_REJECT_BLOCK);
            return;
        }
        ex_set_table_word(tstart0, tstart1, k, start);
        ex_set_table_word(tlen0, tlen1, k, end - start);
    }
    uint first_token = compact_hir_core[function].token_start;
    ex_set_quad(entry, EX_Q_HEAD, uint4(EX_PENDING, function, count, INVALID));
    ex_set_quad(entry, EX_Q_TOKENS, uint4(first_token, last_token - first_token + 1u, INVALID, key.w));
    ex_set_quad(entry, EX_Q_TSTART0, tstart0);
    ex_set_quad(entry, EX_Q_TSTART1, tstart1);
    ex_set_quad(entry, EX_Q_TLEN0, tlen0);
    ex_set_quad(entry, EX_Q_TLEN1, tlen1);
}
