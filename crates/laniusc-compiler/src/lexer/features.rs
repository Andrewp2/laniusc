//! Conservative parser-family feature bits published by the GPU lexer.

/// Semantic parser classification observed generic type-argument syntax.
pub const PARSER_FEATURE_TYPE_ARGS: u32 = 0x0000_0001;
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
/// Source contains trait, impl, or where-clause predicate syntax.
pub const PARSER_FEATURE_PREDICATES: u32 = 0x0000_0020;
/// Source contains member or method access syntax.
pub const PARSER_FEATURE_MEMBERS: u32 = 0x0000_0040;
/// Source contains import syntax and requires compact import tables.
pub const PARSER_FEATURE_IMPORTS: u32 = 0x0000_0080;
/// Source contains a local type-alias declaration.
pub const PARSER_FEATURE_TYPE_ALIASES: u32 = 0x0000_0100;
/// Source contains a string expression rather than only import or extern ABI strings.
pub const PARSER_FEATURE_STRING_EXPRS: u32 = 0x0000_0200;

/// Parser families whose absence can be proven directly from final lexical tokens.
pub const LEXICALLY_PROVEN_PARSER_FEATURES: u32 = PARSER_FEATURE_ARRAYS
    | PARSER_FEATURE_ENUMS
    | PARSER_FEATURE_MATCHES
    | PARSER_FEATURE_PREDICATES
    | PARSER_FEATURE_MEMBERS
    | PARSER_FEATURE_IMPORTS
    | PARSER_FEATURE_TYPE_ALIASES
    | PARSER_FEATURE_STRING_EXPRS;

/// Safe fallback when a caller has not run GPU feature classification.
///
/// Unknown means present: disabling a family is valid only when the measured
/// feature flags prove it absent.
pub const CONSERVATIVE_PARSER_FEATURES: u32 = u32::MAX;
