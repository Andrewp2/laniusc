import primitive_types;
import semantic_interface_layout;
// Derive imported enum instance widths from canonical variant signatures
// and checked concrete arguments in the importing unit. Unknown layouts fail
// closed; this does not specialize a generic function body.
import dependency_interface;
import hir_records;
import type_checker.local_struct_layout;
import native_value_layout;

public interface IInstanceNativeWords { static uint words(uint instance); }

public uint dependency_concrete_enum_instance_words<TypeRefs : ILocalStructTypeRefs, Widths : IInstanceNativeWords>(
    uint parent, uint instance,
    StructuredBuffer<uint> roots, RWStructuredBuffer<uint> instance_kinds,
    RWStructuredBuffer<uint> arg_counts,
    StructuredBuffer<uint> row_starts,
    StructuredBuffer<uint> row_count,
    StructuredBuffer<uint> row_tags,
    StructuredBuffer<uint> row_payloads,
    RWStructuredBuffer<uint> legacy_starts,
    StructuredBuffer<uint> legacy_tags,
    StructuredBuffer<uint> legacy_payloads,
    uint hir_count, uint token_capacity, uint field_count,
    StructuredBuffer<HirCore> cores, StructuredBuffer<HirPayload> payloads,
    StructuredBuffer<HirField> fields, StructuredBuffer<uint> declaration_hir)
{
    if (parent >= dependency_declaration_count() ||
        dependency_declaration_word(parent * 14u + 6u) != 7u)
        return 0u;
    uint signature = dependency_declaration_word(parent * 14u + 7u);
    if (signature >= dependency_type_count()) return 0u;
    uint parent_root = roots[signature];
    uint start = dependency_declaration_word(parent * 14u + 8u);
    uint count = dependency_declaration_word(parent * 14u + 9u);
    if (start > dependency_member_count() || count > dependency_member_count() - start)
        return 0u;
    // The checked enum declaration retains a discriminant even with no variants.
    uint maximum = 1u;
    for (uint offset = 0u; offset < count; offset += 1u)
    {
        uint member = (start + offset) * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(member + 1u) != 5u) continue;
        uint variant_signature = dependency_member_word(member + 7u);
        if (variant_signature >= dependency_type_count()) return 0u;
        uint variant_root = roots[variant_signature];
        if (variant_root >= dependency_type_count() ||
            dependency_type_word(variant_root * 9u) != 7u)
            return 0u;
        uint edge_start = dependency_type_word(variant_root * 9u + 3u);
        uint edge_count = dependency_type_word(variant_root * 9u + 4u);
        if (edge_count == 0u || edge_start > dependency_count(5u) ||
            edge_count > dependency_count(5u) - edge_start)
            return 0u;
        uint result = dependency_type_edge_word(edge_start + edge_count - 1u);
        if (result >= dependency_type_count() || roots[result] != parent_root)
            return 0u;
        uint words = 1u;
        for (uint ordinal = 0u; ordinal + 1u < edge_count; ordinal += 1u)
        {
            uint child = dependency_type_edge_word(edge_start + ordinal);
            if (child >= dependency_type_count()) return 0u;
            uint root = roots[child];
            if (root >= dependency_type_count()) return 0u;
            uint kind = dependency_type_word(root * 9u);
            uint scalar = dependency_type_word(root * 9u + 1u);
            uint tag = 1u;
            if (kind == 2u)
            {
                uint slot = dependency_generic_type_slot(root);
                if (slot >= arg_counts[instance]) return 0u;
                uint row_start = row_starts[instance];
                uint total = row_count[0u];
                if (row_start < total && slot < total - row_start)
                {
                    tag = row_tags[row_start + slot];
                    scalar = row_payloads[row_start + slot];
                }
                else
                {
                    if (slot >= 4u || legacy_starts[instance] == 0xffffffffu) return 0u;
                    uint row = legacy_starts[instance] + slot;
                    tag = legacy_tags[row];
                    scalar = legacy_payloads[row];
                }
            }
            else if (kind != 1u) return 0u;
            uint width = 0u;
            if (tag == 3u && scalar < token_capacity &&
                instance_kinds[scalar] == 3u)
                width = NATIVE_SLICE_WORDS; // Borrowed descriptor, independent of element count.
            else if (tag == 3u && scalar < token_capacity)
                width = Widths.words(scalar);
            else if (tag != 1u)
                return 0u;
            else if (scalar_is_known(scalar))
                width = scalar == 7u ? 2u : 1u;
            else if (kind == 2u)
            {
                // A substituted local nominal argument is checked in this
                // unit. A dependency scalar code is never interpreted locally.
                uint local = local_struct_for_scalar(scalar, hir_count,
                    token_capacity, declaration_hir, cores);
                if (local < hir_count)
                    width = fixed_local_struct_words<TypeRefs>(local, hir_count,
                        token_capacity, field_count, cores, payloads, fields,
                        declaration_hir);
            }
            if (width == 0u || width == 0xffffffffu) return 0u;
            if (words > 0xffffffffu - width) return 0u;
            words += width;
        }
        maximum = max(maximum, words);
    }
    return maximum;
}
