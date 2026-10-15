import native_value_layout;
import type_checker.checked_array_counts;
// Compute the by-value machine-word layout of each fixed struct. One lane owns
// one declaration and writes only that declaration's direct field rows. Nested
// declarations are traversed read-only, so independent layouts remain parallel.

import hir_records;
import gpu_index;

// root_rows selects the lanes: one per HIR row, or (in the fixed-point
// rounds) one per field row, where only a struct's first field row takes the
// struct. A struct without fields keeps its first-pass width of zero, so the
// rounds need not visit it.
struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint root_rows; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_field_start_by_hir;
StructuredBuffer<uint> semantic_struct_field_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_word_offset_by_row;
RWStructuredBuffer<uint> semantic_struct_field_word_count_by_row;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint MAX_LAYOUT_DEPTH = 64u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint LAYOUT_ROOTS_FIRST_FIELD_ROWS = 1u;

uint nested_struct(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return INVALID;
    uint token = semantic_aggregate_decl_token[type_node];
    if (token >= gParams.n_tokens && semantic_expr_ref_tag[type_node] == TYPE_REF_SCALAR)
    {
        uint type_id = semantic_expr_ref_payload[type_node];
        if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
            token = type_id - TY_STRUCT_BASE;
    }
    if (token >= gParams.n_tokens)
    {
        uint source_token = compact_hir_core[type_node].token_start;
        if (source_token < gParams.n_tokens &&
            semantic_aggregate_hir_by_name_token[source_token] < hir_count)
            token = source_token;
    }
    // Canonical type rows retain their path/value HIR in payload.b. Checked
    // type projection normally resolves the wrapper itself; following the
    // canonical value is the general fallback for declaration-field types.
    uint value_node = compact_hir_payload[type_node].b;
    if (token >= gParams.n_tokens && value_node < hir_count)
    {
        token = semantic_aggregate_decl_token[value_node];
        if (token >= gParams.n_tokens &&
            semantic_expr_ref_tag[value_node] == TYPE_REF_SCALAR)
        {
            uint type_id = semantic_expr_ref_payload[value_node];
            if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
                token = type_id - TY_STRUCT_BASE;
        }
        if (token >= gParams.n_tokens)
        {
            uint source_token = compact_hir_core[value_node].token_start;
            if (source_token < gParams.n_tokens &&
                semantic_aggregate_hir_by_name_token[source_token] < hir_count)
                token = source_token;
        }
    }
    if (token >= gParams.n_tokens) return INVALID;
    uint result = semantic_aggregate_hir_by_name_token[token];
    return result < hir_count && compact_hir_core[result].kind == HIR_STRUCT_ITEM
        ? result : INVALID;
}

uint array_length(uint type_node, uint hir_count)
{
    if (type_node >= hir_count) return INVALID;
    if (semantic_expr_ref_tag[type_node] == 3u)
    {
        uint instance = semantic_expr_ref_payload[type_node];
        uint capacity; uint stride;
        type_instance_kind.GetDimensions(capacity, stride);
        if (instance >= capacity) return INVALID;
        if (type_instance_kind[instance] == 2u)
        {
            uint count;
            return checked_source_array_count(type_instance_len_kind[instance],
                type_instance_len_payload[instance], gParams.n_tokens, count) &&
                count < 0xfffffffeu ? count : INVALID;
        }
    }
    // A syntactic fixed array without its checked instance has no length.
    // HIR payload.d names an operand node; it is never an inline count.
    return compact_hir_core[type_node].kind == HIR_TYPE &&
        compact_hir_payload[type_node].a == HIR_TYPE_FORM_ARRAY ? INVALID : 1u;
}

uint array_element_type(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return type_node;
    HirPayload payload = compact_hir_payload[type_node];
    return payload.a == HIR_TYPE_FORM_ARRAY ? payload.b : type_node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint root = lane;
    if (gParams.root_rows == LAYOUT_ROOTS_FIRST_FIELD_ROWS)
    {
        if (lane >= min(compact_field_count[0u], gParams.n_hir_nodes)) return;
        root = compact_fields[lane].owner;
        if (root >= hir_count || semantic_struct_field_start_by_hir[root] != lane)
            return;
    }
    if (root >= hir_count || compact_hir_core[root].kind != HIR_STRUCT_ITEM) return;

    // The traversal keeps two words per nested frame: the field row it was
    // entered through and its running word total. Everything else a frame
    // needs follows from that row (compact_fields is immutable here): its
    // parent's struct is the row's owner, the parent resumes after the row's
    // ordinal, and its multiplier is the row's array length. The top frame's
    // struct and next ordinal live in `current` and `next`.
    uint entry_field[MAX_LAYOUT_DEPTH];
    uint frame_total[MAX_LAYOUT_DEPTH];
    uint depth = 0u;
    uint current = root;
    uint next = 0u;
    entry_field[0u] = INVALID;
    frame_total[0u] = 0u;

    for (;;)
    {
        uint count = semantic_struct_field_count_by_hir[current];
        uint start = semantic_struct_field_start_by_hir[current];
        if (next >= count)
        {
            uint parent_field = entry_field[depth];
            uint multiplier = depth == 0u
                ? 1u : array_length(compact_fields[parent_field].value, hir_count);
            if (multiplier != 0u &&
                frame_total[depth] > (INVALID - 1u) / multiplier)
            {
                semantic_struct_word_count_by_hir[root] = INVALID;
                return;
            }
            uint completed = frame_total[depth] * multiplier;
            if (depth == 0u)
            {
                semantic_struct_word_count_by_hir[root] = completed;
                return;
            }
            depth -= 1u;
            if (depth == 0u && parent_field != INVALID)
            {
                semantic_struct_field_word_offset_by_row[parent_field] = frame_total[0u];
                semantic_struct_field_word_count_by_row[parent_field] = completed;
            }
            if (frame_total[depth] >= INVALID - completed)
            {
                semantic_struct_word_count_by_hir[root] = INVALID;
                return;
            }
            frame_total[depth] += completed;
            HirField entered = compact_fields[parent_field];
            current = entered.owner;
            next = entered.ordinal + 1u;
            continue;
        }

        uint ordinal = next++;
        uint field_row = start != INVALID ? start + ordinal : INVALID;
        if (field_row >= gParams.n_hir_nodes)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        HirField field = compact_fields[field_row];
        if (field.owner != current || field.ordinal != ordinal)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }

        // Complete checked field applications already have their concrete
        // layout. A generic enum/record declaration's pending cache cannot
        // override a concrete application, including a zero-word array.
        if (field.value < hir_count && semantic_expr_ref_tag[field.value] == 3u)
        {
            uint instance = semantic_expr_ref_payload[field.value];
            uint capacity; uint stride;
            type_instance_native_words.GetDimensions(capacity, stride);
            uint words = instance < capacity ? type_instance_native_words[instance] : INVALID;
            if (words == INVALID || frame_total[depth] >= INVALID - words)
            {
                semantic_struct_word_count_by_hir[root] = INVALID;
                return;
            }
            if (depth == 0u)
            {
                semantic_struct_field_word_offset_by_row[field_row] = frame_total[0u];
                semantic_struct_field_word_count_by_row[field_row] = words;
            }
            frame_total[depth] += words;
            continue;
        }

        bool slice_field = field.value < hir_count &&
            compact_hir_core[field.value].kind == HIR_TYPE &&
            compact_hir_payload[field.value].a == HIR_TYPE_FORM_SLICE;
        uint cached_width = semantic_struct_field_word_count_by_row[field_row];
        if (cached_width == INVALID)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        uint multiplier = slice_field ? NATIVE_SLICE_WORDS
            : array_length(field.value, hir_count);
        if (multiplier == INVALID)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        uint element_type = array_element_type(field.value, hir_count);
        if (!slice_field && element_type < hir_count &&
            semantic_expr_ref_tag[element_type] == 2u)
        {
            // Declaration layouts cannot guess one word for an unbound T.
            // Every containing record and field offset waits for its concrete
            // receiver environment, even when the accessed result is scalar.
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        // A slice owns a three-word descriptor, not an inline copy of its
        // element type (even when that element is a nominal struct).
        uint child = slice_field ? INVALID
            : nested_struct(element_type, hir_count);
        if (child == INVALID)
        {
            // A str field stores its existing pointer-and-length descriptor.
            // Its checked scalar code is not a one-word scalar layout.
            if (!slice_field && element_type < hir_count &&
                semantic_expr_ref_tag[element_type] == TYPE_REF_SCALAR &&
                semantic_expr_ref_payload[element_type] == 7u)
            {
                if (multiplier > (INVALID - 1u) / 2u)
                {
                    semantic_struct_word_count_by_hir[root] = INVALID;
                    return;
                }
                multiplier *= 2u;
            }
            // Only enum fields cache a complete non-struct layout between
            // passes. A cached struct width already includes its child and
            // must not become the child's multiplier on the second pass.
            if (cached_width != 0u)
                multiplier = cached_width;
            if (multiplier == INVALID || frame_total[depth] >= INVALID - multiplier)
            {
                semantic_struct_word_count_by_hir[root] = INVALID;
                return;
            }
            if (depth == 0u)
            {
                semantic_struct_field_word_offset_by_row[field_row] = frame_total[0u];
                semantic_struct_field_word_count_by_row[field_row] = multiplier;
            }
            frame_total[depth] += multiplier;
            continue;
        }

        if (depth + 1u >= MAX_LAYOUT_DEPTH)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        // The frames' structs are the root (frame 0's), the owner of each
        // deeper frame's entry row (its parent's), and `current`.
        bool cycle = child == current;
        for (uint ancestor = 1u; ancestor <= depth; ancestor += 1u)
            cycle = cycle || compact_fields[entry_field[ancestor]].owner == child;
        if (cycle)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        // A struct field's multiplier is its array length, which the pop
        // above recomputes from entry_field.
        depth += 1u;
        entry_field[depth] = field_row;
        frame_total[depth] = 0u;
        current = child;
        next = 0u;
    }
}
