/// Applies scanned bracket prefix counts back to per-token rows.
pub mod apply_prefix;
/// Clears the optional debug stack-match relation.
pub mod clear_matches;
/// Builds the block-minimum tree used by PSE stack validation.
pub mod min_tree;
/// Pairs pseudo-edge bracket records after layer scattering.
pub mod pse_pair;
/// Scans bracket block totals into global prefix offsets.
pub mod scan_block_prefix;
/// Computes in-block bracket depth and local counts.
pub mod scan_inblock;
