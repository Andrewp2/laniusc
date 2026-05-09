use std::{
    fs,
    path::{Path, PathBuf},
};

use laniusc::{
    compiler::compile_source_to_wasm_with_gpu_codegen,
    hir::{HirItem, parse_source},
    lexer::cpu::lex_on_cpu,
    parser::cpu::parse_from_token_kinds,
};

fn stdlib_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("stdlib")
}

fn stdlib_lani_paths() -> Vec<PathBuf> {
    let mut pending = vec![stdlib_root()];
    let mut paths = Vec::new();

    while let Some(dir) = pending.pop() {
        for entry in fs::read_dir(&dir)
            .unwrap_or_else(|err| panic!("read stdlib dir {}: {err}", dir.display()))
        {
            let path = entry
                .unwrap_or_else(|err| panic!("read entry in {}: {err}", dir.display()))
                .path();
            if path.is_dir() {
                pending.push(path);
            } else if path.extension().and_then(|ext| ext.to_str()) == Some("lani") {
                paths.push(path);
            }
        }
    }

    paths.sort();
    paths
}

fn read_stdlib_sources() -> Vec<(PathBuf, String)> {
    stdlib_lani_paths()
        .into_iter()
        .map(|path| {
            let src = fs::read_to_string(&path)
                .unwrap_or_else(|err| panic!("read stdlib source {}: {err}", path.display()));
            (path, src)
        })
        .collect()
}

fn combined_stdlib_source() -> String {
    let mut combined = String::new();
    for (path, src) in read_stdlib_sources() {
        combined.push_str("// ");
        combined.push_str(
            &path
                .strip_prefix(stdlib_root())
                .unwrap_or(&path)
                .display()
                .to_string(),
        );
        combined.push('\n');
        combined.push_str(&src);
        if !src.ends_with('\n') {
            combined.push('\n');
        }
        combined.push('\n');
    }
    combined
}

#[test]
fn stdlib_sources_parse_with_cpu_parser_and_hir() {
    let sources = read_stdlib_sources();
    assert!(
        sources.len() >= 3,
        "expected the stdlib to contain multiple .lani sources"
    );

    for (path, src) in sources {
        let name = path.display().to_string();
        let tokens = lex_on_cpu(&src).unwrap_or_else(|err| panic!("{name}: CPU lex failed: {err}"));
        let kinds = tokens.iter().map(|token| token.kind).collect::<Vec<_>>();
        let ast = parse_from_token_kinds(&kinds)
            .unwrap_or_else(|err| panic!("{name}: CPU parser rejected stdlib source: {err}"));
        assert_eq!(ast.nodes[ast.root as usize].tag, "file", "{name}: root tag");

        let hir =
            parse_source(&src).unwrap_or_else(|err| panic!("{name}: HIR parse failed: {err}"));
        assert!(
            !hir.items.is_empty(),
            "{name}: stdlib source should define public functions"
        );
        for item in hir.items {
            let HirItem::Fn(func) = item else {
                panic!("{name}: stdlib source should only contain function items");
            };
            assert!(func.public, "{name}: {} should be pub", func.name);
        }
    }
}

#[test]
fn stdlib_type_checks_representative_concatenated_usage() {
    let mut src = combined_stdlib_source();
    src.push_str(
        r#"
fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let total: i32 = lstd_i32x4_sum(values);
    let low: i32 = lstd_i32x4_min(values);
    let high: i32 = lstd_i32x4_max(values);
    let high_limit: i32 = high * 2;
    let limited: i32 = lstd_i32_clamp(total, low, high_limit);
    let found: bool = lstd_i32x4_contains(values, 4);
    let upper: i32 = high * 3;
    let inside: bool = lstd_i32_between_inclusive(limited, low, upper);
    let ok: bool = lstd_bool_and(found, inside);
    let negative_total: bool = total < 0;
    let flipped: bool = lstd_bool_xor(ok, negative_total);

    if (flipped) {
        let ok_value: i32 = lstd_bool_to_i32(ok);
        print(ok_value);
    } else {
        let fallback: i32 = lstd_i32x4_get_or(values, 2, 0);
        print(fallback);
    }

    let abs_value: i32 = lstd_i32_abs(-7);
    let sign: i32 = lstd_i32_signum(limited);
    return lstd_i32_max(abs_value, sign);
}
"#,
    );

    parse_source(&src).expect("combined stdlib usage should parse as HIR");
    let wasm = pollster::block_on(compile_source_to_wasm_with_gpu_codegen(&src))
        .expect("combined stdlib usage should type-check and compile to WASM");
    assert!(wasm.len() >= 8, "WASM output should contain a header");
    assert_eq!(
        &wasm[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
}
