/// Applies scanned bracket prefix counts back to per-token rows.
pub mod apply_prefix;
/// Builds per-layer bracket histogram counts.
pub mod histogram_layers;
/// Pairs pseudo-edge bracket records after layer scattering.
pub mod pse_pair;
/// Scans bracket block totals into global prefix offsets.
pub mod scan_block_prefix;
/// Scans bracket histograms across bracket layers.
pub mod scan_histograms;
/// Computes in-block bracket depth and local counts.
pub mod scan_inblock;
/// Scatters bracket records into layer-ordered storage.
pub mod scatter_by_layer;
