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
    | PARSER_FEATURE_STRUCTS
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

/// Converts the lexer's proven feature set into a safe parser-allocation set.
///
/// Struct literals may name a type imported from another source file. A unit
/// therefore needs struct-family storage when it either declares a struct or
/// contains imports; when neither token occurs, no struct type can be in scope
/// for a literal and absence is proven lexically.
pub const fn parser_allocation_features(lexical_features: u32) -> u32 {
    if lexical_features & PARSER_FEATURE_IMPORTS != 0 {
        lexical_features | PARSER_FEATURE_STRUCTS
    } else {
        lexical_features
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_allocation_keeps_semantically_discovered_structs_enabled() {
        assert_eq!(
            parser_allocation_features(PARSER_FEATURE_IMPORTS),
            PARSER_FEATURE_IMPORTS | PARSER_FEATURE_STRUCTS
        );
    }

    #[test]
    fn parser_allocation_does_not_enable_structs_without_declarations_or_imports() {
        assert_eq!(
            parser_allocation_features(PARSER_FEATURE_ARRAYS),
            PARSER_FEATURE_ARRAYS
        );
        assert_eq!(parser_allocation_features(0), 0);
    }
}
