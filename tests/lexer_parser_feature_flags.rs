mod common;

use laniusc_compiler::{
    lexer::{
        GpuLexer,
        features::{
            PARSER_FEATURE_ARRAYS,
            PARSER_FEATURE_ENUMS,
            PARSER_FEATURE_IMPORTS,
            PARSER_FEATURE_MATCHES,
            PARSER_FEATURE_MEMBERS,
            PARSER_FEATURE_PREDICATES,
            PARSER_FEATURE_STRING_EXPRS,
            PARSER_FEATURE_TYPE_ALIASES,
        },
    },
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
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
                "type Value = i32; enum Choice { A } fn main() -> i32 { let xs: [Value; 1] = [1]; return match xs[0] { _ => 0 }; }",
                PARSER_FEATURE_ARRAYS
                    | PARSER_FEATURE_ENUMS
                    | PARSER_FEATURE_MATCHES
                    | PARSER_FEATURE_TYPE_ALIASES,
            ),
            (
                "type Value = i32; fn main() -> Value { return 0; }",
                PARSER_FEATURE_TYPE_ALIASES,
            ),
            (
                "module app::main; import core::math; fn main() -> i32 { return 0; }",
                PARSER_FEATURE_IMPORTS,
            ),
            (
                "struct Point { x: i32 } fn main(p: Point) -> i32 { return p.x; }",
                PARSER_FEATURE_MEMBERS,
            ),
            (
                "trait Value { fn get(self) -> i32; } impl Value for i32 { fn get(self) -> i32 { return self; } }",
                PARSER_FEATURE_PREDICATES,
            ),
            (
                "extern \"host_abi\" fn host(); fn main() -> i32 { return 0; }",
                0,
            ),
            (
                "import \"core/math.lani\"; fn main() -> i32 { return 0; }",
                PARSER_FEATURE_IMPORTS,
            ),
            (
                "fn main() -> i32 { print(\"hello\"); return 0; }",
                PARSER_FEATURE_STRING_EXPRS,
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

#[test]
fn gpu_parser_type_arg_feature_ignores_comparisons_and_tracks_generics() {
    common::block_on_gpu_with_timeout("parser type-arg feature flags", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        for (source, expected) in [
            (
                "fn main(x: i32) -> i32 { if (x < 7) { return x; } return 7; }",
                0,
            ),
            (
                "fn id<T>(value: T) -> T { return value; } fn main() -> i32 { return id<i32>(7); }",
                laniusc_compiler::lexer::features::PARSER_FEATURE_TYPE_ARGS,
            ),
            (
                "module app::main; import core::math; fn main() -> i32 { return 0; }",
                laniusc_compiler::lexer::features::PARSER_FEATURE_IMPORTS,
            ),
            (
                "type Value = i32; fn main() -> Value { return 0; }",
                laniusc_compiler::lexer::features::PARSER_FEATURE_TYPE_ALIASES,
            ),
            (
                "extern \"host_abi\" fn host(); fn main() -> i32 { return 0; }",
                0,
            ),
            (
                "fn main() -> i32 { print(\"hello\"); return 0; }",
                laniusc_compiler::lexer::features::PARSER_FEATURE_STRING_EXPRS,
            ),
            (
                "trait Eq<T> { fn check(value: T) -> bool; } impl Eq<i32> for i32 { fn check(value: i32) -> bool { return true; } }",
                laniusc_compiler::lexer::features::PARSER_FEATURE_TYPE_ARGS
                    | laniusc_compiler::lexer::features::PARSER_FEATURE_PREDICATES,
            ),
        ] {
            let actual = lexer
                .with_resident_tokens(source, |_, _, buffers| {
                    parser.debug_token_feature_flags_for_resident_tokens(
                        buffers.n,
                        &buffers.tokens_out,
                        &buffers.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident lex should succeed")
                .expect("parser feature readback should succeed");
            assert_eq!(actual, expected, "source:\n{source}");
        }
    });
}
