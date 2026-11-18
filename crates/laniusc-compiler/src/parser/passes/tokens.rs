//! Pipelines that refine lexer tokens into parser token facts.

use anyhow::Result;

use crate::gpu::passes_core::PassData;

/// Device-static pipelines for the token-facing parser frontend.
///
/// Keeping this as one operation bundle gives the compiler graph one owner for
/// the complete token schedule instead of scattering its pipelines across the
/// parser driver.
pub(in crate::parser) struct TokenFrontendPasses {
    pub token_delimiters_01: PassData,
    pub token_delimiters_02_scan: PassData,
    pub token_statement_event_scan: PassData,
    pub token_delimiters_03_owner_local: PassData,
    pub token_delimiters_04_owner_apply: PassData,
    pub tokens_brace_context: PassData,
    pub tokens_statement_phase_01_local: PassData,
    pub tokens_statement_phase_02_apply: PassData,
    pub tokens_impl_header_01_local: PassData,
    pub tokens_impl_header_02_apply: PassData,
    pub tokens_where_clause_01_local: PassData,
    pub tokens_where_clause_02_apply: PassData,
    pub tokens_match_pattern_01_local: PassData,
    pub tokens_match_pattern_02_apply: PassData,
    pub tokens_delimiter_match_01_depth_blocks: PassData,
    pub tokens_delimiter_match_02_build_min_tree: PassData,
    pub tokens_bracket_01_kinds: PassData,
    pub tokens_bracket_match_03_pair_pse: PassData,
    pub tokens_brace_match_03_pair_pse: PassData,
    pub tokens_delimiter_match_03_enclosing_opens: PassData,
    pub tokens_to_angle_kinds: PassData,
    pub tokens_to_kinds: PassData,
    pub tokens_type_path_context_01_local: PassData,
    pub tokens_type_path_context_02_apply: PassData,
    pub tokens_to_identifier_kinds: PassData,
    pub tokens_generic_shr_00_raw_local: PassData,
    pub tokens_generic_shr_00_raw_apply: PassData,
    pub tokens_generic_shr_01_local: PassData,
    pub tokens_generic_shr_02_scan: PassData,
    pub tokens_generic_shr_03_apply: PassData,
    pub tokens_generic_shr_04_close_kinds: PassData,
}

impl TokenFrontendPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        macro_rules! pass {
            ($label:literal, $shader:literal) => {
                crate::gpu::passes_core::make_main_pass!(
                    device,
                    $label,
                    shader: $shader
                )?
            };
        }
        Ok(Self {
            token_delimiters_01: pass!(
                "parser_tokens_delimiters_01_local",
                "parser/tokens/delimiters/scan_delimiter_depths_in_blocks"
            ),
            token_delimiters_02_scan: pass!(
                "parser_tokens_delimiters_02_scan",
                "parser/tokens/delimiters/scan_delimiter_depth_blocks"
            ),
            token_statement_event_scan: pass!(
                "parser_tokens_context_scan",
                "parser/tokens/contexts/scan_token_context_blocks"
            ),
            token_delimiters_03_owner_local: pass!(
                "parser_tokens_delimiters_03_owner_local",
                "parser/tokens/delimiters/summarize_brace_owner_headers"
            ),
            token_delimiters_04_owner_apply: pass!(
                "parser_tokens_delimiters_04_owner_apply",
                "parser/tokens/delimiters/apply_brace_owner_headers"
            ),
            tokens_brace_context: pass!(
                "parser_tokens_brace_context",
                "parser/tokens/contexts/classify_top_level_braces"
            ),
            tokens_statement_phase_01_local: pass!(
                "parser_tokens_statement_phase_01_local",
                "parser/tokens/contexts/summarize_statement_phases"
            ),
            tokens_statement_phase_02_apply: pass!(
                "parser_tokens_statement_phase_02_apply",
                "parser/tokens/contexts/apply_statement_phases"
            ),
            tokens_impl_header_01_local: pass!(
                "parser_tokens_impl_header_01_local",
                "parser/tokens/contexts/summarize_impl_headers"
            ),
            tokens_impl_header_02_apply: pass!(
                "parser_tokens_impl_header_02_apply",
                "parser/tokens/contexts/apply_impl_headers"
            ),
            tokens_where_clause_01_local: pass!(
                "parser_tokens_where_clause_01_local",
                "parser/tokens/contexts/summarize_where_clauses"
            ),
            tokens_where_clause_02_apply: pass!(
                "parser_tokens_where_clause_02_apply",
                "parser/tokens/contexts/apply_where_clauses"
            ),
            tokens_match_pattern_01_local: pass!(
                "parser_tokens_match_pattern_01_local",
                "parser/tokens/contexts/summarize_match_patterns"
            ),
            tokens_match_pattern_02_apply: pass!(
                "parser_tokens_match_pattern_02_apply",
                "parser/tokens/contexts/apply_match_patterns"
            ),
            tokens_delimiter_match_01_depth_blocks: pass!(
                "parser_tokens_delimiter_match_01_depth_blocks",
                "parser/tokens/delimiters/build_delimiter_match_heaps"
            ),
            tokens_delimiter_match_02_build_min_tree: pass!(
                "parser_tokens_delimiter_match_02_build_min_tree",
                "parser/tokens/delimiters/build_delimiter_min_trees"
            ),
            tokens_bracket_01_kinds: pass!(
                "parser_tokens_bracket_01_kinds",
                "parser/tokens/kinds/classify_bracket_roles"
            ),
            tokens_bracket_match_03_pair_pse: pass!(
                "parser_tokens_bracket_match_03_pair_pse",
                "parser/tokens/kinds/classify_square_brackets"
            ),
            tokens_brace_match_03_pair_pse: pass!(
                "parser_tokens_brace_match_03_pair_pse",
                "parser/tokens/kinds/classify_closing_braces"
            ),
            tokens_delimiter_match_03_enclosing_opens: pass!(
                "parser_tokens_delimiter_match_03_enclosing_opens",
                "parser/tokens/delimiters/find_enclosing_delimiters"
            ),
            tokens_to_angle_kinds: pass!(
                "parser_tokens_to_angle_kinds",
                "parser/tokens/kinds/classify_angle_openers"
            ),
            tokens_to_kinds: pass!(
                "parser_tokens_to_kinds",
                "parser/tokens/kinds/retag_token_kinds"
            ),
            tokens_type_path_context_01_local: pass!(
                "parser_tokens_type_path_context_01_local",
                "parser/tokens/contexts/summarize_type_path_contexts"
            ),
            tokens_type_path_context_02_apply: pass!(
                "parser_tokens_type_path_context_02_apply",
                "parser/tokens/contexts/apply_type_path_contexts"
            ),
            tokens_to_identifier_kinds: pass!(
                "parser_tokens_to_identifier_kinds",
                "parser/tokens/kinds/retag_identifier_kinds"
            ),
            tokens_generic_shr_00_raw_local: pass!(
                "parser_tokens_generic_shr_00_raw_local",
                "parser/tokens/delimiters/scan_raw_angle_depths_in_blocks"
            ),
            tokens_generic_shr_00_raw_apply: pass!(
                "parser_tokens_generic_shr_00_raw_apply",
                "parser/tokens/delimiters/apply_raw_angle_depths"
            ),
            tokens_generic_shr_01_local: pass!(
                "parser_tokens_generic_shr_01_local",
                "parser/tokens/kinds/summarize_generic_angle_effects"
            ),
            tokens_generic_shr_02_scan: pass!(
                "parser_tokens_generic_shr_02_scan",
                "parser/tokens/kinds/scan_generic_angle_effect_blocks"
            ),
            tokens_generic_shr_03_apply: pass!(
                "parser_tokens_generic_shr_03_apply",
                "parser/tokens/kinds/mark_generic_shift_splits"
            ),
            tokens_generic_shr_04_close_kinds: pass!(
                "parser_tokens_generic_shr_04_close_kinds",
                "parser/tokens/kinds/classify_split_shift_closers"
            ),
        })
    }
}
