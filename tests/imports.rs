mod common;

use std::{fs, io, path::PathBuf};

use laniusc::{
    compiler::{
        CompileError,
        compile_source_to_wasm_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen_from_path,
        expand_source_imports,
        expand_source_imports_from_path,
    },
    hir::parse_source,
};

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(stem: &str) -> Self {
        let path = common::temp_artifact_path("laniusc_imports", stem, None);
        fs::create_dir_all(&path)
            .unwrap_or_else(|err| panic!("create temporary directory {}: {err}", path.display()));
        Self { path }
    }

    fn write(&self, relative: &str, contents: &str) -> PathBuf {
        let path = self.path.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .unwrap_or_else(|err| panic!("create directory {}: {err}", parent.display()));
        }
        fs::write(&path, contents)
            .unwrap_or_else(|err| panic!("write temporary file {}: {err}", path.display()));
        path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        match fs::remove_dir_all(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(_) => {}
        }
    }
}

#[test]
fn source_only_stdlib_import_expands_and_compiles() {
    let src = r#"
import "stdlib/i32.lani";

fn main() {
    return lstd_i32_abs(-7);
}
"#;

    let expanded = expand_source_imports(src).expect("expand stdlib import");
    assert!(expanded.contains("pub fn lstd_i32_abs"));
    assert!(!expanded.contains("import \"stdlib/i32.lani\";"));
    parse_source(&expanded).expect("expanded stdlib import should parse");

    let wasm = pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src))
        .expect("stdlib import should compile to WASM");
    assert_eq!(
        &wasm[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
}

#[test]
fn relative_imports_resolve_from_each_importing_file() {
    let dir = TempDir::new("relative");
    dir.write(
        "constants.lani",
        r#"
pub fn base_value() -> i32 {
    return 41;
}
"#,
    );
    dir.write(
        "helpers/math.lani",
        r#"
import "../constants.lani";

pub fn answer() -> i32 {
    return base_value() + 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "helpers/math.lani";

fn main() {
    return answer();
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand relative imports");
    assert!(expanded.contains("pub fn base_value"));
    assert!(expanded.contains("pub fn answer"));
    parse_source(&expanded).expect("expanded relative imports should parse");

    let wasm = pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(&main))
        .expect("relative imports should compile to WASM");
    assert_eq!(
        &wasm[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
}

#[test]
fn duplicate_canonical_import_expands_once() {
    let dir = TempDir::new("duplicate");
    dir.write(
        "helper.lani",
        r#"
pub fn imported_once() -> i32 {
    return 1;
}
"#,
    );
    let main = dir.write(
        "main.lani",
        r#"
import "helper.lani";
import "helper.lani";

fn main() {
    return imported_once();
}
"#,
    );

    let expanded = expand_source_imports_from_path(&main).expect("expand duplicate imports");
    assert_eq!(expanded.matches("pub fn imported_once").count(), 1);
    parse_source(&expanded).expect("expanded duplicate import should parse");
}

#[test]
fn import_cycles_return_clear_error() {
    let dir = TempDir::new("cycle");
    let a = dir.write(
        "a.lani",
        r#"
import "b.lani";

pub fn a() -> i32 {
    return 1;
}
"#,
    );
    dir.write(
        "b.lani",
        r#"
import "a.lani";

pub fn b() -> i32 {
    return 2;
}
"#,
    );

    let err = expand_source_imports_from_path(&a).expect_err("cycle should fail import expansion");
    match err {
        CompileError::Import(message) => {
            assert!(
                message.contains("import cycle detected"),
                "expected cycle error, got {message}"
            );
            assert!(
                message.contains("a.lani"),
                "expected cycle path, got {message}"
            );
            assert!(
                message.contains("b.lani"),
                "expected cycle path, got {message}"
            );
        }
        other => panic!("expected import error, got {other:?}"),
    }
}
