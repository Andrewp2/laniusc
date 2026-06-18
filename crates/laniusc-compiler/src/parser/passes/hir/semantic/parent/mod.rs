/// Initializes semantic parent propagation rows.
pub mod init;
/// Scatters propagated semantic parents into dense HIR rows.
pub mod scatter;
/// Propagates semantic parent rows through tree ancestry.
pub mod step;
