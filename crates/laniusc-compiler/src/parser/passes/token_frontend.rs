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
    pub token_delimiters_02_scan_up: PassData,
    pub token_delimiters_02_scan_down: PassData,
    pub token_statement_event_scan_up: PassData,
    pub token_statement_event_scan_down: PassData,
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
    pub tokens_bracket_match_03_pair_pse: PassData,
    pub tokens_brace_match_03_pair_pse: PassData,
    pub tokens_to_kinds: PassData,
    pub tokens_type_path_context_01_local: PassData,
    pub tokens_type_path_context_02_apply: PassData,
    pub tokens_to_identifier_kinds: PassData,
    pub tokens_generic_shr_00_raw_local: PassData,
    pub tokens_generic_shr_00_raw_apply: PassData,
    pub tokens_generic_shr_01_local: PassData,
    pub tokens_generic_shr_02_scan_up: PassData,
    pub tokens_generic_shr_02_scan_down: PassData,
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
                "parser/tokens/delimiters/01_local"
            ),
            token_delimiters_02_scan_up: pass!(
                "parser_tokens_delimiters_02_scan_up",
                "parser/tokens/delimiters/02_scan_up"
            ),
            token_delimiters_02_scan_down: pass!(
                "parser_tokens_delimiters_02_scan_down",
                "parser/tokens/delimiters/02_scan_down"
            ),
            token_statement_event_scan_up: pass!(
                "parser_tokens_context_scan_up",
                "parser/tokens/context/scan_up"
            ),
            token_statement_event_scan_down: pass!(
                "parser_tokens_context_scan_down",
                "parser/tokens/context/scan_down"
            ),
            token_delimiters_03_owner_local: pass!(
                "parser_tokens_delimiters_03_owner_local",
                "parser/tokens/delimiters/03_owner_local"
            ),
            token_delimiters_04_owner_apply: pass!(
                "parser_tokens_delimiters_04_owner_apply",
                "parser/tokens/delimiters/04_owner_apply"
            ),
            tokens_brace_context: pass!(
                "parser_tokens_brace_context",
                "parser/tokens/brace/context"
            ),
            tokens_statement_phase_01_local: pass!(
                "parser_tokens_statement_phase_01_local",
                "parser/tokens/statement/phase/01_local"
            ),
            tokens_statement_phase_02_apply: pass!(
                "parser_tokens_statement_phase_02_apply",
                "parser/tokens/statement/phase/02_apply"
            ),
            tokens_impl_header_01_local: pass!(
                "parser_tokens_impl_header_01_local",
                "parser/tokens/impl/header/01_local"
            ),
            tokens_impl_header_02_apply: pass!(
                "parser_tokens_impl_header_02_apply",
                "parser/tokens/impl/header/02_apply"
            ),
            tokens_where_clause_01_local: pass!(
                "parser_tokens_where_clause_01_local",
                "parser/tokens/where/clause/01_local"
            ),
            tokens_where_clause_02_apply: pass!(
                "parser_tokens_where_clause_02_apply",
                "parser/tokens/where/clause/02_apply"
            ),
            tokens_match_pattern_01_local: pass!(
                "parser_tokens_match_pattern_01_local",
                "parser/tokens/match/pattern/01_local"
            ),
            tokens_match_pattern_02_apply: pass!(
                "parser_tokens_match_pattern_02_apply",
                "parser/tokens/match/pattern/02_apply"
            ),
            tokens_delimiter_match_01_depth_blocks: pass!(
                "parser_tokens_delimiter_match_01_depth_blocks",
                "parser/tokens/delimiter_match/01_depth_blocks"
            ),
            tokens_delimiter_match_02_build_min_tree: pass!(
                "parser_tokens_delimiter_match_02_build_min_tree",
                "parser/tokens/delimiter_match/02_build_min_tree"
            ),
            tokens_bracket_match_03_pair_pse: pass!(
                "parser_tokens_bracket_match_03_pair_pse",
                "parser/tokens/bracket/match/03_pair_pse"
            ),
            tokens_brace_match_03_pair_pse: pass!(
                "parser_tokens_brace_match_03_pair_pse",
                "parser/tokens/brace/match/03_pair_pse"
            ),
            tokens_to_kinds: pass!("parser_tokens_to_kinds", "parser/tokens/to/kinds"),
            tokens_type_path_context_01_local: pass!(
                "parser_tokens_type_path_context_01_local",
                "parser/tokens/type/path/context/01_local"
            ),
            tokens_type_path_context_02_apply: pass!(
                "parser_tokens_type_path_context_02_apply",
                "parser/tokens/type/path/context/02_apply"
            ),
            tokens_to_identifier_kinds: pass!(
                "parser_tokens_to_identifier_kinds",
                "parser/tokens/to/identifier_kinds"
            ),
            tokens_generic_shr_00_raw_local: pass!(
                "parser_tokens_generic_shr_00_raw_local",
                "parser/tokens/generic/shr/00_raw_local"
            ),
            tokens_generic_shr_00_raw_apply: pass!(
                "parser_tokens_generic_shr_00_raw_apply",
                "parser/tokens/generic/shr/00_raw_apply"
            ),
            tokens_generic_shr_01_local: pass!(
                "parser_tokens_generic_shr_01_local",
                "parser/tokens/generic/shr/01_local"
            ),
            tokens_generic_shr_02_scan_up: pass!(
                "parser_tokens_generic_shr_02_scan_up",
                "parser/tokens/generic/shr/02_scan_up"
            ),
            tokens_generic_shr_02_scan_down: pass!(
                "parser_tokens_generic_shr_02_scan_down",
                "parser/tokens/generic/shr/02_scan_down"
            ),
            tokens_generic_shr_03_apply: pass!(
                "parser_tokens_generic_shr_03_apply",
                "parser/tokens/generic/shr/03_apply"
            ),
            tokens_generic_shr_04_close_kinds: pass!(
                "parser_tokens_generic_shr_04_close_kinds",
                "parser/tokens/generic/shr/04_close_kinds"
            ),
        })
    }
}
