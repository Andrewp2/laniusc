/// Builds the semantic-end search heaps the parent search reads.
pub mod end_tree;
/// Propagates semantic parent rows through tree ancestry.
pub mod step;
/// Finds dense semantic parents by searching the semantic-end heaps.
pub mod traverse;
