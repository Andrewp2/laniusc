use super::*;
use crate::parser::tables::{Ll1RejectionContext, PrecomputedParseTables};

/// Debug readback for delimiter-pair validation.
pub struct BracketsMatchResult {
    pub valid: bool,
    pub final_depth: i32,
    pub min_depth: i32,
    pub match_for_index: Vec<u32>,
}

#[derive(Clone, Debug)]
/// Six-word LL/parser status decoded into host fields.
pub struct Ll1AcceptResult {
    pub accepted: bool,
    pub error_pos: u32,
    pub error_code: u32,
    pub detail: u32,
    pub steps: u32,
    pub emit_len: u32,
}

impl Ll1AcceptResult {
    /// Decodes the six-word parser status buffer used by GPU parser passes.
    pub(crate) fn from_status_words(words: &[u32]) -> Self {
        Self {
            accepted: words[0] != 0,
            error_pos: words[1],
            error_code: words[2],
            detail: words[3],
            steps: words[4],
            emit_len: words[5],
        }
    }

    /// Formats a parser rejection without exposing internal GPU pass names.
    pub fn rejection_message(&self) -> String {
        if self.accepted {
            return "parse accepted".to_string();
        }

        match self.error_code {
            3 => format!(
                "parse error: this input is too large for the current parser buffers \
                 (needed {} output entries, capacity {})",
                self.detail, self.emit_len
            ),
            4 => "parse error: input is incomplete or contains mismatched syntax".to_string(),
            _ => "parse error: could not match the grammar".to_string(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
/// Parser rejection class owned by the parser boundary.
pub enum ParserFailureKind {
    /// The LL(1) acceptance pass rejected the token-kind stream.
    Ll1Rejected,
}

#[derive(Clone, Debug)]
/// Structured parser failure payload consumed by compiler diagnostics.
pub struct ParserFailure {
    pub kind: ParserFailureKind,
    ll1: Ll1AcceptResult,
    semantic_token_kinds: Option<Vec<u32>>,
    ll1_rejection: Option<Ll1RejectionContext>,
}

impl ParserFailure {
    /// Builds a parser failure from a rejected LL(1) status and optional token-kind readback.
    pub fn from_ll1_rejection(
        ll1: Ll1AcceptResult,
        parse_tables: &PrecomputedParseTables,
        semantic_token_kinds: Option<Vec<u32>>,
    ) -> Self {
        debug_assert!(
            !ll1.accepted,
            "accepted LL(1) status should not be reported as a parser failure"
        );
        let ll1_rejection = semantic_token_kinds
            .as_deref()
            .and_then(|kinds| parse_tables.diagnose_ll1_rejection(kinds));
        Self {
            kind: ParserFailureKind::Ll1Rejected,
            ll1,
            semantic_token_kinds,
            ll1_rejection,
        }
    }

    /// Raw LL(1) status. This remains useful for low-level fallback positioning.
    pub fn ll1(&self) -> &Ll1AcceptResult {
        &self.ll1
    }

    /// Current parser token-kind stream, when diagnostic readback succeeded.
    pub fn semantic_token_kinds(&self) -> Option<&[u32]> {
        self.semantic_token_kinds.as_deref()
    }

    /// Table-derived expected/found context, when available.
    pub fn ll1_rejection(&self) -> Option<&Ll1RejectionContext> {
        self.ll1_rejection.as_ref()
    }
}

#[cfg(test)]
mod tests {
    use super::{Ll1AcceptResult, ParserFailure};
    use crate::parser::tables::{INVALID_TABLE_ENTRY, Ll1ParseErrorCode, PrecomputedParseTables};

    fn tiny_ident_semicolon_table() -> PrecomputedParseTables {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![INVALID_TABLE_ENTRY; 4];
        tables.ll1_predict[1] = 0;
        tables.prod_rhs_off = vec![0];
        tables.prod_rhs_len = vec![2];
        tables.prod_rhs = vec![1, 3];
        tables
    }

    #[test]
    fn parser_rejection_message_hides_gpu_ll1_details() {
        let result = Ll1AcceptResult {
            accepted: false,
            error_pos: 7,
            error_code: 2,
            detail: 19,
            steps: 11,
            emit_len: 0,
        };

        let message = result.rejection_message();
        assert_eq!(message, "parse error: could not match the grammar");
        assert!(!message.contains("near token"));
        assert!(!message.contains("status token"));
        assert!(!message.contains("GPU LL(1)"));
    }

    #[test]
    fn parser_rejection_message_decodes_stack_effect_depth() {
        let result = Ll1AcceptResult {
            accepted: false,
            error_pos: 0,
            error_code: 4,
            detail: (-2i32) as u32,
            steps: 14,
            emit_len: 0,
        };

        let message = result.rejection_message();
        assert_eq!(
            message,
            "parse error: input is incomplete or contains mismatched syntax"
        );
        assert!(!message.contains("depth"));
        assert!(!message.contains("GPU LL(1)"));
    }

    #[test]
    fn parser_status_words_decode_to_accept_result() {
        let result = Ll1AcceptResult::from_status_words(&[0, 3, 4, 5, 6, 7]);

        assert!(!result.accepted);
        assert_eq!(result.error_pos, 3);
        assert_eq!(result.error_code, 4);
        assert_eq!(result.detail, 5);
        assert_eq!(result.steps, 6);
        assert_eq!(result.emit_len, 7);
    }

    #[test]
    fn parser_failure_captures_table_rejection_context() {
        let failure = ParserFailure::from_ll1_rejection(
            Ll1AcceptResult {
                accepted: false,
                error_pos: 2,
                error_code: 2,
                detail: 0,
                steps: 3,
                emit_len: 0,
            },
            &tiny_ident_semicolon_table(),
            Some(vec![0, 1, 2, 0]),
        );

        let rejection = failure
            .ll1_rejection()
            .expect("table replay should explain the rejected token");
        assert_eq!(rejection.pos, 2);
        assert_eq!(rejection.code, Ll1ParseErrorCode::TerminalMismatch);
        assert_eq!(rejection.found, 2);
        assert_eq!(rejection.expected, vec![3]);
        assert_eq!(failure.semantic_token_kinds(), Some(&[0, 1, 2, 0][..]));
        assert_eq!(failure.ll1().error_pos, 2);
    }
}

/// Full one-shot parser debug readback result.
pub struct ParseResult {
    pub ll1: Ll1AcceptResult,
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub brackets: BracketsMatchResult,

    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_semantic_prefix_before_node: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_subtree_end: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_type_path_leaf_node: Vec<u32>,
    pub hir_type_arg_start: Vec<u32>,
    pub hir_type_arg_count: Vec<u32>,
    pub hir_type_arg_next: Vec<u32>,
    pub hir_type_alias_target_node: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_stmt_record_kind: Vec<u32>,
    pub hir_stmt_record_operand0: Vec<u32>,
    pub hir_stmt_record_operand1: Vec<u32>,
    pub hir_stmt_record_operand2: Vec<u32>,
    pub hir_stmt_scope_end: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_path_node: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_variant_payload_node: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_next: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_match_payload_owner_arm: Vec<u32>,
    pub hir_match_payload_match_node: Vec<u32>,
    pub hir_match_payload_ordinal: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_expr_string_start: Vec<u32>,
    pub hir_expr_string_len: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
    pub hir_struct_lit_field_next: Vec<u32>,

    pub debug: DebugOutput,
}

#[derive(Clone, Debug)]
/// Resident parser debug readback result from compiler-owned token buffers.
pub struct ResidentParseResult {
    pub ll1: Ll1AcceptResult,
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_semantic_prefix_before_node: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_subtree_end: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_node_file_id: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_type_path_leaf_node: Vec<u32>,
    pub hir_type_arg_start: Vec<u32>,
    pub hir_type_arg_count: Vec<u32>,
    pub hir_type_arg_next: Vec<u32>,
    pub hir_type_alias_target_node: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_stmt_record_kind: Vec<u32>,
    pub hir_stmt_record_operand0: Vec<u32>,
    pub hir_stmt_record_operand1: Vec<u32>,
    pub hir_stmt_record_operand2: Vec<u32>,
    pub hir_stmt_scope_end: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_path_node: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_variant_payload_node: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_next: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_match_payload_owner_arm: Vec<u32>,
    pub hir_match_payload_match_node: Vec<u32>,
    pub hir_match_payload_ordinal: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_callee_path_node: Vec<u32>,
    pub hir_call_parent_by_callee: Vec<u32>,
    pub hir_call_context_stmt_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_lit_context_stmt_node: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_expr_name_role: Vec<u32>,
    pub hir_expr_result_root_node: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_nearest_stmt_node: Vec<u32>,
    pub hir_nearest_block_node: Vec<u32>,
    pub hir_nearest_enclosing_control_node: Vec<u32>,
    pub hir_nearest_loop_node: Vec<u32>,
    pub hir_nearest_fn_node: Vec<u32>,
    pub hir_nearest_array_element_node: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_context_stmt_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
    pub hir_struct_lit_field_next: Vec<u32>,
}

/// Recorded parser status readback for deferred LL/HIR validation.
pub struct RecordedResidentLl1HirCheck {
    pub(super) status_readback: wgpu::Buffer,
}

/// Parser status map queued while the host records independent downstream work.
pub(crate) struct PendingResidentLl1HirStatus {
    status_readback: wgpu::Buffer,
    map: crate::gpu::passes_core::PendingReadbackMap,
}

impl RecordedResidentLl1HirCheck {
    /// Reads the recorded parser status buffer into a host status result.
    pub(crate) fn read_status_result(
        &self,
        device: &wgpu::Device,
    ) -> anyhow::Result<Ll1AcceptResult> {
        self.read_status_feature_flags_and_pointer_jump_steps_result(device)
            .map(|(status, _feature_flags, _pointer_jump_steps)| status)
    }

    /// Reads parser status, feature mask, and the depth-bounded round count.
    pub(crate) fn read_status_feature_flags_and_pointer_jump_steps_result(
        &self,
        device: &wgpu::Device,
    ) -> anyhow::Result<(Ll1AcceptResult, u32, u32)> {
        self.begin_status_and_feature_flags_read().finish(device)
    }

    /// Queues parser status mapping without waiting for GPU completion.
    pub(crate) fn begin_status_and_feature_flags_read(&self) -> PendingResidentLl1HirStatus {
        let slice = self.status_readback.slice(..);
        let map =
            crate::gpu::passes_core::begin_readback_map(&slice, "parser.recorded-ll1-hir.status");
        PendingResidentLl1HirStatus {
            status_readback: self.status_readback.clone(),
            map,
        }
    }
}

impl PendingResidentLl1HirStatus {
    /// Waits for the queued map and decodes status plus GPU scheduling metadata.
    pub(crate) fn finish(
        self,
        device: &wgpu::Device,
    ) -> anyhow::Result<(Ll1AcceptResult, u32, u32)> {
        crate::gpu::passes_core::finish_readback_map_blocking(device, self.map)?;
        let mapped = self.status_readback.slice(..).get_mapped_range();
        let words =
            crate::gpu::readback::read_u32_words::<8>(&mapped, "parser.recorded-ll1-hir.status")?;
        drop(mapped);
        self.status_readback.unmap();

        Ok((
            Ll1AcceptResult::from_status_words(&words[..6]),
            words[6],
            words[7],
        ))
    }
}

/// Recorded semantic-HIR count readback used by backend capacity planning.
pub struct RecordedHirSemanticCount {
    pub(super) block_count_readback: wgpu::Buffer,
    pub(super) block_count_words: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
/// Exact parser allocation inputs measured by GPU token classification and
/// partial-parse emission before full tree/HIR allocation.
pub struct ResidentParserCapacity {
    pub tree_capacity: u32,
    pub parser_feature_flags: u32,
}

/// Cached resident parser buffers keyed by capacity, tables, and debug mode.
pub(super) struct ResidentParserBufferCache {
    pub(super) token_capacity: u32,
    pub(super) table_fingerprint: u64,
    pub(super) retain_debug_hir_buffers: bool,
    pub(super) parser_feature_flags: u32,
    pub(super) buffers: ParserBuffers,
}
