// Parsers’ passes now use the shared Pass trait from gpu::passes_core.
pub mod brackets_match;
pub mod llp_pairs;
pub mod pack_varlen;

// Re-export the pass structs so callers can `use parser::gpu::passes::*`.
pub use brackets_match::*;
pub use llp_pairs::*;
pub use pack_varlen::*;
