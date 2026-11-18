/// Applies scanned bracket prefix counts back to per-token rows.
pub mod apply_bracket_block_prefix;
/// Builds the block-minimum tree used by PSE stack validation.
pub mod build_bracket_min_tree;
/// Clears the optional debug stack-match relation.
pub mod clear_bracket_matches;
/// Parser acceptance status passes.
pub mod combine_pack_and_bracket_status;
/// Pairs pseudo-edge bracket records after layer scattering.
pub mod pair_brackets_by_layer;
/// Scans bracket block totals into global prefix offsets.
pub mod scan_bracket_blocks;
/// Computes in-block bracket depth and local counts.
pub mod scan_bracket_depths_in_blocks;
