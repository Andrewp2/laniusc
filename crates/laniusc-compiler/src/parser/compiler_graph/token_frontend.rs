//! Declarative identities and registration for token-facing parser work.

use super::{clear, input, reflected, workspace};
use crate::{
    gpu::{
        compiler_graph::{AccessMode, CompilerGraphBuilder, CompilerPhase, ResourceDomain},
        passes_core::PassData,
        scan::hierarchical_scan_levels,
    },
    parser::{compiler_graph::ParserGraphCapacity, passes::token_frontend::TokenFrontendPasses},
};

pub(in crate::parser) const DELIMITER_DEPTH_SCAN_UP: &str =
    "parser.tokens.delimiters.depth_scan.up";
pub(in crate::parser) const DELIMITER_DEPTH_SCAN_DOWN: &str =
    "parser.tokens.delimiters.depth_scan.down";
pub(in crate::parser) const DELIMITER_OWNER_HEADER_SCAN_UP: &str =
    "parser.tokens.delimiters.owner_header_scan.up";
pub(in crate::parser) const DELIMITER_OWNER_HEADER_SCAN_DOWN: &str =
    "parser.tokens.delimiters.owner_header_scan.down";
pub(in crate::parser) const DELIMITER_OWNER_SCAN_UP: &str =
    "parser.tokens.delimiters.owner_scan.up";
pub(in crate::parser) const DELIMITER_OWNER_SCAN_DOWN: &str =
    "parser.tokens.delimiters.owner_scan.down";
pub(in crate::parser) const IMPL_HEADER_SCAN_UP: &str = "parser.tokens.impl_header.scan.up";
pub(in crate::parser) const IMPL_HEADER_SCAN_DOWN: &str = "parser.tokens.impl_header.scan.down";
pub(in crate::parser) const STATEMENT_PHASE_SCAN_UP: &str = "parser.tokens.statement_phase.scan.up";
pub(in crate::parser) const STATEMENT_PHASE_SCAN_DOWN: &str =
    "parser.tokens.statement_phase.scan.down";
pub(in crate::parser) const MATCH_PATTERN_SCAN_UP: &str = "parser.tokens.match_pattern.scan.up";
pub(in crate::parser) const MATCH_PATTERN_SCAN_DOWN: &str = "parser.tokens.match_pattern.scan.down";
pub(in crate::parser) const WHERE_CLAUSE_SCAN_UP: &str = "parser.tokens.where_clause.scan.up";
pub(in crate::parser) const WHERE_CLAUSE_SCAN_DOWN: &str = "parser.tokens.where_clause.scan.down";
pub(in crate::parser) const TYPE_PATH_SCAN_UP: &str = "parser.tokens.type_path_context.scan.up";
pub(in crate::parser) const TYPE_PATH_SCAN_DOWN: &str = "parser.tokens.type_path_context.scan.down";
pub(in crate::parser) const GENERIC_SHR_RAW_SCAN_UP: &str = "parser.tokens.generic_shr.raw_scan.up";
pub(in crate::parser) const GENERIC_SHR_RAW_SCAN_DOWN: &str =
    "parser.tokens.generic_shr.raw_scan.down";
pub(in crate::parser) const GENERIC_SHR_SCAN_UP: &str = "parser.tokens.generic_shr.scan.up";
pub(in crate::parser) const GENERIC_SHR_SCAN_DOWN: &str = "parser.tokens.generic_shr.scan.down";
pub(in crate::parser) const IMPL_HEADER_KIND_CLEAR: &str = "parser.tokens.impl_header_kind.clear";
pub(in crate::parser) const FEATURE_FLAGS_CLEAR: &str = "parser.tokens.feature_flags.clear";
pub(in crate::parser) const BRACED_RHS_STATEMENT_KIND_CLEAR: &str =
    "parser.tokens.braced_rhs_statement_kind.clear";

const MIN_TREE_BUILD: &str = "parser.tokens.delimiter_match.build_min_tree";

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
        "braced_rhs_statement_kind",
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
    ] {
        let resource = workspace(graph, name, ResourceDomain::Tokens, token_rows * 4)?;
        if capacity.preclassified_token_kinds {
            graph.mark_zero_initialized(resource)?;
        }
    }

    for name in [
        "block_sum_paren",
        "block_sum_brace",
        "block_sum_bracket",
        "block_sum_angle",
        "hierarchy_paren",
        "hierarchy_brace",
        "hierarchy_bracket",
        "hierarchy_angle",
        "block_prefix_paren",
        "block_prefix_brace",
        "block_prefix_bracket",
        "block_prefix_angle",
        "top_brace_owner_block",
        "hierarchy_owner",
        "top_brace_owner_block_prefix",
        "statement_event_block",
        "statement_event_hierarchy",
        "statement_event_block_prefix",
        "generic_shr_block_sum",
        "generic_shr_block_min",
        "generic_shr_hierarchy_sum",
        "generic_shr_hierarchy_min",
        "generic_shr_block_prefix_sum",
        "generic_shr_block_prefix_min",
        "paren_match_block_min",
        "brace_match_block_min",
        "bracket_match_block_min",
        "angle_match_block_min",
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
    ] {
        let resource = workspace(graph, name, ResourceDomain::Tokens, tree_rows * 4)?;
        if capacity.preclassified_token_kinds {
            graph.mark_zero_initialized(resource)?;
        }
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

fn scan(
    graph: &mut CompilerGraphBuilder,
    up_name: &'static str,
    down_name: &'static str,
    up: &PassData,
    down: &PassData,
    up_aliases: &[(&'static str, &'static str, Option<AccessMode>)],
    down_aliases: &[(&'static str, &'static str, Option<AccessMode>)],
    initializes: &[&'static str],
    levels: usize,
) -> Result<(), String> {
    pass(graph, up_name, up, up_aliases)?;
    graph.mark_pass_bindings_initialize(up_name, initializes)?;
    graph.repeat_pass_range(levels as u32, up_name, up_name)?;
    if levels > 1 {
        pass(graph, down_name, down, down_aliases)?;
        graph.repeat_pass_range((levels - 1) as u32, down_name, down_name)?;
    }
    Ok(())
}

fn statement_scan(
    graph: &mut CompilerGraphBuilder,
    name_up: &'static str,
    name_down: &'static str,
    passes: &TokenFrontendPasses,
    levels: usize,
) -> Result<(), String> {
    scan(
        graph,
        name_up,
        name_down,
        &passes.token_statement_event_scan_up,
        &passes.token_statement_event_scan_down,
        &[(
            "statement_event_hierarchy",
            "statement_event_hierarchy",
            None,
        )],
        &[(
            "statement_event_hierarchy",
            "statement_event_hierarchy",
            None,
        )],
        &["statement_event_block_prefix", "statement_event_hierarchy"],
        levels,
    )
}

fn delimiter_scan(
    graph: &mut CompilerGraphBuilder,
    name_up: &'static str,
    name_down: &'static str,
    passes: &TokenFrontendPasses,
    levels: usize,
) -> Result<(), String> {
    const ALIASES: &[(&str, &str, Option<AccessMode>)] =
        &[("hierarchy_event", "statement_event_hierarchy", None)];
    scan(
        graph,
        name_up,
        name_down,
        &passes.token_delimiters_02_scan_up,
        &passes.token_delimiters_02_scan_down,
        ALIASES,
        ALIASES,
        &[
            "block_prefix_brace",
            "block_prefix_bracket",
            "block_prefix_paren",
            "block_prefix_angle",
            "top_brace_owner_block_prefix",
            "statement_event_block_prefix",
            "hierarchy_brace",
            "hierarchy_bracket",
            "hierarchy_paren",
            "hierarchy_angle",
            "hierarchy_owner",
            "hierarchy_event",
        ],
        levels,
    )
}

fn generic_scan(
    graph: &mut CompilerGraphBuilder,
    name_up: &'static str,
    name_down: &'static str,
    passes: &TokenFrontendPasses,
    levels: usize,
) -> Result<(), String> {
    const ALIASES: &[(&str, &str, Option<AccessMode>)] = &[
        ("block_sum", "generic_shr_block_sum", None),
        ("block_min", "generic_shr_block_min", None),
        ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
        ("block_prefix_min", "generic_shr_block_prefix_min", None),
        ("hierarchy_sum", "generic_shr_hierarchy_sum", None),
        ("hierarchy_min", "generic_shr_hierarchy_min", None),
    ];
    scan(
        graph,
        name_up,
        name_down,
        &passes.tokens_generic_shr_02_scan_up,
        &passes.tokens_generic_shr_02_scan_down,
        ALIASES,
        ALIASES,
        &[
            "block_prefix_sum",
            "block_prefix_min",
            "hierarchy_sum",
            "hierarchy_min",
        ],
        levels,
    )
}

pub(super) fn register_schedule(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &TokenFrontendPasses,
) -> Result<(), String> {
    let blocks = capacity.token_capacity.div_ceil(256).max(1);
    let levels = hierarchical_scan_levels(blocks).len();

    clear(
        graph,
        IMPL_HEADER_KIND_CLEAR,
        CompilerPhase::Parse,
        &[("token_impl_header_kind", "token_impl_header_kind")],
    )?;
    pass(
        graph,
        "parser.tokens.impl_header.local",
        &passes.tokens_impl_header_01_local,
        &[(
            "statement_event_block",
            "statement_event_block",
            Some(AccessMode::Write),
        )],
    )?;
    statement_scan(
        graph,
        IMPL_HEADER_SCAN_UP,
        IMPL_HEADER_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.impl_header.apply",
        &passes.tokens_impl_header_02_apply,
        &[(
            "token_impl_context_event",
            "token_impl_context_event",
            Some(AccessMode::Write),
        )],
    )?;

    pass(
        graph,
        "parser.tokens.delimiters.local",
        &passes.token_delimiters_01,
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
    delimiter_scan(
        graph,
        DELIMITER_DEPTH_SCAN_UP,
        DELIMITER_DEPTH_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.generic_shr.raw_local",
        &passes.tokens_generic_shr_00_raw_local,
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
    generic_scan(
        graph,
        GENERIC_SHR_RAW_SCAN_UP,
        GENERIC_SHR_RAW_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.generic_shr.raw_apply",
        &passes.tokens_generic_shr_00_raw_apply,
        &[
            ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
            ("block_prefix_min", "generic_shr_block_prefix_min", None),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.delimiters.owner_local",
        &passes.token_delimiters_03_owner_local,
        &[],
    )?;
    delimiter_scan(
        graph,
        DELIMITER_OWNER_HEADER_SCAN_UP,
        DELIMITER_OWNER_HEADER_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.delimiters.owner_apply",
        &passes.token_delimiters_04_owner_apply,
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
    delimiter_scan(
        graph,
        DELIMITER_OWNER_SCAN_UP,
        DELIMITER_OWNER_SCAN_DOWN,
        passes,
        levels,
    )?;
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
        "parser.tokens.statement_phase.local",
        &passes.tokens_statement_phase_01_local,
        &[],
    )?;
    statement_scan(
        graph,
        STATEMENT_PHASE_SCAN_UP,
        STATEMENT_PHASE_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.statement_phase.apply",
        &passes.tokens_statement_phase_02_apply,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.delimiter_match.depth_blocks",
        &passes.tokens_delimiter_match_01_depth_blocks,
        &[
            (
                "bracket_semantic_kind",
                "bracket_semantic_kind",
                Some(AccessMode::Write),
            ),
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
        ],
    )?;
    pass(
        graph,
        MIN_TREE_BUILD,
        &passes.tokens_delimiter_match_02_build_min_tree,
        &[],
    )?;
    graph.mark_pass_bindings_initialize(
        MIN_TREE_BUILD,
        &[
            "paren_match_min_tree",
            "brace_match_min_tree",
            "bracket_match_min_tree",
            "angle_match_min_tree",
        ],
    )?;
    graph.repeat_pass_range(
        blocks.next_power_of_two().ilog2() + 1,
        MIN_TREE_BUILD,
        MIN_TREE_BUILD,
    )?;
    clear(
        graph,
        BRACED_RHS_STATEMENT_KIND_CLEAR,
        CompilerPhase::Parse,
        &[("braced_rhs_statement_kind", "braced_rhs_statement_kind")],
    )?;
    pass(
        graph,
        "parser.tokens.brace_match.pair_pse",
        &passes.tokens_brace_match_03_pair_pse,
        &[],
    )?;
    pass(
        graph,
        "parser.tokens.bracket_match.pair_pse",
        &passes.tokens_bracket_match_03_pair_pse,
        &[],
    )?;

    pass(
        graph,
        "parser.tokens.match_pattern.local",
        &passes.tokens_match_pattern_01_local,
        &[],
    )?;
    statement_scan(
        graph,
        MATCH_PATTERN_SCAN_UP,
        MATCH_PATTERN_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.match_pattern.apply",
        &passes.tokens_match_pattern_02_apply,
        &[(
            "token_match_pattern_context_event",
            "token_match_pattern_context_event",
            Some(AccessMode::Write),
        )],
    )?;
    pass(
        graph,
        "parser.tokens.where_clause.local",
        &passes.tokens_where_clause_01_local,
        &[],
    )?;
    statement_scan(
        graph,
        WHERE_CLAUSE_SCAN_UP,
        WHERE_CLAUSE_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.where_clause.apply",
        &passes.tokens_where_clause_02_apply,
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
        "parser.tokens.type_path_context.local",
        &passes.tokens_type_path_context_01_local,
        &[("semantic_token_kinds", "token_kinds", None)],
    )?;
    statement_scan(
        graph,
        TYPE_PATH_SCAN_UP,
        TYPE_PATH_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.type_path_context.apply",
        &passes.tokens_type_path_context_02_apply,
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
        "parser.tokens.generic_shr.local",
        &passes.tokens_generic_shr_01_local,
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
    generic_scan(
        graph,
        GENERIC_SHR_SCAN_UP,
        GENERIC_SHR_SCAN_DOWN,
        passes,
        levels,
    )?;
    pass(
        graph,
        "parser.tokens.generic_shr.apply",
        &passes.tokens_generic_shr_03_apply,
        &[
            ("block_prefix_sum", "generic_shr_block_prefix_sum", None),
            ("block_prefix_min", "generic_shr_block_prefix_min", None),
            ("semantic_token_kinds_rw", "token_kinds", None),
        ],
    )?;
    pass(
        graph,
        "parser.tokens.generic_shr.close_kinds",
        &passes.tokens_generic_shr_04_close_kinds,
        &[("semantic_token_kinds", "token_kinds", None)],
    )?;
    Ok(())
}
