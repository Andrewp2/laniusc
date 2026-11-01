import primitive_types;
import type_checker.concrete_type_equality;
import type_checker.constant_atoms_identity;
// Project checked array/slice references into dense semantic HIR.
//
// The earlier index-result pass establishes that the index expression has a
// valid array/slice declaration and publishes its scalar cache. This final
// projection is entirely dense-HIR keyed: no raw parser row survives into the
// checked semantic artifact boundary.

import hir_records;
import status;
import type_checker.checked_array_counts;
import type_checker.checked_index_reference;
import type_checker.checked_canonical;
import type_checker.checked_type_graph;
import type_checker.native_nominal_identity;
import gpu_index;
import checked_semantic_artifact;
import type_checker.argument_context;
import type_checker.array_extent_literal;
import hir_expr_semantics;

bool valid_instance(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> type_native_word_count;
StructuredBuffer<uint> type_native_scalar_identity;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_decl_token_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_word_count_by_hir;
RWStructuredBuffer<uint> semantic_array_length_by_hir;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> semantic_function_result_word_count_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_STMT_FOR = 7u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint NATIVE_RUNTIME_LENGTH = 0xfffffffeu;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint ITERABLE_EXCLUSIVE_RANGE = 1u;
static const uint ITERABLE_INCLUSIVE_RANGE = 2u;
static const uint ITERABLE_FIXED_ARRAY = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint name_token(uint node)
{
    if (!valid_hir(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         compact_hir_core[node].kind != HIR_PATH_EXPR))
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : INVALID;
}

uint forwarded_expression(uint node)
{
    for (uint depth = 0u; depth < 64u && valid_hir(node); depth++)
    {
        uint kind = compact_hir_core[node].kind;
        HirPayload value = compact_hir_payload[node];
        if ((kind != 14u && kind != 16u && kind != 17u) || value.a != 1u) return node;
        node = value.b;
    }
    return INVALID;
}

void publish_ref(uint node, uint tag, uint payload)
{
    if (!valid_hir(node)) return;
    semantic_expr_ref_tag_by_hir[node] = tag;
    semantic_expr_ref_payload_by_hir[node] = payload;
}

bool native_array_count(uint instance, out uint count)
{
    count = 0u;
    return valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY &&
        checked_source_array_count(type_instance_len_kind[instance],
            type_instance_len_payload[instance], gParams.n_tokens, count) &&
        count < NATIVE_RUNTIME_LENGTH;
}

// Publishes the length of array or slice `instance` at `node`; true with the
// fixed count when it is a native fixed-size array.
bool publish_array_length(uint node, uint instance, out uint count)
{
    count = 0u;
    if (!valid_hir(node) || !valid_instance(instance)) return false;
    uint kind = type_instance_kind[instance];
    if (kind == TYPE_INSTANCE_SLICE)
    {
        semantic_array_length_by_hir[node] = NATIVE_RUNTIME_LENGTH;
        return false;
    }
    if (kind != TYPE_INSTANCE_ARRAY) return false;
    semantic_array_length_by_hir[node] = INVALID;
    if (native_array_count(instance, count))
    {
        semantic_array_length_by_hir[node] = count;
        return true;
    }
    // Original generic bodies may retain a conditional array-count contract.
    // Only a genuinely symbolic integer remains deferred; malformed atoms,
    // failed concrete fits and fixed counts colliding with native markers fail.
    ConstantReferenceDescriptor descriptor;
    bool symbolic = inspect_constant_reference<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(
        uint3(type_instance_len_kind[instance], type_instance_len_payload[instance], 0u),
        gParams.n_tokens, descriptor) &&
        descriptor.disposition == CONSTANT_REFERENCE_SYMBOLIC &&
        scalar_is_integer(descriptor.terminal_scalar);
    // An out-of-range literal extent reports its own range error, not an
    // unsupported array (array_extent_literal.slang).
    uint range_literal = symbolic ? INVALID
        : array_extent_range_literal(node, active_hir_count(), compact_hir_core, compact_hir_payload);
    if (valid_token(range_literal))
        record_min_token_error(status, range_literal, 24u, SCALAR_U32);
    else if (!symbolic)
    {
        // A language error already at this array type (a length of the wrong
        // type, type_instances/01d) explains the missing layout.
        uint token = compact_hir_core[node].token_start;
        bool diagnosed = status[STATUS_OK_SLOT] == 0u && status[STATUS_TOKEN_SLOT] == token &&
            status[STATUS_CODE_SLOT] != 6u;
        if (!diagnosed) record_min_token_error(status, token, 6u, 0x474e0006u);
    }
    return false;
}

uint array_element_decl_token(uint instance)
{
    if (!valid_instance(instance)) return INVALID;
    uint tag = type_instance_elem_ref_tag[instance];
    uint payload = type_instance_elem_ref_payload[instance];
    if (tag == TYPE_REF_INSTANCE && valid_instance(payload))
        return type_instance_decl_token[payload];
    if (tag == TYPE_REF_SCALAR)
        return native_nominal_token(payload, gParams.n_tokens, type_native_scalar_identity);
    return INVALID;
}

uint element_aggregate_words(uint tag, uint payload)
{
    if (tag == TYPE_REF_INSTANCE && valid_instance(payload)) return type_native_word_count[payload];
    if (tag == TYPE_REF_SCALAR && payload == 7u) return 2u;
    if (tag == TYPE_REF_SCALAR)
    {
        uint token = native_nominal_token(payload, gParams.n_tokens, type_native_scalar_identity);
        if (token != INVALID) return type_native_word_count[token];
    }
    return 0u;
}

// The array facts of `node` with checked container `instance`: its length,
// and with `full` also its reference, element declaration and words.
void publish_array_facts(uint node, uint instance, bool full)
{
    if (full) publish_ref(node, TYPE_REF_INSTANCE, instance);
    uint length;
    bool fixed = publish_array_length(node, instance, length);
    if (!full || !valid_hir(node)) return;
    uint decl_token = array_element_decl_token(instance);
    if (valid_token(decl_token))
        semantic_aggregate_decl_token_by_hir[node] = decl_token;
    if (fixed)
    {
        uint width = element_aggregate_words(type_instance_elem_ref_tag[instance],
            type_instance_elem_ref_payload[instance]);
        if (width != 0u && width != INVALID && length <= (INVALID - 1u) / width)
            semantic_aggregate_word_count_by_hir[node] = length * width;
    }
}

void publish_array_literal_element_decl(uint node)
{
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_ARRAY_EXPR ||
        compact_array_element_count[node] == 0u)
        return;
    uint start = compact_array_element_start[node];
    if (start >= min(compact_array_element_row_count[0u], gParams.n_hir_nodes)) return;
    uint element = compact_array_elements[start].value;
    if (!valid_hir(element)) return;
    uint decl_token = semantic_aggregate_decl_token_by_hir[element];
    if (valid_token(decl_token))
        semantic_aggregate_decl_token_by_hir[node] = decl_token;
}

#define DECLARED_CONTEXT_CANONICAL LateIds
#include "../../array_literal_expected.slang"

uint contextual_array_instance(uint node)
{
    if (valid_hir(node) && call_inference_result_tag[node] == TYPE_REF_INSTANCE)
    {
        uint instance = call_inference_result_payload[node];
        if (valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY)
            return instance;
    }
    return declared_array_literal_instance(node);
}

// The innermost non-index base of index chain `node`, with the number of
// indices above it; INVALID when the chain does not end in a value.
uint index_chain_root(uint node, out uint indices)
{
    indices = 0u;
    uint root = node;
    for (uint depth = 0u; depth < 64u && valid_hir(root); depth++)
    {
        root = forwarded_expression(root);
        if (!valid_hir(root)) return INVALID;
        if (compact_hir_core[root].kind != HIR_INDEX_EXPR) break;
        indices++;
        root = compact_hir_payload[root].b;
    }
    if (!valid_hir(root) || compact_hir_core[root].kind == HIR_INDEX_EXPR || indices == 0u)
        return INVALID;
    return root;
}

// `literal_instance` is the contextual instance of `root` when it is an
// array literal.
bool checked_index_base_reference(uint node, uint root, uint indices, uint literal_instance,
    out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID; payload = INVALID;
    if (checked_value_index_reference(node, active_hir_count(), gParams.n_tokens,
        compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
        decl_type_ref_payload, member_result_ref_tag, member_result_ref_payload,
        semantic_calls_by_hir, type_instance_kind, type_instance_elem_ref_tag,
        type_instance_elem_ref_payload, tag, payload)) return true;
    if (!valid_hir(root)) return false;

    // Read the accepted root reference, not an earlier index lane's output.
    // These producer tables are immutable throughout this projection pass.
    uint kind = compact_hir_core[root].kind;
    if (kind == HIR_NAME_EXPR || kind == HIR_PATH_EXPR)
    {
        uint token = name_token(root);
        uint declaration = valid_token(token) ? visible_decl[token] : INVALID;
        if (!valid_token(declaration)) declaration = token;
        if (!valid_token(declaration)) return false;
        tag = decl_type_ref_tag[declaration]; payload = decl_type_ref_payload[declaration];
    }
    else if (kind == 19u)
    {
        CheckedCallArtifact call = semantic_calls_by_hir[root];
        tag = call.return_ref_tag; payload = call.return_ref_payload;
    }
    else if (kind == 21u)
    {
        uint token = compact_hir_payload[root].c;
        if (!valid_token(token)) return false;
        tag = member_result_ref_tag[token]; payload = member_result_ref_payload[token];
    }
    else if (kind == HIR_ARRAY_EXPR)
    {
        tag = TYPE_REF_INSTANCE; payload = literal_instance;
    }
    else return false;

    return checked_index_elements(indices, type_instance_kind,
        type_instance_elem_ref_tag, type_instance_elem_ref_payload, tag, payload);
}

uint aggregate_word_count(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_instance(payload)) return 0u;
    uint count;
    if (native_array_count(payload, count))
        return type_native_word_count[payload];
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    bool literal_node = core.kind == HIR_ARRAY_EXPR;
    if (core.kind == HIR_FN && valid_token(payload.b))
        semantic_function_result_word_count_by_hir[node] = aggregate_word_count(
            fn_return_ref_tag[payload.b], fn_return_ref_payload[payload.b]);
    uint index_node = core.kind == HIR_INDEX_EXPR ? node : INVALID;
    bool for_node = core.kind == HIR_FOR_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
    uint base_node = index_node != INVALID
        ? payload.b
        : for_node ? payload.c : node;
    base_node = literal_node ? node : forwarded_expression(base_node);
    bool nested_index_base = !literal_node && valid_hir(base_node) &&
        compact_hir_core[base_node].kind == HIR_INDEX_EXPR;
    uint indices = 0u;
    uint root = nested_index_base ? index_chain_root(base_node, indices) : INVALID;
    // One array literal per lane: the lane's own, or the root of its index
    // chain.
    uint literal = literal_node ? node
        : valid_hir(root) && compact_hir_core[root].kind == HIR_ARRAY_EXPR ? root : INVALID;
    uint literal_instance = valid_hir(literal) ? contextual_array_instance(literal) : INVALID;

    // Array facts, published at the end: (first_node, first_instance), with
    // its reference too when first_full, then (second_node, second_instance).
    uint first_node = INVALID; uint first_instance = INVALID; bool first_full = false;
    uint second_node = INVALID; uint second_instance = INVALID;
    if (literal_node)
    {
        if (!valid_instance(literal_instance) ||
            type_instance_kind[literal_instance] != TYPE_INSTANCE_ARRAY) return;
        first_node = node; first_instance = literal_instance; first_full = true;
    }
    else
    {
        // The inference producer owns the binder's checked identity. Direct
        // ranges do not have an aggregate iterable instance; named range kinds
        // were retained while their immutable dependency page was resident.
        if (for_node && valid_token(payload.b))
        {
            uint iterable_kind = semantic_iterable_kind_by_hir[node];
            bool direct_range = valid_hir(base_node) &&
                (compact_hir_core[base_node].kind == 14u || compact_hir_core[base_node].kind == 16u) &&
                compact_hir_payload[base_node].a >= 30u && compact_hir_payload[base_node].a <= 35u;
            if (direct_range || iterable_kind == ITERABLE_EXCLUSIVE_RANGE ||
                iterable_kind == ITERABLE_INCLUSIVE_RANGE)
            {
                publish_ref(node, decl_type_ref_tag[payload.b], decl_type_ref_payload[payload.b]);
                return;
            }
        }
        // The preceding expression-reference pass already checked projections
        // such as `region.data` and calls returning slices. A name-only lookup
        // loses their instance type (and therefore their runtime length).
        uint instance = valid_hir(base_node) &&
            semantic_expr_ref_tag_by_hir[base_node] == TYPE_REF_INSTANCE
                ? semantic_expr_ref_payload_by_hir[base_node] : INVALID;
        if (nested_index_base)
        {
            // Resolve the whole projection from its accepted root without
            // depending on another lane publishing the inner index first.
            uint base_tag; uint base_payload;
            bool resolved = checked_index_base_reference(base_node, root, indices, literal_instance,
                base_tag, base_payload);
            instance = resolved && base_tag == TYPE_REF_INSTANCE ? base_payload : INVALID;
        }
        if (!valid_instance(instance))
        {
            uint token = name_token(base_node);
            uint decl = valid_token(token) ? visible_decl[token] : INVALID;
            if (!valid_token(decl) || decl_type_ref_tag[decl] != TYPE_REF_INSTANCE)
                return;
            instance = decl_type_ref_payload[decl];
        }
        if (!valid_instance(instance)) return;
        uint kind = type_instance_kind[instance];
        if (for_node)
        {
            // Reference indexing has an explicit native projection recipe. For
            // iteration, retain the existing accepted direct-container contract.
            if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE) return;
        }
        uint source_instance = instance;
        if (!checked_index_container(TYPE_REF_INSTANCE, source_instance, type_instance_kind,
            type_instance_elem_ref_tag, type_instance_elem_ref_payload, instance)) return;
        kind = type_instance_kind[instance];

        uint elem_tag = type_instance_elem_ref_tag[instance];
        uint elem_payload = type_instance_elem_ref_payload[instance];
        if (elem_tag == TYPE_REF_INVALID || elem_payload == INVALID) return;

        // Bounds describe the terminal container; source type and layout still
        // describe the original value. In particular, &array is one pointer, not
        // an inline array. An inner index keeps its actual element reference too.
        first_node = base_node; first_instance = instance;
        first_full = !nested_index_base && source_instance == instance;
        uint element_node = for_node ? node : index_node;
        if (valid_hir(element_node))
        {
            publish_ref(element_node, elem_tag, elem_payload);
            semantic_aggregate_word_count_by_hir[element_node] = elem_tag == TYPE_REF_SCALAR && elem_payload == 7u
                ? 0u : element_aggregate_words(elem_tag, elem_payload);
            uint element_decl = array_element_decl_token(instance);
            if (valid_token(element_decl))
                semantic_aggregate_decl_token_by_hir[element_node] = element_decl;
        }
        if (for_node)
        {
            if (kind == TYPE_INSTANCE_ARRAY) { second_node = node; second_instance = instance; }
        }
        else if (index_node != INVALID)
        {
            uint element_container;
            if (checked_index_container(elem_tag, elem_payload, type_instance_kind,
                type_instance_elem_ref_tag, type_instance_elem_ref_payload, element_container))
            {
                second_node = index_node; second_instance = element_container;
            }
        }
    }
    [loop]
    for (uint job = 0u; job < 2u; job++)
        publish_array_facts(job == 0u ? first_node : second_node,
            job == 0u ? first_instance : second_instance, job == 0u && first_full);
    if (literal_node) publish_array_literal_element_decl(node);
}
