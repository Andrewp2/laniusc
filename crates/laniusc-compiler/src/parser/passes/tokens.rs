//! Pipelines that refine lexer tokens into parser token facts.

use anyhow::Result;

use crate::gpu::passes_core::PassData;

/// Device-static pipelines for the token-facing parser frontend.
///
/// Keeping this as one operation bundle gives the compiler graph one owner for
/// the complete token schedule instead of scattering its pipelines across the
/// parser driver.
pub(in crate::parser) struct TokenFrontendPasses {
    pub scan_delimiter_depths_in_blocks: PassData,
    pub scan_delimiter_depth_blocks: PassData,
    pub token_statement_event_scan: PassData,
    pub summarize_brace_owner_headers: PassData,
    pub apply_brace_owner_headers: PassData,
    pub tokens_brace_context: PassData,
    pub summarize_statement_phases: PassData,
    pub apply_statement_phases: PassData,
    pub summarize_impl_headers: PassData,
    pub apply_impl_headers: PassData,
    pub summarize_where_clauses: PassData,
    pub apply_where_clauses: PassData,
    pub summarize_match_patterns: PassData,
    pub apply_match_patterns: PassData,
    pub build_delimiter_match_heaps: PassData,
    pub build_delimiter_min_trees: PassData,
    pub classify_bracket_roles: PassData,
    pub classify_square_brackets: PassData,
    pub classify_closing_braces: PassData,
    pub find_enclosing_delimiters: PassData,
    pub tokens_to_angle_kinds: PassData,
    pub tokens_to_kinds: PassData,
    pub summarize_type_path_contexts: PassData,
    pub apply_type_path_contexts: PassData,
    pub tokens_to_identifier_kinds: PassData,
    pub scan_raw_angle_depths_in_blocks: PassData,
    pub apply_raw_angle_depths: PassData,
    pub summarize_generic_angle_effects: PassData,
    pub scan_generic_angle_effect_blocks: PassData,
    pub mark_generic_shift_splits: PassData,
    pub classify_split_shift_closers: PassData,
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
            scan_delimiter_depths_in_blocks: pass!(
                "parser.tokens.scan_delimiter_depths_in_blocks",
                "parser/tokens/delimiters/scan_delimiter_depths_in_blocks"
            ),
            scan_delimiter_depth_blocks: pass!(
                "parser.tokens.scan_delimiter_depth_blocks",
                "parser/tokens/delimiters/scan_delimiter_depth_blocks"
            ),
            token_statement_event_scan: pass!(
                "parser_tokens_context_scan",
                "parser/tokens/contexts/scan_token_context_blocks"
            ),
            summarize_brace_owner_headers: pass!(
                "parser.tokens.summarize_brace_owner_headers",
                "parser/tokens/delimiters/summarize_brace_owner_headers"
            ),
            apply_brace_owner_headers: pass!(
                "parser.tokens.apply_brace_owner_headers",
                "parser/tokens/delimiters/apply_brace_owner_headers"
            ),
            tokens_brace_context: pass!(
                "parser_tokens_brace_context",
                "parser/tokens/contexts/classify_top_level_braces"
            ),
            summarize_statement_phases: pass!(
                "parser.tokens.summarize_statement_phases",
                "parser/tokens/contexts/summarize_statement_phases"
            ),
            apply_statement_phases: pass!(
                "parser.tokens.apply_statement_phases",
                "parser/tokens/contexts/apply_statement_phases"
            ),
            summarize_impl_headers: pass!(
                "parser.tokens.summarize_impl_headers",
                "parser/tokens/contexts/summarize_impl_headers"
            ),
            apply_impl_headers: pass!(
                "parser.tokens.apply_impl_headers",
                "parser/tokens/contexts/apply_impl_headers"
            ),
            summarize_where_clauses: pass!(
                "parser.tokens.summarize_where_clauses",
                "parser/tokens/contexts/summarize_where_clauses"
            ),
            apply_where_clauses: pass!(
                "parser.tokens.apply_where_clauses",
                "parser/tokens/contexts/apply_where_clauses"
            ),
            summarize_match_patterns: pass!(
                "parser.tokens.summarize_match_patterns",
                "parser/tokens/contexts/summarize_match_patterns"
            ),
            apply_match_patterns: pass!(
                "parser.tokens.apply_match_patterns",
                "parser/tokens/contexts/apply_match_patterns"
            ),
            build_delimiter_match_heaps: pass!(
                "parser.tokens.build_delimiter_match_heaps",
                "parser/tokens/delimiters/build_delimiter_match_heaps"
            ),
            build_delimiter_min_trees: pass!(
                "parser.tokens.build_delimiter_min_trees",
                "parser/tokens/delimiters/build_delimiter_min_trees"
            ),
            classify_bracket_roles: pass!(
                "parser.tokens.classify_bracket_roles",
                "parser/tokens/kinds/classify_bracket_roles"
            ),
            classify_square_brackets: pass!(
                "parser.tokens.classify_square_brackets",
                "parser/tokens/kinds/classify_square_brackets"
            ),
            classify_closing_braces: pass!(
                "parser.tokens.classify_closing_braces",
                "parser/tokens/kinds/classify_closing_braces"
            ),
            find_enclosing_delimiters: pass!(
                "parser.tokens.find_enclosing_delimiters",
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
            summarize_type_path_contexts: pass!(
                "parser.tokens.summarize_type_path_contexts",
                "parser/tokens/contexts/summarize_type_path_contexts"
            ),
            apply_type_path_contexts: pass!(
                "parser.tokens.apply_type_path_contexts",
                "parser/tokens/contexts/apply_type_path_contexts"
            ),
            tokens_to_identifier_kinds: pass!(
                "parser_tokens_to_identifier_kinds",
                "parser/tokens/kinds/retag_identifier_kinds"
            ),
            scan_raw_angle_depths_in_blocks: pass!(
                "parser.tokens.scan_raw_angle_depths_in_blocks",
                "parser/tokens/delimiters/scan_raw_angle_depths_in_blocks"
            ),
            apply_raw_angle_depths: pass!(
                "parser.tokens.apply_raw_angle_depths",
                "parser/tokens/delimiters/apply_raw_angle_depths"
            ),
            summarize_generic_angle_effects: pass!(
                "parser.tokens.summarize_generic_angle_effects",
                "parser/tokens/kinds/summarize_generic_angle_effects"
            ),
            scan_generic_angle_effect_blocks: pass!(
                "parser.tokens.scan_generic_angle_effect_blocks",
                "parser/tokens/kinds/scan_generic_angle_effect_blocks"
            ),
            mark_generic_shift_splits: pass!(
                "parser.tokens.mark_generic_shift_splits",
                "parser/tokens/kinds/mark_generic_shift_splits"
            ),
            classify_split_shift_closers: pass!(
                "parser.tokens.classify_split_shift_closers",
                "parser/tokens/kinds/classify_split_shift_closers"
            ),
        })
    }
}
