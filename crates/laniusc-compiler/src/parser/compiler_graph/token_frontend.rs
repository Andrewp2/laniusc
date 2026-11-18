//! Declarative identities and registration for token-facing parser work.

use super::{clear, input, reflected, workspace};
use crate::{
    gpu::{
        compiler_graph::{AccessMode, CompilerGraphBuilder, CompilerPhase, ResourceDomain},
        passes_core::PassData,
    },
    parser::{compiler_graph::ParserGraphCapacity, passes::tokens::TokenFrontendPasses},
};

pub(in crate::parser) const DELIMITER_DEPTH_SCAN: &str =
    "parser.tokens.delimiter_depths.scan_delimiter_depth_blocks";
pub(in crate::parser) const DELIMITER_OWNER_HEADER_SCAN: &str =
    "parser.tokens.brace_owner_headers.scan_delimiter_depth_blocks";
pub(in crate::parser) const DELIMITER_OWNER_SCAN: &str =
    "parser.tokens.brace_owners.scan_delimiter_depth_blocks";
pub(in crate::parser) const GENERIC_SHR_RAW_SCAN: &str =
    "parser.tokens.raw_angles.scan_generic_angle_effect_blocks";
pub(in crate::parser) const GENERIC_SHR_SCAN: &str =
    "parser.tokens.generic_angles.scan_generic_angle_effect_blocks";
pub(in crate::parser) const IMPL_HEADER_KIND_CLEAR: &str = "parser.tokens.impl_header_kind.clear";
pub(in crate::parser) const FEATURE_FLAGS_CLEAR: &str = "parser.tokens.feature_flags.clear";

pub(in crate::parser) const ENCLOSING_OPENS: &str = "parser.tokens.find_enclosing_delimiters";
pub(in crate::parser) const ANGLE_KINDS: &str = "parser.tokens_to_angle_kinds.pass";

const MIN_TREE_BUILD: &str = "parser.tokens.build_delimiter_min_trees";

pub(super) fn register_resources(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
) -> Result<(), String> {
    let token_rows = u64::from(capacity.n_tokens.max(1));
    let input_rows = u64::from(capacity.token_capacity.max(1));
    let blocks = capacity.token_capacity.div_ceil(256).max(1);
    let block_rows = u64::from(blocks);
    let tree_rows = u64::from(blocks.next_power_of_two()) * 2;

    input(
        graph,
        "token_words",
        ResourceDomain::Tokens,
        input_rows * 12,
    )?;
    input(graph, "lexer_token_count", ResourceDomain::Tokens, 4)?;

    for name in [
        "depth_paren_inblock",
        "depth_brace_inblock",
        "depth_bracket_inblock",
        "depth_angle_inblock",
        "brace_semantic_kind",
        "bracket_semantic_kind",
        "statement_context_kind",
        "token_impl_header_kind",
        "token_impl_context_event",
        "token_type_path_context_kind",
        "token_where_context_event",
        "token_match_pattern_context_event",
        "paren_match_depth",
        "brace_match_depth",
        "bracket_match_depth",
        "angle_match_depth",
        "token_angle_close",
        "token_direct_lt_kind",
        "statement_boundary_depth",
        "token_statement_start",
    ] {
        let resource = workspace(graph, name, ResourceDomain::Tokens, token_rows * 4)?;
        if capacity.preclassified_token_kinds {
            graph.mark_zero_initialized(resource)?;
        }
    }
    // One enclosing-row word per delimiter class (paren, brace, bracket, angle).
    let enclosing_open = workspace(
        graph,
        "token_enclosing_open",
        ResourceDomain::Tokens,
        token_rows * 16,
    )?;
    if capacity.preclassified_token_kinds {
        graph.mark_zero_initialized(enclosing_open)?;
    }

    for name in [
        "block_sum_paren",
        "block_sum_brace",
        "block_sum_bracket",
        "block_sum_angle",
        "block_prefix_paren",
        "block_prefix_brace",
        "block_prefix_bracket",
        "block_prefix_angle",
        "top_brace_owner_block",
        "top_brace_owner_block_prefix",
        "statement_event_block",
        "statement_event_block_prefix",
        "generic_shr_block_sum",
        "generic_shr_block_min",
        "generic_shr_block_prefix_sum",
        "generic_shr_block_prefix_min",
        "paren_match_block_min",
        "brace_match_block_min",
        "bracket_match_block_min",
        "angle_match_block_min",
        "statement_boundary_block_min",
    ] {
        let resource = workspace(graph, name, ResourceDomain::Tokens, block_rows * 4)?;
        if capacity.preclassified_token_kinds {
            graph.mark_zero_initialized(resource)?;
        }
    }

    for name in [
        "paren_match_min_tree",
        "brace_match_min_tree",
        "bracket_match_min_tree",
        "angle_match_min_tree",
        "statement_boundary_min_tree",
    ] {
        let resource = workspace(graph, name, ResourceDomain::Tokens, tree_rows * 4)?;
        if capacity.preclassified_token_kinds {
            graph.mark_zero_initialized(resource)?;
        }
    }
    // Every 256-token block's local minimum heap, one int4 (paren, brace,
    // bracket, angle) per heap node, so delimiter searches need no row scans.
    let local_min = workspace(
        graph,
        "delimiter_match_local_min",
        ResourceDomain::Tokens,
        block_rows * 256 * 16,
    )?;
    if capacity.preclassified_token_kinds {
        graph.mark_zero_initialized(local_min)?;
    }
    // The same heap over the statement boundary keys, one int per node.
    let boundary_local_min = workspace(
        graph,
        "statement_boundary_local_min",
        ResourceDomain::Tokens,
        block_rows * 256 * 4,
    )?;
    if capacity.preclassified_token_kinds {
        graph.mark_zero_initialized(boundary_local_min)?;
    }
    Ok(())
}

fn pass(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    data: &PassData,
    aliases: &[(&'static str, &'static str, Option<AccessMode>)],
) -> Result<(), String> {
    reflected(
        graph,
        name,
        CompilerPhase::Parse,
        ResourceDomain::Tokens,
        data,
        aliases,
    )
}

/// Registers a one-workgroup scan over every token block. It writes each
/// output row of the active blocks.
fn scan(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    data: &PassData,
    aliases: &[(&'static str, &'static str, Option<AccessMode>)],
    initializes: &[&'static str],
) -> Result<(), String> {
    pass(graph, name, data, aliases)?;
    graph.mark_pass_bindings_initialize(name, initializes)?;
    Ok(())
}

fn delimiter_scan(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    passes: &TokenFrontendPasses,
) -> Result<(), String> {
    scan(
        graph,
        name,
        &passes.scan_delimiter_depth_blocks,
        &[],
        &[
            "block_prefix_brace",
            "block_prefix_bracket",
            "block_prefix_paren",
            "block_prefix_angle",
            "top_brace_owner_block_prefix",
            "statement_event_block_prefix",
        ],
    )
}

fn generic_scan(
    graph: &mut CompilerGraphBuilder,
    name: &'static str,
    passes: &TokenFrontendPasses,
) -> Result<(), String> {
    const ALIASES: &[(&str, &str, Option<AccessMode>)] = &[
        ("block_sum", "generic_shr_block_sum", None),
        ("block_min", "generic_shr_block_min", None),
        ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
        ("block_prefix_min", "generic_shr_block_prefix_min", None),
    ];
    scan(
        graph,
        name,
        &passes.scan_generic_angle_effect_blocks,
        ALIASES,
        &["block_prefix_sum", "block_prefix_min"],
    )
}

pub(super) fn register_schedule(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &TokenFrontendPasses,
) -> Result<(), String> {
    let blocks = capacity.token_capacity.div_ceil(256).max(1);

    clear(
        graph,
        IMPL_HEADER_KIND_CLEAR,
        CompilerPhase::Parse,
        &[("token_impl_header_kind", "token_impl_header_kind")],
    )?;
    pass(
        graph,
        "parser.tokens.scan_delimiter_depths_in_blocks",
        &passes.scan_delimiter_depths_in_blocks,
        &[
            (
                "depth_brace_inblock",
                "depth_brace_inblock",
                Some(AccessMode::Write),
            ),
            (
                "depth_bracket_inblock",
                "depth_bracket_inblock",
                Some(AccessMode::Write),
            ),
            (
                "depth_paren_inblock",
                "depth_paren_inblock",
                Some(AccessMode::Write),
            ),
            (
                "depth_angle_inblock",
                "depth_angle_inblock",
                Some(AccessMode::Write),
            ),
            (
                "block_sum_brace",
                "block_sum_brace",
                Some(AccessMode::Write),
            ),
            (
                "block_sum_bracket",
                "block_sum_bracket",
                Some(AccessMode::Write),
            ),
            (
                "block_sum_paren",
                "block_sum_paren",
                Some(AccessMode::Write),
            ),
            (
                "block_sum_angle",
                "block_sum_angle",
                Some(AccessMode::Write),
            ),
            (
                "top_brace_owner_block",
                "top_brace_owner_block",
                Some(AccessMode::Write),
            ),
            (
                "statement_event_block",
                "statement_event_block",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    delimiter_scan(graph, DELIMITER_DEPTH_SCAN, passes)?;
    // Impl-header boundaries distinguish array-type separators from statement
    // terminators using the completed raw bracket-depth relation.
    pass(
        graph,
        "parser.tokens.summarize_impl_headers",
        &passes.summarize_impl_headers,
        &[(
            "statement_event_block",
            "statement_event_block",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.apply_impl_headers",
        &passes.apply_impl_headers,
        &[(
            "token_impl_context_event",
            "token_impl_context_event",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.scan_raw_angle_depths_in_blocks",
        &passes.scan_raw_angle_depths_in_blocks,
        &[
            (
                "block_sum",
                "generic_shr_block_sum",
                Some(AccessMode::Write),
            ),
            (
                "block_min",
                "generic_shr_block_min",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    generic_scan(graph, GENERIC_SHR_RAW_SCAN, passes)?;
    pass(
        graph,
        "parser.tokens.apply_raw_angle_depths",
        &passes.apply_raw_angle_depths,
        &[
            ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
            ("block_prefix_min", "generic_shr_block_prefix_min", None),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.build_delimiter_match_heaps",
        &passes.build_delimiter_match_heaps,
        &[
            (
                "paren_match_depth",
                "paren_match_depth",
                Some(AccessMode::Write),
            ),
            (
                "brace_match_depth",
                "brace_match_depth",
                Some(AccessMode::Write),
            ),
            (
                "bracket_match_depth",
                "bracket_match_depth",
                Some(AccessMode::Write),
            ),
            (
                "angle_match_depth",
                "angle_match_depth",
                Some(AccessMode::Write),
            ),
            (
                "paren_match_block_min",
                "paren_match_block_min",
                Some(AccessMode::Write),
            ),
            (
                "brace_match_block_min",
                "brace_match_block_min",
                Some(AccessMode::Write),
            ),
            (
                "bracket_match_block_min",
                "bracket_match_block_min",
                Some(AccessMode::Write),
            ),
            (
                "angle_match_block_min",
                "angle_match_block_min",
                Some(AccessMode::Write),
            ),
            (
                "delimiter_match_local_min",
                "delimiter_match_local_min",
                Some(AccessMode::Write),
            ),
            (
                "statement_boundary_depth",
                "statement_boundary_depth",
                Some(AccessMode::Write),
            ),
            (
                "statement_boundary_block_min",
                "statement_boundary_block_min",
                Some(AccessMode::Write),
            ),
            (
                "statement_boundary_local_min",
                "statement_boundary_local_min",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    pass(
        graph,
        MIN_TREE_BUILD,
        &passes.build_delimiter_min_trees,
        &[],
    )?;
    graph.mark_pass_bindings_initialize(
        MIN_TREE_BUILD,
        &[
            "paren_match_min_tree",
            "brace_match_min_tree",
            "bracket_match_min_tree",
            "angle_match_min_tree",
            "statement_boundary_min_tree",
        ],
    )?;
    graph.repeat_pass_range(
        blocks.next_power_of_two().ilog2() + 1,
        MIN_TREE_BUILD,
        MIN_TREE_BUILD,
    )?;
    // Delimiter ownership is published once per token as soon as the raw
    // match depths and their search trees exist; the pairing and semantic
    // classification passes read it instead of searching.
    pass(
        graph,
        ENCLOSING_OPENS,
        &passes.find_enclosing_delimiters,
        &[
            (
                "token_enclosing_open",
                "token_enclosing_open",
                Some(AccessMode::Write),
            ),
            (
                "token_angle_close",
                "token_angle_close",
                Some(AccessMode::Write),
            ),
            (
                "token_statement_start",
                "token_statement_start",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.summarize_brace_owner_headers",
        &passes.summarize_brace_owner_headers,
        &[],
    )?;
    delimiter_scan(graph, DELIMITER_OWNER_HEADER_SCAN, passes)?;
    pass(
        graph,
        "parser.tokens.apply_brace_owner_headers",
        &passes.apply_brace_owner_headers,
        &[
            (
                "top_brace_owner_block",
                "top_brace_owner_block",
                Some(AccessMode::Write),
            ),
            (
                "brace_semantic_kind",
                "brace_semantic_kind",
                Some(AccessMode::Write),
            ),
            (
                "statement_event_block",
                "statement_event_block",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    delimiter_scan(graph, DELIMITER_OWNER_SCAN, passes)?;
    pass(
        graph,
        "parser.tokens.brace_context",
        &passes.tokens_brace_context,
        &[(
            "statement_context_kind",
            "statement_context_kind",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.summarize_statement_phases",
        &passes.summarize_statement_phases,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.apply_statement_phases",
        &passes.apply_statement_phases,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.classify_bracket_roles",
        &passes.classify_bracket_roles,
        &[(
            "bracket_semantic_kind",
            "bracket_semantic_kind",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.classify_closing_braces",
        &passes.classify_closing_braces,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.classify_square_brackets",
        &passes.classify_square_brackets,
        &[],
    )?;

    // The local pass stores each token's own event; the apply pass reads it
    // at the same row and replaces it with the event before the token.
    pass(
        graph,
        "parser.tokens.summarize_match_patterns",
        &passes.summarize_match_patterns,
        &[(
            "token_match_pattern_context_event",
            "token_match_pattern_context_event",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.apply_match_patterns",
        &passes.apply_match_patterns,
        &[(
            "token_match_pattern_context_event",
            "token_match_pattern_context_event",
            Some(AccessMode::ReadWrite),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.summarize_where_clauses",
        &passes.summarize_where_clauses,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.apply_where_clauses",
        &passes.apply_where_clauses,
        &[(
            "token_where_context_event",
            "token_where_context_event",
            Some(AccessMode::Write),
        )],
    )?;
    clear(
        graph,
        FEATURE_FLAGS_CLEAR,
        CompilerPhase::Parse,
        &[("token_feature_flags", "token_feature_flags")],
    )?;
    // Each raw `<`'s own role is published once per token; semantic
    // classification reads it instead of searching.
    pass(
        graph,
        ANGLE_KINDS,
        &passes.tokens_to_angle_kinds,
        &[(
            "token_direct_lt_kind",
            "token_direct_lt_kind",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens_to_kinds.pass",
        &passes.tokens_to_kinds,
        &[
            (
                "semantic_token_kinds",
                "token_kinds",
                Some(AccessMode::Write),
            ),
            ("parser_token_count", "token_count", Some(AccessMode::Write)),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.summarize_type_path_contexts",
        &passes.summarize_type_path_contexts,
        &[("semantic_token_kinds", "token_kinds", None)],
    )?;
    pass(
        graph,
        "parser.tokens.apply_type_path_contexts",
        &passes.apply_type_path_contexts,
        &[
            ("semantic_token_kinds", "token_kinds", None),
            (
                "token_type_path_context_kind",
                "token_type_path_context_kind",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    pass(
        graph,
        "parser.tokens_to_identifier_kinds.pass",
        &passes.tokens_to_identifier_kinds,
        &[("semantic_token_kinds", "token_kinds", None)],
    )?;
    pass(
        graph,
        "parser.tokens.summarize_generic_angle_effects",
        &passes.summarize_generic_angle_effects,
        &[
            ("semantic_token_kinds", "token_kinds", None),
            (
                "block_sum",
                "generic_shr_block_sum",
                Some(AccessMode::Write),
            ),
            (
                "block_min",
                "generic_shr_block_min",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    generic_scan(graph, GENERIC_SHR_SCAN, passes)?;
    pass(
        graph,
        "parser.tokens.mark_generic_shift_splits",
        &passes.mark_generic_shift_splits,
        &[
            ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
            ("block_prefix_min", "generic_shr_block_prefix_min", None),
            ("semantic_token_kinds_rw", "token_kinds", None),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.classify_split_shift_closers",
        &passes.classify_split_shift_closers,
        &[("semantic_token_kinds", "token_kinds", None)],
    )?;
    Ok(())
}
