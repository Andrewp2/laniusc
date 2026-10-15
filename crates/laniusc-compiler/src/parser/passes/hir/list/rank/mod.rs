/// Scatters compact list rank records.
pub mod compact_scatter;
/// Computes local list rank prefixes.
pub mod prefix_local;
/// Propagates compact list owners and additive ranks.
pub mod step;

/// Semantic use of the reusable list-rank kernels.
///
/// One pipeline serves several HIR lists, but each use remains a distinct
/// compiler-graph operation because it has different inputs, outputs, and
/// position in the frontend schedule.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ListRankInvocation {
    TypeArguments,
    Parameters,
    CallArguments,
    ArrayElements,
    StringRecords,
    StringOffsets,
    PathSegments,
    TypeRoots,
    VariantPayloadOwners,
    BinarySpans,
}

impl ListRankInvocation {
    pub const fn local_label(self) -> &'static str {
        match self {
            Self::TypeArguments => "hir_type_arg_rank_prefix_00_local",
            Self::Parameters => "hir_param_rank_prefix_00_local",
            Self::CallArguments => "hir_call_arg_rank_prefix_00_local",
            Self::ArrayElements => "hir_array_element_rank_prefix_00_local",
            Self::StringRecords => "hir_string_compact_local",
            Self::StringOffsets => "hir_string_offset_local",
            Self::PathSegments => "hir_path_segment_rank_prefix_00_local",
            Self::TypeRoots => "hir_type_root_rank_prefix_00_local",
            Self::VariantPayloadOwners => "hir_variant_payload_owner_rank_prefix_00_local",
            Self::BinarySpans => "hir_binary_span_rank_prefix_00_local",
        }
    }

    pub const fn scan_labels(self) -> (&'static str, &'static str) {
        match self {
            Self::TypeArguments => (
                "hir_type_arg_rank_prefix_01_blocks.up",
                "hir_type_arg_rank_prefix_01_blocks.down",
            ),
            Self::Parameters => (
                "hir_param_rank_prefix_01_blocks.up",
                "hir_param_rank_prefix_01_blocks.down",
            ),
            Self::CallArguments => (
                "hir_call_arg_rank_prefix_01_blocks.up",
                "hir_call_arg_rank_prefix_01_blocks.down",
            ),
            Self::ArrayElements => (
                "hir_array_element_rank_prefix_01_blocks.up",
                "hir_array_element_rank_prefix_01_blocks.down",
            ),
            Self::StringRecords => (
                "hir_string_compact_prefix_01_blocks.up",
                "hir_string_compact_prefix_01_blocks.down",
            ),
            Self::StringOffsets => (
                "hir_string_offset_prefix_01_blocks.up",
                "hir_string_offset_prefix_01_blocks.down",
            ),
            Self::PathSegments => (
                "hir_path_segment_rank_prefix_01_blocks.up",
                "hir_path_segment_rank_prefix_01_blocks.down",
            ),
            Self::TypeRoots => (
                "hir_type_root_rank_prefix_01_blocks.up",
                "hir_type_root_rank_prefix_01_blocks.down",
            ),
            Self::VariantPayloadOwners => (
                "hir_variant_payload_owner_rank_prefix_01_blocks.up",
                "hir_variant_payload_owner_rank_prefix_01_blocks.down",
            ),
            Self::BinarySpans => (
                "hir_binary_span_rank_prefix_01_blocks.up",
                "hir_binary_span_rank_prefix_01_blocks.down",
            ),
        }
    }

    pub const fn scatter_label(self) -> &'static str {
        match self {
            Self::TypeArguments => "hir_type_arg_rank_compact_scatter",
            Self::Parameters => "hir_param_rank_compact_scatter",
            Self::CallArguments => "hir_call_arg_rank_compact_scatter",
            Self::ArrayElements => "hir_array_element_rank_compact_scatter",
            Self::StringRecords => "hir_string_compact_scatter",
            Self::StringOffsets => "hir_string_offset_scatter",
            Self::PathSegments => "hir_path_segment_rank_compact_scatter",
            Self::TypeRoots => "hir_type_root_rank_compact_scatter",
            Self::VariantPayloadOwners => "hir_variant_payload_owner_rank_compact_scatter",
            Self::BinarySpans => "hir_binary_span_rank_compact_scatter",
        }
    }

    pub const fn step_labels(self) -> (&'static str, &'static str) {
        match self {
            Self::TypeArguments => (
                "hir_type_arg_rank_step.a_to_b",
                "hir_type_arg_rank_step.b_to_a",
            ),
            Self::Parameters => ("hir_param_rank_step.a_to_b", "hir_param_rank_step.b_to_a"),
            Self::CallArguments => (
                "hir_call_arg_ordinal_step.a_to_b",
                "hir_call_arg_ordinal_step.b_to_a",
            ),
            Self::ArrayElements => (
                "hir_array_element_rank_step.a_to_b",
                "hir_array_element_rank_step.b_to_a",
            ),
            Self::PathSegments => (
                "hir_path_segment_step.a_to_b",
                "hir_path_segment_step.b_to_a",
            ),
            Self::TypeRoots => (
                "hir_type_root_owner_step.a_to_b",
                "hir_type_root_owner_step.b_to_a",
            ),
            Self::VariantPayloadOwners => (
                "hir_canonical_variant_payload_owner_step.a_to_b",
                "hir_canonical_variant_payload_owner_step.b_to_a",
            ),
            Self::BinarySpans => (
                "hir_binary_span_step.a_to_b",
                "hir_binary_span_step.b_to_a",
            ),
            Self::StringRecords | Self::StringOffsets => {
                ("hir_list_rank_step.a_to_b", "hir_list_rank_step.b_to_a")
            }
        }
    }
}
