/// Array literal record passes.
pub mod array_pass_params;
/// Scatters compact list rank records.
pub mod compact_list_rows;
/// Links array element rows to their parent array literals.
pub mod link_array_elements;
/// Call argument ownership-link pass.
pub mod link_call_args;
/// Links type argument rows to their owning type node.
pub mod link_type_args;
pub mod mark_canonical_array_elements;
pub mod mark_canonical_call_args;
pub mod mark_canonical_type_args;
/// Computes local list rank prefixes.
pub mod mark_list_rows;
/// Scatters ranked array element rows into compact storage.
pub mod publish_array_elements;
/// Scatters ranked call arguments into call-local ranges.
pub mod publish_call_arg_ordinals;
/// Scatters ranked type argument rows into compact storage.
pub mod publish_type_args;
/// Propagates compact list owners and additive ranks.
pub mod rank_list_rows;
pub mod scatter_canonical_array_elements;
pub mod scatter_canonical_call_args;
pub mod scatter_canonical_type_args;

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

    pub const fn scan_label(self) -> &'static str {
        match self {
            Self::TypeArguments => "hir_type_arg_rank_prefix_01_blocks",
            Self::Parameters => "hir_param_rank_prefix_01_blocks",
            Self::CallArguments => "hir_call_arg_rank_prefix_01_blocks",
            Self::ArrayElements => "hir_array_element_rank_prefix_01_blocks",
            Self::StringRecords => "hir_string_compact_prefix_01_blocks",
            Self::StringOffsets => "hir_string_offset_prefix_01_blocks",
            Self::PathSegments => "hir_path_segment_rank_prefix_01_blocks",
            Self::TypeRoots => "hir_type_root_rank_prefix_01_blocks",
            Self::VariantPayloadOwners => "hir_variant_payload_owner_rank_prefix_01_blocks",
            Self::BinarySpans => "hir_binary_span_rank_prefix_01_blocks",
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
