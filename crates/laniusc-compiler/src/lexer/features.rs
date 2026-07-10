//! Conservative parser-family feature bits published by the GPU lexer.

/// Source contains bracket syntax and may require parser array metadata.
pub const PARSER_FEATURE_ARRAYS: u32 = 0x0000_0002;
/// Source contains an enum declaration and may require parser enum metadata.
pub const PARSER_FEATURE_ENUMS: u32 = 0x0000_0004;
/// Source contains a match expression and may require parser match metadata.
pub const PARSER_FEATURE_MATCHES: u32 = 0x0000_0008;
/// Semantic parser classification observed a struct declaration or literal.
/// The lexer does not claim this bit because imported-type literals cannot be
/// proven from raw keyword presence alone.
pub const PARSER_FEATURE_STRUCTS: u32 = 0x0000_0010;

/// Parser families whose absence can be proven directly from final lexical tokens.
pub const LEXICALLY_PROVEN_PARSER_FEATURES: u32 =
    PARSER_FEATURE_ARRAYS | PARSER_FEATURE_ENUMS | PARSER_FEATURE_MATCHES;
