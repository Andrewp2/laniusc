/// Compact runtime DFA table loader.
pub mod compact;
/// Hand-built DFA used by table generation and the CPU oracle.
pub mod dfa;
/// Lexer table serialization helpers.
pub mod io;
/// Token kind definitions and token id constants.
pub mod tokens;

pub use io::{load_tables_bin_bytes, load_tables_json_bytes, save_tables_bin, save_tables_json};
pub use tokens::{INVALID_TOKEN, TokenKind};

/// Full lexer table form used by table generation and compatibility tests.
///
/// Runtime GPU lexing loads the compact table form from `lexer_tables.bin`;
/// this structure remains the readable source form for generation and tests.
pub struct Tables {
    /// Maps each byte value to the DFA summary function it represents.
    pub char_to_func: [u32; 256],
    /// Row-major merge table for DFA summary-function composition.
    pub merge: Vec<u32>,
    /// Maps summary/state ids to `TokenKind` or `INVALID_TOKEN`.
    pub token_of: Vec<u32>,
    /// Number of summary functions, including the identity function.
    pub m: u32,
    /// Identity function id.
    pub identity: u32,
}
