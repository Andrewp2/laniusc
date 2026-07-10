/// Initializes nearest-context relation rows.
pub mod init;
/// Scatters nearest-context relation rows into semantic HIR records.
pub mod scatter;
/// Propagates nearest-context relation rows through semantic HIR ancestry.
pub mod step;
/// Propagates small nearest-context tables in one cooperative workgroup.
pub mod step_small;
