// src/lexer/tables/mod.rs
pub mod build;
pub mod compact;
pub mod dfa;
pub mod io;
pub mod tokens;

// Re-exports to keep the external API unchanged.
pub use build::build_tables;
pub use io::{load_tables_bin_bytes, load_tables_json_bytes, save_tables_bin, save_tables_json};
pub use tokens::{INVALID_TOKEN, TokenKind};

/// Packed tables used by GPU kernels + gen_tables.
/// NOTE: `emit_on_start` was removed because it was unused in the pipeline.
pub struct Tables {
    pub char_to_func: [u32; 256],
    pub merge: Vec<u32>,    // m*m row-major
    pub token_of: Vec<u32>, // m -> TokenKind or INVALID_TOKEN
    pub m: u32,             // number of functions (including identity)
    pub identity: u32,      // identity id (0)
}
