mod common;

use laniusc_compiler::lexer::{
    GpuLexer,
    features::{
        LEXICALLY_PROVEN_PARSER_FEATURES,
        PARSER_FEATURE_ARRAYS,
        PARSER_FEATURE_ENUMS,
        PARSER_FEATURE_MATCHES,
    },
};

#[test]
fn gpu_lexer_publishes_conservative_parser_family_flags() {
    common::block_on_gpu_with_timeout("lexer parser feature flags", async move {
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        for (source, expected) in [
            ("fn main() -> i32 { return 0; }", 0),
            (
                "fn main() -> i32 { let xs: [i32; 1] = [7]; return xs[0]; }",
                PARSER_FEATURE_ARRAYS,
            ),
            (
                "enum Choice { A, B } fn main() -> i32 { return 0; }",
                PARSER_FEATURE_ENUMS,
            ),
            (
                "fn main() -> i32 { return match 1 { _ => 0 }; }",
                PARSER_FEATURE_MATCHES,
            ),
            (
                "enum Choice { A } fn main() -> i32 { let xs: [i32; 1] = [1]; return match xs[0] { _ => 0 }; }",
                LEXICALLY_PROVEN_PARSER_FEATURES,
            ),
        ] {
            let actual = lexer
                .debug_parser_feature_flags(source)
                .await
                .expect("read GPU lexer parser feature flags");
            assert_eq!(actual, expected, "source:\n{source}");
        }
    });
}
