mod common;

use laniusc::compiler::CompileError;

#[test]
fn imports_expose_only_public_declarations_from_imported_module_records() {
    let imported_module = r#"
module lib::api;

pub fn exposed() -> i32 {
    return 1;
}

fn hidden() -> i32 {
    return 2;
}
"#;
    let unimported_decoy = r#"
module lib::decoy;

pub fn hidden() -> i32 {
    return 3;
}
"#;

    common::type_check_source_pack_with_timeout(&[
        imported_module,
        unimported_decoy,
        r#"
module app::main;

import lib::api;

fn main() {
    return exposed();
}
"#,
    ])
    .expect("imported public declarations should be visible through source-pack module records");

    match common::type_check_source_pack_with_timeout(&[
        imported_module,
        unimported_decoy,
        r#"
module app::main;

import lib::api;

fn main() {
    return hidden();
}
"#,
    ]) {
        Ok(()) => panic!(
            "private declarations from imported modules must not compile, \
             even when an unimported public declaration has the same name"
        ),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type-check rejection, got {other:?}"),
    }
}
