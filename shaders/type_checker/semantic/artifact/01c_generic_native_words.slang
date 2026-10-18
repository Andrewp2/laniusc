import primitive_types;
import type_checker.checked_array_counts;
import native_value_layout;
import type_checker.checked_canonical;
import type_checker.checked_type_graph;
// Checked native widths for concrete generic values. These facts stay private
// to body compilation; durable type and object records are unchanged.

import hir_records;
import gpu_index;
import checked_semantic_artifact;
import type_checker.local_struct_layout;
import type_checker.native_nominal_identity;
import type_checker.concrete_value_layout;
import type_checker.dependencies.retained_value_layout;
import status;

bool valid_instance(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> type_instance_aggregate_word_count;
StructuredBuffer<uint4> body_specialization_inputs;
#include "../../type/instances/body_graph_rows.slang"
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;
static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_CONST = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint type_head_token(uint node)
{
    uint path = node < active_hir_count() ? path_id_by_owner_hir[node] : INVALID;
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path < path_count)
    {
        uint count = path_segment_count[path];
        uint row = count != 0u ? path_segment_base[path] + count - 1u : INVALID;
        if (row < gParams.n_tokens && valid_token(path_segment_token[row]))
            return path_segment_token[row];
    }
    return node < active_hir_count() ? compact_hir_core[node].token_start : INVALID;
}

// Bare nominal references and applied nominal references share declaration
// structure. Their representation never determines whether a value is scalar.
uint local_nominal_owner(uint tag, uint payload, uint wanted_kind)
{
    uint decl = INVALID;
    if (tag == TYPE_REF_INSTANCE && valid_instance(payload) && type_instance_kind[payload] == 1u)
        decl = type_instance_decl_token[payload];
    else if (tag == TYPE_REF_SCALAR)
        decl = native_nominal_declaration_token(payload, gParams.n_tokens,
            active_hir_count(), type_decl_hir_node_by_token, compact_hir_core);
    uint owner = valid_token(decl) ? type_decl_hir_node_by_token[decl] : INVALID;
    return valid_hir(owner) && compact_hir_core[owner].kind == wanted_kind ? owner : INVALID;
}

uint local_enum_owner(uint tag, uint payload)
{ return local_nominal_owner(tag, payload, HIR_ENUM_ITEM); }

uint local_struct_owner(uint tag, uint payload)
{ return local_nominal_owner(tag, payload, HIR_STRUCT_ITEM); }

bool native_array_count(uint instance, out uint count)
{
    count = 0u;
    return valid_instance(instance) && type_instance_kind[instance] == 2u &&
        checked_source_array_count(type_instance_len_kind[instance],
            type_instance_len_payload[instance], gParams.n_tokens, count) &&
        count < 0xfffffffeu;
}

public struct CheckedConcreteValueLayout : IConcreteValueLayout
{
    public static uint leaf_words(uint tag, uint payload)
    {
        if (tag == 1u)
        {
            if (scalar_is_known(payload)) return payload == SCALAR_STR ? 2u : 1u;
            // Nominal leaves expand through the same field/variant graph as
            // applied types, including arrays, descriptors and nested enums.
            return INVALID;
        }
        if (tag != 3u || !valid_instance(payload)) return INVALID;
        if (type_instance_kind[payload] == 4u) return 1u;
        if (type_instance_kind[payload] == 3u) return NATIVE_SLICE_WORDS;
        if (type_instance_kind[payload] == 2u) return INVALID;
        // A closed replay graph may retain an exact native width witness from
        // its checking unit. Foreign private definitions can be opaque here.
        // Read the immutable seed, not a concurrently produced layout column.
        // Missing witnesses fall through to the ordinary checked payload graph.
        uint source_capacity; uint stride;
        type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
        uint seed_count = body_graph_node_count();
        if (payload >= source_capacity && payload - source_capacity < seed_count)
        {
            uint witness = body_graph_node(payload - source_capacity).w;
            if (witness != INVALID) return witness;
        }
        // Concrete enum layouts must be evaluated from their checked payload
        // graph. An earlier dependency projection can still lack a child's
        // width and therefore cannot establish the enclosing enum's width.
        if (local_struct_owner(tag, payload) != INVALID ||
            local_enum_owner(tag, payload) != INVALID || retained_layout_kind(payload) != 0u) return INVALID;
        // An imported nominal needs its retained payload groups. Page absence
        // cannot authorize a partial cached field count as a native width.
        if (type_instance_kind[payload] == 1u &&
            external_type_library_id[payload] != INVALID) return INVALID;
        uint cached = type_instance_aggregate_word_count[payload];
        return cached != 0u ? cached : INVALID;
    }

    public static uint group_count(uint tag, uint payload)
    {
        if (local_struct_owner(tag, payload) != INVALID) return 1u;
        if (local_enum_owner(tag, payload) != INVALID)
            return min(compact_variant_count[0u], gParams.n_hir_nodes);
        if (tag != 3u || !valid_instance(payload)) return 0u;
        if (type_instance_kind[payload] == 2u)
        {
            uint count;
            return native_array_count(payload, count) ? 1u : 0u;
        }
        return retained_layout_kind(payload) != 0u ? imported_layout_group_count[payload] : 0u;
    }

    public static uint overhead(uint tag, uint payload)
    {
        if (local_struct_owner(tag, payload) != INVALID) return 0u;
        return tag == 3u && valid_instance(payload) &&
            (type_instance_kind[payload] == 2u || retained_layout_kind(payload) == 6u) ? 0u : 1u;
    }

    public static uint repetitions(uint tag, uint payload)
    {
        if (tag == 3u && valid_instance(payload) && type_instance_kind[payload] == 2u)
        {
            uint count;
            return native_array_count(payload, count) ? count : INVALID;
        }
        return 1u;
    }

    public static uint payload_count(uint tag, uint payload, uint group)
    {
        if (tag == 3u && valid_instance(payload) && type_instance_kind[payload] == 2u)
            return 1u;
        uint struct_owner = local_struct_owner(tag, payload);
        if (struct_owner != INVALID)
        {
            uint count = min(compact_field_count[0u], gParams.n_hir_nodes);
            return first_local_struct_field(compact_hir_core[struct_owner].token_end, count, compact_fields)
                - first_local_struct_field(compact_hir_core[struct_owner].token_start, count, compact_fields);
        }
        uint owner = local_enum_owner(tag, payload);
        if (owner != INVALID)
            return group < min(compact_variant_count[0u], gParams.n_hir_nodes) &&
                compact_variants[group].owner == owner ? compact_variant_payload_count[group] : INVALID;
        if (tag != TYPE_REF_INSTANCE) return INVALID;
        uint2 retained;
        return retained_layout_group(payload, group, retained) ? retained.y : INVALID;
    }

    public static bool payload_ref(uint tag, uint payload, uint group, uint ordinal,
        out uint child_tag, out uint child_payload)
    {
        child_tag = 0u; child_payload = INVALID;
        if (tag == 3u && valid_instance(payload) && type_instance_kind[payload] == 2u)
        {
            child_tag = type_instance_elem_ref_tag[payload];
            child_payload = type_instance_elem_ref_payload[payload];
            return child_tag != 0u && child_payload != INVALID;
        }
        uint owner = local_struct_owner(tag, payload);
        uint type_node = INVALID;
        if (owner != INVALID)
        {
            uint count = min(compact_field_count[0u], gParams.n_hir_nodes);
            uint start = first_local_struct_field(compact_hir_core[owner].token_start, count, compact_fields);
            if (start >= count || ordinal >= count - start) return false;
            HirField field = compact_fields[start + ordinal];
            if (field.owner != owner || field.ordinal != ordinal) return false;
            type_node = field.value;
        }
        else owner = local_enum_owner(tag, payload);
        if (owner != INVALID)
        {
            if (type_node == INVALID)
            {
                uint start = compact_variant_payload_start[group];
                uint total = min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
                if (start >= total || ordinal >= total - start) return false;
                HirVariantPayload field = compact_variant_payloads[start + ordinal];
                if (field.variant != group || field.ordinal != ordinal) return false;
                type_node = field.type_node;
            }
            if (!valid_hir(type_node)) return false;
            uint token = type_head_token(type_node);
            if (!valid_token(token)) return false;
            child_tag = type_expr_ref_tag[token];
            child_payload = type_expr_ref_payload[token];
            if (child_tag == 2u)
            {
                if (tag != TYPE_REF_INSTANCE || !valid_token(child_payload)) return false;
                uint slot = type_generic_param_slot_by_token[child_payload];
                return ScopedCheckedTypeGraph.environment_argument(payload, slot, child_tag, child_payload);
            }
            if (child_tag == 3u)
                return canonical_checked_scoped_reference<LateIds>(child_tag, child_payload,
                    tag == TYPE_REF_INSTANCE ? payload : INVALID, gParams.n_tokens, child_tag, child_payload);
        }
        else
        {
            if (tag != TYPE_REF_INSTANCE) return false;
            return retained_layout_child(payload, group, ordinal, child_tag, child_payload);
        }
        return child_tag != 0u && child_payload != INVALID;
    }
}

// The layout words of every checked type node, memoized for the pass: node
// n < capacity is row n (tag 3) and node capacity + d is local nominal
// declaration d read through its bare scalar code (tag 1). An entry is 0
// while unknown, INVALID without a native layout, and otherwise words + 1
// (a width of exactly 0xfffffffe words has no entry and reads as INVALID).
// Each lane evaluates its root one level at a time over the entries every
// lane publishes, so a node's layout is evaluated once, not once per
// enclosing type, and no lane keeps a stack.
RWStructuredBuffer<uint> type_native_word_memo;
RWStructuredBuffer<uint> status;
static const uint LAYOUT_NODE_NONE = 0xffffffffu;
static const uint LAYOUT_STEP_DONE = 0xffffffffu;
// The walker's depth bound: a path of more than 64 nodes has no layout.
static const uint LAYOUT_DEPTH_LIMIT = 64u;
// Each descent publishes at least one node.
static const uint LAYOUT_DESCENT_LIMIT = 1u << 20u;

uint layout_memo_capacity()
{
    uint capacity; uint stride;
    type_native_word_memo.GetDimensions(capacity, stride);
    return capacity;
}

// The memo node of checked reference (tag, payload), or LAYOUT_NODE_NONE
// with its words (a scalar leaf, or INVALID without a layout) in `words`.
uint layout_node(uint tag, uint payload, out uint words)
{
    words = INVALID;
    uint capacity = checked_type_capacity();
    uint node = LAYOUT_NODE_NONE;
    if (tag == TYPE_REF_INSTANCE && payload < capacity) node = payload;
    else if (tag == TYPE_REF_SCALAR)
    {
        if (scalar_is_known(payload))
        {
            words = payload == SCALAR_STR ? 2u : 1u;
            return LAYOUT_NODE_NONE;
        }
        // Nominal codes expand through their declaration; an ambiguous code
        // has none.
        uint declaration = native_nominal_declaration_token(payload, gParams.n_tokens,
            active_hir_count(), type_decl_hir_node_by_token, compact_hir_core);
        if (valid_token(declaration)) node = capacity + declaration;
    }
    return node < layout_memo_capacity() ? node : LAYOUT_NODE_NONE;
}

// The checked reference memo node `node` stands for.
void layout_node_ref(uint node, out uint tag, out uint payload)
{
    uint capacity = checked_type_capacity();
    tag = TYPE_REF_INSTANCE; payload = node;
    if (node < capacity) return;
    uint declaration = node - capacity;
    uint owner = type_decl_hir_node_by_token[declaration];
    tag = TYPE_REF_SCALAR;
    payload = (compact_hir_core[owner].kind == HIR_STRUCT_ITEM ? TY_STRUCT_BASE : TY_ENUM_BASE) + declaration;
}

// GPU type-check status code: a struct or enum contains itself by value.
static const uint TYPE_CHECK_RECURSIVE_TYPE = 28u;

// A value of memo node `node` would contain itself, so it has no finite
// layout. Report the local struct or enum declaration at its name token;
// codegen would otherwise only find a missing aggregate layout.
void report_recursive_layout(uint node)
{
    uint capacity = checked_type_capacity();
    uint declaration = INVALID;
    if (node >= capacity) declaration = node - capacity;
    else if (type_instance_kind[node] == 1u) declaration = type_instance_decl_token[node];
    if (!valid_token(declaration)) return;
    uint owner = type_decl_hir_node_by_token[declaration];
    if (!valid_hir(owner)) return;
    uint kind = compact_hir_core[owner].kind;
    if (kind == HIR_STRUCT_ITEM || kind == HIR_ENUM_ITEM)
        record_min_token_error(status, declaration, TYPE_CHECK_RECURSIVE_TYPE, 0u);
}

void layout_publish(uint node, uint words)
{
    type_native_word_memo[node] = words >= INVALID - 1u ? INVALID : words + 1u;
}

uint layout_entry_words(uint entry)
{
    return entry == INVALID ? INVALID : entry - 1u;
}

// One level of concrete_value_words at memo node `node`. When the words of
// every child are known it publishes the node's words and returns
// LAYOUT_STEP_DONE; otherwise it returns the first child still unknown.
uint layout_step(uint node)
{
    uint tag; uint payload;
    layout_node_ref(node, tag, payload);
    uint words = CheckedConcreteValueLayout.leaf_words(tag, payload);
    if (words == INVALID)
    {
        uint groups = CheckedConcreteValueLayout.group_count(tag, payload);
        if (groups == 0u || groups == INVALID)
        {
            layout_publish(node, INVALID);
            return LAYOUT_STEP_DONE;
        }
        // Groups sum their payload widths; the value uses the largest group.
        words = 0u;
        for (uint group = 0u; group < groups; group++)
        {
            uint count = CheckedConcreteValueLayout.payload_count(tag, payload, group);
            if (count == INVALID) continue;
            uint total = CheckedConcreteValueLayout.overhead(tag, payload);
            for (uint ordinal = 0u; ordinal < count; ordinal++)
            {
                uint child_tag; uint child_payload;
                uint child_words = INVALID;
                uint child = CheckedConcreteValueLayout.payload_ref(tag, payload, group, ordinal,
                    child_tag, child_payload)
                    ? layout_node(child_tag, child_payload, child_words) : LAYOUT_NODE_NONE;
                // A finite concrete type cannot contain itself by value.
                if (child == node)
                {
                    report_recursive_layout(node);
                    child_words = INVALID;
                }
                else if (child != LAYOUT_NODE_NONE)
                {
                    uint entry = type_native_word_memo[child];
                    if (entry == 0u) return child;
                    child_words = layout_entry_words(entry);
                }
                if (child_words == INVALID || total >= INVALID - child_words)
                {
                    layout_publish(node, INVALID);
                    return LAYOUT_STEP_DONE;
                }
                total += child_words;
            }
            words = max(words, total);
        }
    }
    uint repetitions = CheckedConcreteValueLayout.repetitions(tag, payload);
    if (repetitions == INVALID || (repetitions != 0u && words > (INVALID - 1u) / repetitions))
        words = INVALID;
    else words *= repetitions;
    layout_publish(node, words);
    return LAYOUT_STEP_DONE;
}

// Follows unknown children from `root` and publishes the first node whose
// children are all known; false when the path is longer than the walker's
// bound. A path back to the root is a cycle, so the root has no layout.
bool layout_descend(uint root)
{
    uint node = root;
    for (uint depth = 0u; depth < LAYOUT_DEPTH_LIMIT; depth++)
    {
        uint next = layout_step(node);
        if (next == LAYOUT_STEP_DONE) return true;
        if (next == root)
        {
            report_recursive_layout(root);
            layout_publish(root, INVALID);
            return true;
        }
        node = next;
    }
    return false;
}

// The native words of checked reference (tag, payload), as
// concrete_value_words<CheckedConcreteValueLayout> computes them.
uint layout_words(uint tag, uint payload)
{
    uint words;
    uint root = layout_node(tag, payload, words);
    if (root == LAYOUT_NODE_NONE) return words;
    for (uint descent = 0u; descent < LAYOUT_DESCENT_LIMIT; descent++)
    {
        uint entry = type_native_word_memo[root];
        if (entry != 0u) return layout_entry_words(entry);
        if (!layout_descend(root)) return INVALID;
    }
    return INVALID;
}

RWStructuredBuffer<uint> type_native_word_count;
RWStructuredBuffer<uint> type_native_scalar_identity;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (token >= gParams.n_tokens) return;
    uint capacity = checked_type_capacity();
    uint source_capacity; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
    uint seed_count = body_graph_node_count();
    // One evaluation site handles source and generated rows.
    for (uint instance = token; instance < capacity;)
    {
        uint tag = TYPE_REF_INSTANCE;
        uint payload = instance;
        uint scalar = 0u;
        if (instance < source_capacity)
        {
            uint declaration = type_decl_hir_node_by_token[instance];
            if (valid_hir(declaration))
            {
                uint kind = compact_hir_core[declaration].kind;
                if (kind == HIR_STRUCT_ITEM || kind == HIR_ENUM_ITEM)
                {
                    scalar = (kind == HIR_STRUCT_ITEM ? TY_STRUCT_BASE : TY_ENUM_BASE) + instance;
                    // Complete bare nominal declarations use the same graph
                    // root as applications. Legacy codes can overlap and are
                    // published only as derived compatibility facts.
                    if (type_instance_kind[instance] != 1u ||
                        type_instance_decl_token[instance] != instance)
                    {
                        tag = TYPE_REF_SCALAR;
                        payload = scalar;
                    }
                }
            }
        }
        else if (instance - source_capacity < seed_count)
        {
            // Keep the seed's completed width in seed-node order even when a
            // source-owned bare nominal replays through its checked scalar
            // reference. Cache admission reads this exact contiguous result.
            uint ordinal = instance - source_capacity;
            uint4 node = body_graph_node(ordinal);
            uint anchor = body_graph_identity(ordinal).w;
            if (node.x == 9u && (anchor & 0xe0000000u) == 0x40000000u)
            { tag = TYPE_REF_SCALAR; payload = anchor & 0x1fffffffu; }
        }
        type_native_scalar_identity[instance] = scalar;
        type_native_word_count[instance] = layout_words(tag, payload);
        // Only active seed rows participate; inactive reserved storage can
        // belong to a previous job. Ordinary jobs retain their existing walk.
        if (instance < source_capacity)
            instance = source_capacity + (token < seed_count ? token : BODY_GRAPH_NODES + token);
        else if (instance - source_capacity < BODY_GRAPH_NODES)
        {
            uint ordinal = instance - source_capacity;
            instance = ordinal < seed_count && gParams.n_tokens < seed_count - ordinal
                ? instance + gParams.n_tokens : source_capacity + BODY_GRAPH_NODES + token;
        }
        else if (gParams.n_tokens >= capacity - instance) break;
        else instance += gParams.n_tokens;
    }
}
