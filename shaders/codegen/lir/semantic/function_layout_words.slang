import type_checker.constant_atoms_identity;
import native_value_layout;
// The by-value machine-word width of every struct and enum declaration. One
// lane owns one HIR row; a struct or enum row walks the by-value expansion of
// its declaration and publishes its width, and a struct also publishes the
// offset and width of each of its direct fields. Lanes only read declarations
// and write their own rows, so every declaration's layout is computed in
// parallel in one dispatch, with no rounds between enums and the structs that
// contain them.
//
// A struct is the sum of its fields, each times its array length. An enum is
// the discriminant word plus its widest variant, where a variant is the sum of
// its payloads. Struct and enum fields and nominal payloads are entered as
// nested frames; checked type applications, imported nominals and scalars are
// leaves. Any invalid width in the expansion makes the root invalid. A
// declaration that reaches itself by value has no finite width: the walk
// rejects it as invalid, and function_layout_enum_variants reports it.

import hir_records;
import codegen.lowering_ir;
import gpu_index;
import type_checker.concrete_type_closure;
import type_checker.checked_array_counts;
import type_checker.native_nominal_identity;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_field_start_by_hir;
StructuredBuffer<uint> semantic_struct_field_count_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_word_offset_by_row;
RWStructuredBuffer<uint> semantic_struct_field_word_count_by_row;

#include "function_layout_payload_types.slang"
#include "function_layout_field_types.slang"

static const uint LAYOUT_LANES = 32u;
static const uint DISPATCH_X_STRIDE = 65535u * LAYOUT_LANES;

// A frame is a struct, an enum, or one variant of the enum below it. Frame 0
// is the root declaration. Every deeper frame keeps the row it was entered
// through, tagged with how, and its running total: a struct's word sum, an
// enum's widest variant, or a variant's word sum. The entry row also names
// the frame below and where it resumes, so only the top frame's position
// lives in registers.
static const uint ENTRY_ROW_MASK = 0x3fffffffu;
static const uint ENTRY_STRUCT_FIELD = 0u << 30u; // struct through a field row
static const uint ENTRY_ENUM_FIELD = 1u << 30u;   // enum through a field row
static const uint ENTRY_VARIANT = 2u << 30u;      // variant row of the enum below
static const uint ENTRY_PAYLOAD = 3u << 30u;      // struct or enum through a payload row
static const uint ENTRY_KIND_MASK = 3u << 30u;

static const uint FRAME_STRUCT = 0u;
static const uint FRAME_ENUM = 1u;
static const uint FRAME_VARIANT = 2u;

groupshared uint layout_entry[LAYOUT_LANES * MAX_LAYOUT_DEPTH];
groupshared uint layout_total[LAYOUT_LANES * MAX_LAYOUT_DEPTH];

// The enum an enum-typed field holds by value. Checked type applications,
// arrays and imported enums keep their own widths and are not entered.
uint enum_field_declaration(uint field_value)
{
    if (semantic_expr_ref_tag[field_value] != TYPE_REF_SCALAR) return INVALID;
    uint hir_count = gParams.n_hir_nodes;
    uint token = native_nominal_declaration_token(semantic_expr_ref_payload[field_value],
        gParams.n_tokens, hir_count, semantic_aggregate_hir_by_name_token, compact_hir_core);
    uint declaration = token < gParams.n_tokens
        ? semantic_aggregate_hir_by_name_token[token] : INVALID;
    return declaration < hir_count && compact_hir_core[declaration].kind == HIR_ENUM_ITEM
        ? declaration : INVALID;
}

// The first variant row of `owner`; variant rows are ordered by owner.
uint first_variant_row(uint owner, uint variant_total)
{
    uint lo = 0u;
    uint hi = variant_total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].owner < owner) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

// The declaration of the frame below the one entered through `entry`, or
// INVALID when that frame is a variant.
uint entry_parent_declaration(uint entry)
{
    uint kind = entry & ENTRY_KIND_MASK;
    uint row = entry & ENTRY_ROW_MASK;
    if (kind == ENTRY_STRUCT_FIELD || kind == ENTRY_ENUM_FIELD)
        return compact_fields[row].owner;
    if (kind == ENTRY_VARIANT)
        return compact_variants[row].owner;
    return INVALID;
}

void layout_declaration(uint root, uint base)
{
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (root >= hir_count) return;
    uint root_kind = compact_hir_core[root].kind;
    if (root_kind != HIR_STRUCT_ITEM && root_kind != HIR_ENUM_ITEM) return;
    uint variant_total = min(compact_variant_count[0u], hir_count);
    uint payload_total = min(compact_variant_payload_row_count[0u], hir_count);

    uint depth = 0u;
    uint frame = root_kind == HIR_STRUCT_ITEM ? FRAME_STRUCT : FRAME_ENUM;
    uint current = root;
    uint next = frame == FRAME_STRUCT ? 0u : first_variant_row(root, variant_total);
    layout_entry[base] = INVALID;
    layout_total[base] = frame == FRAME_STRUCT ? 0u : 1u; // discriminant

    for (;;)
    {
        // Advance the top frame by one field, variant or payload. `child`
        // names a declaration to enter through `child_entry`.
        uint child = INVALID;
        uint child_entry = INVALID;
        bool finished = false;
        if (frame == FRAME_STRUCT)
        {
            uint count = semantic_struct_field_count_by_hir[current];
            uint start = semantic_struct_field_start_by_hir[current];
            if (next >= count)
            {
                finished = true;
            }
            else
            {
                uint ordinal = next++;
                uint field_row = start != INVALID ? start + ordinal : INVALID;
                if (field_row >= gParams.n_hir_nodes) break;
                HirField field = compact_fields[field_row];
                if (field.owner != current || field.ordinal != ordinal) break;

                uint field_words = INVALID;
                // Complete checked field applications already have their
                // concrete layout, including a zero-word array.
                if (field.value < hir_count && semantic_expr_ref_tag[field.value] == 3u)
                {
                    uint instance = semantic_expr_ref_payload[field.value];
                    uint capacity; uint stride;
                    type_instance_native_words.GetDimensions(capacity, stride);
                    field_words = instance < capacity ? type_instance_native_words[instance] : INVALID;
                    if (field_words == INVALID) break;
                }
                else
                {
                    // An unbound T has no declaration layout; every containing
                    // record and field offset waits for its concrete receiver.
                    if (field.value < gParams.n_hir_nodes &&
                        semantic_expr_ref_tag[field.value] == TYPE_REF_GENERIC_PARAM)
                        break;
                    bool slice_field = field.value < hir_count &&
                        compact_hir_core[field.value].kind == HIR_TYPE &&
                        compact_hir_payload[field.value].a == HIR_TYPE_FORM_SLICE;
                    uint multiplier = slice_field ? NATIVE_SLICE_WORDS
                        : array_length(field.value, hir_count);
                    if (multiplier == INVALID) break;
                    uint element_type = array_element_type(field.value, hir_count);
                    if (!slice_field && element_type < hir_count &&
                        semantic_expr_ref_tag[element_type] == TYPE_REF_GENERIC_PARAM)
                        break;
                    // A slice owns a three-word descriptor, not an inline copy
                    // of its element type.
                    uint nested = slice_field ? INVALID : nested_struct(element_type, hir_count);
                    uint field_enum = nested == INVALID ? enum_field_declaration(field.value) : INVALID;
                    if (nested != INVALID)
                    {
                        child = nested;
                        child_entry = ENTRY_STRUCT_FIELD | field_row;
                    }
                    else if (field_enum != INVALID)
                    {
                        child = field_enum;
                        child_entry = ENTRY_ENUM_FIELD | field_row;
                    }
                    else
                    {
                        // A str field stores its pointer-and-length descriptor.
                        if (!slice_field && element_type < hir_count &&
                            semantic_expr_ref_tag[element_type] == TYPE_REF_SCALAR &&
                            semantic_expr_ref_payload[element_type] == 7u)
                        {
                            if (multiplier > (INVALID - 1u) / 2u) break;
                            multiplier *= 2u;
                        }
                        field_words = multiplier;
                    }
                }
                if (child == INVALID)
                {
                    uint total = layout_total[base + depth];
                    if (total >= INVALID - field_words) break;
                    if (depth == 0u)
                    {
                        semantic_struct_field_word_offset_by_row[field_row] = total;
                        semantic_struct_field_word_count_by_row[field_row] = field_words;
                    }
                    layout_total[base + depth] = total + field_words;
                    continue;
                }
            }
        }
        else if (frame == FRAME_ENUM)
        {
            if (next >= variant_total || compact_variants[next].owner != current)
            {
                finished = true;
            }
            else
            {
                uint variant = next++;
                uint start = compact_variant_payload_start[variant];
                uint count = compact_variant_payload_count[variant];
                if (count != 0u && (start >= payload_total || count > payload_total - start))
                    break;
                if (depth + 1u >= MAX_LAYOUT_DEPTH) break;
                depth += 1u;
                layout_entry[base + depth] = ENTRY_VARIANT | variant;
                layout_total[base + depth] = 1u; // discriminant
                frame = FRAME_VARIANT;
                current = variant;
                next = 0u;
                continue;
            }
        }
        else
        {
            uint count = compact_variant_payload_count[current];
            if (next >= count)
            {
                finished = true;
            }
            else
            {
                uint ordinal = next++;
                uint payload_row = compact_variant_payload_start[current] + ordinal;
                HirVariantPayload payload = compact_variant_payloads[payload_row];
                if (payload.variant != current || payload.ordinal != ordinal ||
                    payload.type_node >= hir_count)
                    break;
                // Generic payloads have no fixed by-value layout.
                if (symbolic_payload_layout(payload.type_node)) break;
                uint ref_tag = semantic_expr_ref_tag[payload.type_node];
                uint words = layout_total[base + depth];
                if (ref_tag == 3u)
                {
                    uint instance = semantic_expr_ref_payload[payload.type_node];
                    uint capacity; uint stride;
                    type_instance_kind.GetDimensions(capacity, stride);
                    uint payload_words = instance < capacity
                        ? type_instance_kind[instance] == 3u ? NATIVE_SLICE_WORDS : type_instance_native_words[instance]
                        : INVALID;
                    if (payload_words == INVALID || words >= INVALID - payload_words) break;
                    layout_total[base + depth] = words + payload_words;
                    continue;
                }
                if (ref_tag != TYPE_REF_SCALAR) break;
                uint type_id = semantic_expr_ref_payload[payload.type_node];
                if (type_id >= TY_STRUCT_BASE)
                {
                    child = nominal_declaration(payload.type_node, type_id, hir_count);
                    if (child >= hir_count) break;
                    child_entry = ENTRY_PAYLOAD | payload_row;
                }
                else
                {
                    uint payload_words = type_id == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
                    if (words > INVALID - payload_words) break;
                    layout_total[base + depth] = words + payload_words;
                    continue;
                }
            }
        }

        if (!finished)
        {
            // Enter `child`. A declaration already on the path reaches itself
            // by value.
            if (depth + 1u >= MAX_LAYOUT_DEPTH) break;
            bool cycle = frame != FRAME_VARIANT && child == current;
            for (uint ancestor = 1u; ancestor <= depth; ancestor += 1u)
                cycle = cycle || entry_parent_declaration(layout_entry[base + ancestor]) == child;
            if (cycle) break;
            depth += 1u;
            layout_entry[base + depth] = child_entry;
            bool child_struct = compact_hir_core[child].kind == HIR_STRUCT_ITEM;
            layout_total[base + depth] = child_struct ? 0u : 1u; // discriminant
            frame = child_struct ? FRAME_STRUCT : FRAME_ENUM;
            current = child;
            next = child_struct ? 0u : first_variant_row(child, variant_total);
            continue;
        }

        // The top frame is complete: fold its width into the frame below.
        uint completed = layout_total[base + depth];
        if (depth == 0u)
        {
            semantic_struct_word_count_by_hir[root] = completed;
            return;
        }
        uint entry = layout_entry[base + depth];
        uint entry_kind = entry & ENTRY_KIND_MASK;
        uint row = entry & ENTRY_ROW_MASK;
        depth -= 1u;
        uint total = layout_total[base + depth];
        if (entry_kind == ENTRY_VARIANT)
        {
            layout_total[base + depth] = max(total, completed);
            frame = FRAME_ENUM;
            current = compact_variants[row].owner;
            next = row + 1u;
            continue;
        }
        if (entry_kind == ENTRY_PAYLOAD)
        {
            if (total > INVALID - completed) break;
            layout_total[base + depth] = total + completed;
            HirVariantPayload payload = compact_variant_payloads[row];
            frame = FRAME_VARIANT;
            current = payload.variant;
            next = payload.ordinal + 1u;
            continue;
        }
        HirField field = compact_fields[row];
        if (entry_kind == ENTRY_STRUCT_FIELD)
        {
            uint multiplier = array_length(field.value, hir_count);
            if (multiplier != 0u && completed > (INVALID - 1u) / multiplier) break;
            completed *= multiplier;
        }
        if (total >= INVALID - completed) break;
        if (depth == 0u)
        {
            semantic_struct_field_word_offset_by_row[row] = total;
            semantic_struct_field_word_count_by_row[row] = completed;
        }
        layout_total[base + depth] = total + completed;
        frame = FRAME_STRUCT;
        current = field.owner;
        next = field.ordinal + 1u;
    }
    semantic_struct_word_count_by_hir[root] = INVALID;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 gtid: SV_GroupThreadID)
{
    layout_declaration(linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE),
        gtid.x * MAX_LAYOUT_DEPTH);
}
