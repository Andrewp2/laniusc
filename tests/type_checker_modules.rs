mod common;

use laniusc::compiler::{CompileError, GpuCompiler, type_check_source_with_gpu_using};

fn assert_gpu_type_check_accepts(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_accepts_with_fresh_compiler(path: &'static str, src: &'static str) {
    common::block_on_gpu_with_timeout(&format!("fresh GPU type check for {path}"), async move {
        let compiler = GpuCompiler::new().await?;
        type_check_source_with_gpu_using(src, &compiler).await
    })
    .unwrap_or_else(|err| panic!("{path} should pass GPU type checking: {err:?}"));
}

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!("source pack should fail GPU type checking"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_leading_module_metadata() {
    assert_gpu_type_check_accepts("module app::main;");
    assert_gpu_type_check_accepts("module app::main; fn main() { return 0; }");
}

#[test]
fn type_checker_source_pack_resolves_path_import_metadata_without_visibility() {
    common::type_check_source_pack_with_timeout(&["module app::main; fn main() { return 0; }"])
        .expect(
            "single-file explicit source-pack input should pass through resident GPU type checking",
        );

    common::type_check_source_pack_with_timeout(&[
        "module core::math; fn one() -> i32 { return 1; } ",
        "module app::main; fn main() { return 0; }",
    ])
    .expect("multi-file explicit source-pack module metadata should stay metadata without imports");

    common::type_check_source_pack_with_timeout(&[
        "module core::math; pub fn one() -> i32 { return 1; } ",
        "module app::main; import core::math; fn main() { return 0; }",
    ])
    .expect("path imports should resolve to an already-uploaded module on GPU");

    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import core::math; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import \"stdlib/core/math.lani\"; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module core::math; fn one() -> i32 { return 1; } ",
        "module core::math; fn two() -> i32 { return 2; }",
    ]);
}

#[test]
fn type_checker_accepts_simple_nongeneric_stdlib_seed_modules() {
    for (path, src) in [
        ("stdlib/bool.lani", include_str!("../stdlib/bool.lani")),
        ("stdlib/i32.lani", include_str!("../stdlib/i32.lani")),
        (
            "stdlib/core/bool.lani",
            include_str!("../stdlib/core/bool.lani"),
        ),
        (
            "stdlib/core/char.lani",
            include_str!("../stdlib/core/char.lani"),
        ),
        (
            "stdlib/core/i32.lani",
            include_str!("../stdlib/core/i32.lani"),
        ),
        (
            "stdlib/core/f32.lani",
            include_str!("../stdlib/core/f32.lani"),
        ),
        (
            "stdlib/core/i64.lani",
            include_str!("../stdlib/core/i64.lani"),
        ),
        (
            "stdlib/core/ordering.lani",
            include_str!("../stdlib/core/ordering.lani"),
        ),
        (
            "stdlib/core/panic.lani",
            include_str!("../stdlib/core/panic.lani"),
        ),
        (
            "stdlib/core/u32.lani",
            include_str!("../stdlib/core/u32.lani"),
        ),
        (
            "stdlib/core/u8.lani",
            include_str!("../stdlib/core/u8.lani"),
        ),
        (
            "stdlib/test/assert.lani",
            include_str!("../stdlib/test/assert.lani"),
        ),
    ] {
        common::type_check_source_with_timeout(src)
            .unwrap_or_else(|err| panic!("{path} should pass GPU type checking: {err:?}"));
    }
}

#[test]
fn type_checker_accepts_target_capability_seed_module() {
    assert_gpu_type_check_accepts_with_fresh_compiler(
        "stdlib/core/target.lani",
        include_str!("../stdlib/core/target.lani"),
    );
}

#[test]
fn type_checker_accepts_core_range_seed_module() {
    assert_gpu_type_check_accepts_with_fresh_compiler(
        "stdlib/core/range.lani",
        include_str!("../stdlib/core/range.lani"),
    );
}

#[test]
fn type_checker_accepts_limited_const_array_and_runtime_abi_seed_modules() {
    for (path, src) in [
        (
            "stdlib/core/array_i32.lani",
            include_str!("../stdlib/core/array_i32.lani"),
        ),
        (
            "stdlib/alloc/allocator.lani",
            include_str!("../stdlib/alloc/allocator.lani"),
        ),
        (
            "stdlib/std/env.lani",
            include_str!("../stdlib/std/env.lani"),
        ),
        ("stdlib/std/fs.lani", include_str!("../stdlib/std/fs.lani")),
        ("stdlib/std/io.lani", include_str!("../stdlib/std/io.lani")),
        (
            "stdlib/std/net.lani",
            include_str!("../stdlib/std/net.lani"),
        ),
        (
            "stdlib/std/process.lani",
            include_str!("../stdlib/std/process.lani"),
        ),
        (
            "stdlib/std/time.lani",
            include_str!("../stdlib/std/time.lani"),
        ),
    ] {
        common::type_check_source_with_timeout(src)
            .unwrap_or_else(|err| panic!("{path} should pass GPU type checking: {err:?}"));
    }
}

#[test]
fn type_checker_rejects_stdlib_seed_modules_blocked_by_gpu_semantics() {
    for (path, src) in [
        (
            "stdlib/array_i32_4.lani",
            include_str!("../stdlib/array_i32_4.lani"),
        ),
        (
            "stdlib/core/array_i32_4.lani",
            include_str!("../stdlib/core/array_i32_4.lani"),
        ),
        (
            "stdlib/core/cmp.lani",
            include_str!("../stdlib/core/cmp.lani"),
        ),
        (
            "stdlib/core/hash.lani",
            include_str!("../stdlib/core/hash.lani"),
        ),
        (
            "stdlib/core/option.lani",
            include_str!("../stdlib/core/option.lani"),
        ),
        (
            "stdlib/core/result.lani",
            include_str!("../stdlib/core/result.lani"),
        ),
    ] {
        match common::type_check_source_with_timeout(src) {
            Ok(()) => panic!("{path} should remain rejected by GPU type checking"),
            Err(CompileError::GpuTypeCheck(_)) => {}
            Err(other) => panic!("{path} should fail in GPU type checking, got {other:?}"),
        }
    }
}

#[test]
fn type_checker_accepts_same_source_qualified_type_paths() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

enum Choice {
    Yes,
    No,
}

fn take(point: app::main::Point, choice: app::main::Choice) {
    return;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_same_source_qualified_type_body_flow() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn x_of(point: app::main::Point) -> i32 {
    return point.x;
}

fn copy(point: app::main::Point) -> app::main::Point {
    return point;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_same_source_qualified_local_annotations() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::main::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_unresolved_qualified_local_annotations() {
    assert_gpu_type_check_rejects(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::other::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_unresolved_qualified_type_paths() {
    assert_gpu_type_check_rejects(
        r#"
fn take(value: core::option::Option<i32>) {
    return;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_same_source_qualified_value_calls_only() {
    let scope = include_str!("../shaders/type_checker/type_check_scope.slang");
    let syntax = include_str!("../shaders/parser/syntax_tokens.slang");
    let calls = include_str!("../shaders/type_checker/type_check_calls_03_resolve.slang");

    assert!(
        scope.contains("token_kind(i) == TK_TRAIT")
            && !scope.contains("module_item_kind[i] == MODULE_ITEM_IMPORT"),
        "scope should not reject imports after the module resolver owns import validation"
    );
    assert!(
        syntax.contains("is_qualified_value_call_path")
            && calls.contains("same_source_qualified_value_leaf")
            && calls.contains("qualified_leaf_token"),
        "GPU syntax should only admit call-shaped value paths; GPU type checking must resolve same-source calls without enabling imports"
    );

    assert_gpu_type_check_accepts(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = app::helper();
    return value;
}
"#,
    );
    assert_gpu_type_check_accepts(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::main::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let flag: bool = app::helper();
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn main() {
    return app::missing();
}
"#,
    );
}
