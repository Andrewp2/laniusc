mod common;

use laniusc::{
    compiler::{CompileError, GpuCompiler, type_check_source_pack_with_gpu_using},
    lexer::test_cpu::lex_on_test_cpu,
};

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking:\n{src}"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_accepts(src: &str) {
    common::type_check_source_with_timeout(src)
        .unwrap_or_else(|err| panic!("source should pass GPU type checking: {err:?}"));
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!("source pack should fail GPU type checking"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_accepts(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources).unwrap_or_else(|err| {
        dump_test_cpu_token_context_for_gpu_error(sources, &err);
        panic!("source pack should pass GPU type checking: {err:?}");
    });
}

fn assert_gpu_type_check_pack_accepts_with_fresh_compiler(
    label: &'static str,
    sources: &[&'static str],
) {
    let source_refs = sources.to_vec();
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    common::block_on_gpu_with_timeout(label, async move {
        let compiler = GpuCompiler::new().await?;
        type_check_source_pack_with_gpu_using(&sources, &compiler).await
    })
    .unwrap_or_else(|err| {
        dump_test_cpu_token_context_for_gpu_error(&source_refs, &err);
        panic!("{label} should pass GPU type checking: {err:?}");
    });
}

fn dump_test_cpu_token_context_for_gpu_error(sources: &[&str], err: &CompileError) {
    // Test-only diagnostic: this intentionally uses the named CPU lexer oracle
    // only after a GPU failure, so it is not part of the compiler path.
    let message = match err {
        CompileError::GpuTypeCheck(message) | CompileError::GpuSyntax(message) => message,
        _ => return,
    };
    let Some(token_i) = message
        .split("rejected token ")
        .nth(1)
        .and_then(|rest| rest.split(':').next())
        .and_then(|raw| raw.parse::<usize>().ok())
    else {
        return;
    };
    let joined = sources.concat();
    let Ok(tokens) = lex_on_test_cpu(&joined) else {
        return;
    };
    let start = token_i.saturating_sub(4);
    let end = (token_i + 5).min(tokens.len());
    eprintln!("test CPU lexer token context [{start}..{end}) for GPU error token {token_i}:");
    for i in start..end {
        let token = &tokens[i];
        let text = &joined[token.start..token.start + token.len];
        eprintln!("  #{i}: {:?} {:?}", token.kind, text);
    }
}

fn assert_declares_module_metadata(path: &str, src: &str) {
    assert!(
        src.lines()
            .any(|line| line.trim_start().starts_with("module ")),
        "{path} should remain a module-form stdlib seed"
    );
}

fn assert_module_header_accepts(path: &str, src: &str) {
    let module_header = src
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with("module "))
        .unwrap_or_else(|| panic!("{path} should declare module metadata"));
    assert_gpu_type_check_accepts(module_header);
}

#[test]
fn type_checker_accepts_leading_module_metadata() {
    assert_gpu_type_check_accepts("module app::main;");
    assert_gpu_type_check_accepts("module app::main; fn main() { return 0; }");
}

#[test]
fn type_checker_source_pack_accepts_module_metadata_and_resolved_path_imports() {
    assert_gpu_type_check_pack_accepts(&["module app::main; fn main() { return 0; }"]);
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; fn one() -> i32 { return 1; } ",
        "module app::main; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub fn one() -> i32 { return 1; } ",
        "module app::main; import core::math; fn main() { return 0; }",
    ]);

    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import core::math; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import \"stdlib/core/math.lani\"; fn main() { return 0; }",
    ]);
}

#[test]
fn type_checker_source_pack_resolves_public_type_aliases_on_gpu() {
    assert_gpu_type_check_pack_accepts(&[
        "module core::count; pub type Count = i32;",
        r#"
module app::main;

import core::count;

fn keep(value: Count) -> Count {
    return value;
}

fn main() {
    let imported: Count = keep(1);
    let qualified: core::count::Count = imported;
    return qualified;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_duplicate_declarations_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

fn duplicate() -> i32 { return 1; }
fn duplicate() -> i32 { return 2; }

fn main() { return duplicate(); }
"#]);

    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

type Duplicate = i32;
type Duplicate = bool;

fn main() { return 0; }
"#]);
}

#[test]
fn type_checker_accepts_flat_legacy_stdlib_seed_files() {
    for (path, src) in [
        ("stdlib/bool.lani", include_str!("../stdlib/bool.lani")),
        ("stdlib/i32.lani", include_str!("../stdlib/i32.lani")),
    ] {
        common::type_check_source_with_timeout(src).unwrap_or_else(|err| {
            dump_test_cpu_token_context_for_gpu_error(&[src], &err);
            panic!("{path} should pass GPU type checking: {err:?}");
        });
    }
}

#[test]
fn stdlib_module_seed_headers_are_valid_gpu_metadata() {
    assert_gpu_type_check_accepts(
        "module core::bool; pub fn not(value: bool) -> bool { return value; }",
    );

    for (path, src) in [
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
            "stdlib/core/range.lani",
            include_str!("../stdlib/core/range.lani"),
        ),
        (
            "stdlib/core/target.lani",
            include_str!("../stdlib/core/target.lani"),
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
        assert_declares_module_metadata(path, src);
        assert_module_header_accepts(path, src);
    }
}

#[test]
fn stdlib_seed_files_with_unimplemented_semantics_are_not_short_typecheck_fixtures() {
    for (path, src) in [
        (
            "stdlib/core/cmp.lani",
            include_str!("../stdlib/core/cmp.lani"),
        ),
        (
            "stdlib/core/hash.lani",
            include_str!("../stdlib/core/hash.lani"),
        ),
    ] {
        assert!(
            !src.trim().is_empty()
                && (src.contains("module ")
                    || src.contains("struct ")
                    || src.contains("enum ")
                    || src.contains("fn ")
                    || src.contains("extern ")
                    || src.contains("import ")
                    || src.contains("::")),
            "{path} should remain documented as a stdlib seed, not a timeout-prone GPU type-check fixture"
        );
    }
}

#[test]
fn type_checker_accepts_array_i32_4_seed_files() {
    assert_gpu_type_check_accepts(include_str!("../stdlib/array_i32_4.lani"));
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core::array_i32_4 source-pack seed",
        &[include_str!("../stdlib/core/array_i32_4.lani")],
    );
}

#[test]
fn type_checker_accepts_core_range_source_pack_seed() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core range source-pack seed",
        &[
            include_str!("../stdlib/core/range.lani"),
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = core::range::start_i32(range);
    let end: i32 = core::range::end_i32(range);
    if (core::range::contains_i32(range, 2)) {
        return start;
    }
    return end;
}
"#,
        ],
    );
}

#[test]
fn type_checker_accepts_core_range_method_source_pack_seed() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core range method source-pack seed",
        &[
            include_str!("../stdlib/core/range.lani"),
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let direct_start: i32 = core::range::range_i32(1, 4).start();
    let direct_contains: bool = core::range::range_i32(1, 4).contains(2);
    if (range.contains(2)) {
        return direct_start;
    }
    return end;
}
"#,
        ],
    );
}

#[test]
fn type_checker_rejects_private_cross_module_method_call() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::private_methods;

pub struct Thing {
    value: i32,
}

pub fn make(value: i32) -> Thing {
    return Thing { value: value };
}

impl Thing {
    fn hidden(self) -> i32 {
        return self.value;
    }
}
"#,
        r#"
module app::main;

import core::private_methods;

fn main() {
    let thing: core::private_methods::Thing = core::private_methods::make(1);
    return thing.hidden();
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_duplicate_inherent_methods_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

struct Thing {
    value: i32,
}

impl Thing {
    fn read(self) -> i32 {
        return self.value;
    }

    fn read(self) -> i32 {
        return 0;
    }
}

fn main() {
    let thing: Thing = Thing { value: 1 };
    return thing.read();
}
"#]);
}

#[test]
fn type_checker_accepts_core_ordering_source_pack_seed() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core ordering source-pack seed",
        &[
            include_str!("../stdlib/core/ordering.lani"),
            r#"
module app::main;

import core::ordering;

fn main() {
    let ordering: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    let less: core::ordering::Ordering = core::ordering::Less;
    return 0;
}
"#,
        ],
    );
}

#[test]
fn type_checker_accepts_core_option_and_result_source_pack_seeds() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core option source-pack seed",
        &[include_str!("../stdlib/core/option.lani")],
    );
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core result source-pack seed",
        &[include_str!("../stdlib/core/result.lani")],
    );
}

#[test]
fn type_checker_accepts_qualified_generic_option_and_result_calls() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "qualified generic option/result stdlib calls",
        &[
            include_str!("../stdlib/core/option.lani"),
            include_str!("../stdlib/core/result.lani"),
            r#"
module app::main;

import core::option;
import core::result;

fn option_value() -> i32 {
    let value: core::option::Option<i32> = core::option::Some(1);
    let fallback: i32 = 2;
    let is_some: bool = core::option::is_some(value);
    return core::option::unwrap_or(value, fallback);
}

fn result_value() -> i32 {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    let is_ok: bool = core::result::is_ok(value);
    return core::result::unwrap_or(value, 3);
}

fn main() {
    let left: i32 = option_value();
    let right: i32 = result_value();
    return left;
}
"#,
        ],
    );
}

#[test]
fn type_checker_accepts_same_module_qualified_type_paths_via_gpu_resolution_arrays() {
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
fn type_checker_accepts_qualified_function_calls_via_hir_value_consumer() {
    let calls = include_str!("../shaders/type_checker/type_check_calls_03_resolve.slang");
    let consumer =
        include_str!("../shaders/type_checker/type_check_modules_10h_consume_value_calls.slang");

    assert!(
        !calls.contains("StructuredBuffer<uint> dense_counts")
            && !calls.contains("StructuredBuffer<uint> module_records")
            && !calls.contains("StructuredBuffer<uint> import_records")
            && !calls.contains("token_belongs_to_module_metadata_ast_span")
            && !calls.contains("module_value_path_decl")
            && !calls.contains("same_source_qualified")
            && !calls.contains("qualified_leaf_token"),
        "GPU call resolution should not keep deleted module/import shortcuts or a token-level qualified-call bridge"
    );
    assert!(
        consumer.contains("resolved_value_decl")
            && consumer.contains("decl_token_start")
            && consumer.contains("call_fn_index")
            && consumer.contains("call_return_type")
            && !consumer.contains("ByteAddressBuffer")
            && !consumer.contains("token_words")
            && !consumer.contains("token_kind")
            && !consumer.contains("token_hash")
            && !consumer.contains("same_text"),
        "qualified calls should be consumed from HIR path resolver arrays, not token text lookup"
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
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::math;

pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app::main;

fn main() {
    return core::math::one();
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let code: i32 = std::io::flush_stdout();
    std::io::print_i32(code);
    return code;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    alloc::allocator::dealloc(ptr, 16, 4);
    return 0;
}
"#,
    ]);
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

#[test]
fn type_checker_accepts_stdlib_assertion_helpers_as_qualified_void_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/test/assert.lani"),
        r#"
module app::main;

import test::assert;

fn main() {
    let value: i32 = 7;
    test::assert::eq_i32(value, 7);
    test::assert::is_true(value == 7);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_constants_via_hir_value_consumer() {
    let project_value =
        include_str!("../shaders/type_checker/type_check_modules_10g_project_value_paths.slang");
    let consumer =
        include_str!("../shaders/type_checker/type_check_modules_10i_consume_value_consts.slang");

    assert!(
        project_value.contains("module_value_path_status[owner_token] = resolved_value_status")
            && project_value.contains("module_value_path_expr_head")
            && !project_value.contains("module_value_path_decl_token")
            && !project_value.contains("ByteAddressBuffer"),
        "value status projection should be fail-closed and should not use token-level declaration bridges"
    );
    assert!(
        consumer.contains("resolved_value_decl")
            && consumer.contains("visible_type[const_token]")
            && consumer.contains("visible_type[owner_token]")
            && !consumer.contains("ByteAddressBuffer")
            && !consumer.contains("token_hash")
            && !consumer.contains("same_text"),
        "qualified constants should be consumed from resolver arrays and declaration type outputs"
    );

    assert_gpu_type_check_accepts(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let value: i32 = app::LIMIT;
    return value;
}
"#,
    );
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::i32;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let flag: bool = app::LIMIT;
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    return app::MISSING;
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
    let value: i32 = app::helper;
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_qualified_unit_enum_variants_via_hir_value_consumer() {
    let consumer = include_str!(
        "../shaders/type_checker/type_check_modules_10j_consume_value_enum_units.slang"
    );

    assert!(
        consumer.contains("resolved_value_decl")
            && consumer.contains("decl_parent_type_decl")
            && consumer.contains("HIR_ITEM_KIND_ENUM_VARIANT")
            && consumer.contains("TY_ENUM_BASE + enum_token")
            && !consumer.contains("ByteAddressBuffer")
            && !consumer.contains("source_bytes")
            && !consumer.contains("token_hash")
            && !consumer.contains("same_text"),
        "unit enum variants should be consumed from resolver arrays and parent enum metadata"
    );

    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn main() {
    let value: core::ordering::Ordering = core::ordering::Less;
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn main() {
    let value: bool = core::ordering::Less;
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum MaybeI32 {
    Some(i32),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::MaybeI32 = core::maybe::Some;
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_generic_enum_constructors_via_resolver_arrays() {
    let project_instances =
        include_str!("../shaders/type_checker/type_check_modules_10k_project_type_instances.slang");
    let consume_enum_calls = include_str!(
        "../shaders/type_checker/type_check_modules_10l_consume_value_enum_calls.slang"
    );

    assert!(
        project_instances.contains("resolved_type_decl")
            && project_instances.contains("path_segment_token")
            && project_instances.contains("TYPE_REF_INSTANCE")
            && project_instances.contains("type_instance_decl_token")
            && !project_instances.contains("ByteAddressBuffer")
            && !project_instances.contains("source_bytes")
            && !project_instances.contains("same_text"),
        "generic type instances should project from resolver path records"
    );
    assert!(
        consume_enum_calls.contains("resolved_value_decl")
            && consume_enum_calls.contains("decl_parent_type_decl")
            && consume_enum_calls.contains("GENERIC_ENUM_CTOR_OK")
            && consume_enum_calls.contains("TY_ENUM_BASE + enum_token")
            && !consume_enum_calls.contains("ByteAddressBuffer")
            && !consume_enum_calls.contains("source_bytes")
            && !consume_enum_calls.contains("token_words")
            && !consume_enum_calls.contains("generic_param_list")
            && !consume_enum_calls.contains("same_text"),
        "enum constructor calls should consume resolver arrays and constructor validation state"
    );

    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = Some(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    let value: Maybe<i32> = Some(1);
    return 0;
}
"#]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(true);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some();
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::None(1);
    return 0;
}
"#,
    ]);
}
