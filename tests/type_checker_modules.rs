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
    common::type_check_source_with_timeout(src).unwrap_or_else(|err| {
        dump_test_cpu_token_context_for_gpu_error(&[src], &err);
        panic!("source should pass GPU type checking: {err:?}");
    });
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!(
            "source pack should fail GPU type checking:\n{}",
            sources.join("\n--- source split ---\n")
        ),
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
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub const VALUE: i32 = 1;",
        r#"
module app::main;

import core::math;
import core::math;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import core::math; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import \"stdlib/core/math.lani\"; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import app::main; fn main() { return 0; }",
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
            "stdlib/core/slice.lani",
            include_str!("../stdlib/core/slice.lani"),
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
fn stdlib_trait_seed_files_are_not_short_typecheck_fixtures() {
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
            "{path} should remain a non-trivial stdlib seed, not a shortened type-check fixture"
        );
    }
}

#[test]
fn type_checker_accepts_core_cmp_and_hash_trait_seed_files() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core cmp/hash trait source-pack seeds",
        &[
            include_str!("../stdlib/core/cmp.lani"),
            include_str!("../stdlib/core/hash.lani"),
        ],
    );
}

#[test]
fn type_checker_enforces_stdlib_trait_where_obligations_from_source_pack() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core cmp/hash source-pack where obligations",
        &[
            include_str!("../stdlib/core/cmp.lani"),
            include_str!("../stdlib/core/hash.lani"),
            r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_cmp<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn keep_hash<T>(value: T) -> T where T: core::hash::Hash<T> {
    return value;
}

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let left: i32 = keep_cmp(7);
    let middle: i32 = keep_hash(left);
    let right: i32 = keep_both(middle);
    return right;
}
"#,
        ],
    );
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/cmp.lani"),
        include_str!("../stdlib/core/hash.lani"),
        r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let value: bool = keep_both(true);
    return 0;
}
"#,
    ]);
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
fn type_checker_accepts_core_array_i32_source_pack_seed() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core::array_i32 source-pack seed",
        &[include_str!("../stdlib/core/array_i32.lani")],
    );
}

#[test]
fn type_checker_accepts_core_bool_source_pack_seed() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/bool.lani"),
        r#"
module app::main;

import core::bool;

fn main() {
    let inverted: bool = core::bool::not(false);
    let both: bool = core::bool::and(inverted, true);
    let either: bool = core::bool::or(false, both);
    let changed: bool = core::bool::xor(either, false);
    let same: bool = core::bool::eq(changed, true);
    let numeric: bool = core::bool::from_i32(1);
    if (same && numeric) {
        return 0;
    }
    return 1;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_i32_source_pack_seed() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/i32.lani"),
        r#"
module app::main;

import core::i32;

fn main() {
    let magnitude: i32 = core::i32::saturating_abs(-7);
    let lower: i32 = core::i32::min(magnitude, core::i32::MAX);
    let signed: i32 = core::i32::signum(-3);
    let powered: bool = core::i32::is_power_of_two(8);
    if (powered && signed == -1 && lower == 7) {
        return core::i32::clamp(lower, 0, 7);
    }
    return 1;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_char_and_u32_source_pack_seeds() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/char.lani"),
        include_str!("../stdlib/core/u32.lani"),
        r#"
module app::main;

import core::char;
import core::u32;

fn main() {
    let digit: bool = core::char::is_ascii_digit('7');
    let alpha: bool = core::char::is_ascii_alphabetic('Q');
    let clamped: u32 = core::u32::clamp(9, core::u32::MIN, 7);
    let wrapped: u32 = core::u32::wrapping_add(core::u32::MAX, 1);
    if (digit && alpha && clamped == 7 && wrapped == 0) {
        return 0;
    }
    return 1;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_u8_and_i64_source_pack_seeds() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/u8.lani"),
        include_str!("../stdlib/core/i64.lani"),
        r#"
module app::main;

import core::u8;
import core::i64;

fn main() {
    let ascii: bool = core::u8::is_ascii_digit(57);
    let low: u8 = core::u8::min(9, 4);
    let magnitude: i64 = core::i64::abs(-7);
    let bounded: i64 = core::i64::clamp(magnitude, 0, 5);
    if (ascii && low == 4 && bounded == 5) {
        return 0;
    }
    return 1;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_f32_source_pack_seed() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

fn choose(value: f32) -> f32 {
    let magnitude: f32 = core::f32::abs(value);
    let low: f32 = core::f32::min(magnitude, core::f32::ONE);
    let bounded: f32 = core::f32::clamp(low, core::f32::ZERO, 1.0);
    if (bounded > 0.5) {
        return bounded;
    }
    return core::f32::max(bounded, 0.5);
}

fn main() {
    let value: f32 = choose(-2.0);
    return 0;
}
"#,
    ]);
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
fn type_checker_accepts_core_range_inclusive_method_source_pack_seed() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "core range inclusive method source-pack seed",
        &[
            include_str!("../stdlib/core/range.lani"),
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::RangeInclusive<i32> = core::range::range_inclusive_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let empty: bool = range.is_empty();
    let direct_end: i32 = core::range::range_inclusive_i32(1, 4).end();
    let direct_contains: bool = core::range::range_inclusive_i32(1, 4).contains(4);
    let direct_empty: bool = core::range::range_inclusive_i32(5, 4).is_empty();
    if (range.contains(4) && !empty && !direct_empty) {
        return direct_end;
    }
    return start + end;
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
fn type_checker_accepts_qualified_generic_enum_instance_returns() {
    assert_gpu_type_check_pack_accepts_with_fresh_compiler(
        "qualified generic option replace return",
        &[
            include_str!("../stdlib/core/option.lani"),
            r#"
module app::main;

import core::option;

fn main() {
    let none: core::option::Option<i32> = core::option::None;
    let replaced: core::option::Option<i32> = core::option::replace(none, 11);
    return core::option::unwrap_or(replaced, 0);
}
"#,
        ],
    );
}

#[test]
fn type_checker_rejects_qualified_generic_option_and_result_call_mismatches() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::Some(1);
    return core::option::unwrap_or(value, true);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn main() {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    return core::result::unwrap_or(value, false);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::None;
    let wrong: core::option::Option<bool> = core::option::replace(value, 11);
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_bounded_module_qualified_generic_callees_and_rejects_conflicts() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::keep(1);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    let flag: bool = core::id::keep(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, 2);
}
"#,
    ]);
    // Generic aggregate returns are not in the bounded module-qualified call
    // slice yet. Reject them instead of comparing only the outer Wrapper decl.
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::wrap;

pub struct Wrapper<T> {
    value: T,
}

pub fn wrap<T>(value: T) -> Wrapper<T> {
    return Wrapper { value: value };
}
"#,
        r#"
module app::main;

import core::wrap;

fn main() {
    let wrapped: core::wrap::Wrapper<bool> = core::wrap::wrap(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::wrap;

pub struct Wrapper<T> {
    value: T,
}

pub fn wrap<T>(value: T) -> Wrapper<T> {
    return Wrapper { value: value };
}
"#,
        r#"
module app::main;

import core::wrap;

fn main() {
    let wrapped: core::wrap::Wrapper<i32> = core::wrap::wrap(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, true);
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_module_qualified_generic_array_calls_outside_bounded_slice() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::array;

pub fn first<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}
"#,
        r#"
module app::main;

import core::array;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    return core::array::first(values);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::array;

pub fn copy<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}
"#,
        r#"
module app::main;

import core::array;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = core::array::copy(values);
    return copied[0];
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_source_pack_non_constructor_symbolic_generic_enum_returns() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn wrong<T>(value: T) -> core::option::Option<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
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
fn type_checker_accepts_host_abi_seed_source_pack_modules() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/net.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/time.lani"),
    ]);
}

#[test]
fn type_checker_accepts_host_abi_source_pack_qualified_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/env.lani"),
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/net.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;

import std::env;
import std::fs;
import std::net;
import std::process;
import std::time;

fn main() {
    let args: i32 = std::process::argc();
    let first_arg_len: i32 = std::process::arg_len(0);
    let vars: i32 = std::env::var_count();
    let first_var_len: i32 = std::env::var_key_len(0);
    let file: i32 = std::fs::open_read(0, 0);
    let bytes: i32 = std::fs::read(file, 0, 0);
    let now: i64 = std::time::monotonic_now_ns();
    let slept: i32 = std::time::sleep_ms(0);
    let tcp: i32 = std::net::tcp_connect(0, 0, 80);
    let udp: i32 = std::net::udp_bind(0, 0, 53);
    std::process::set_exit_code(0);
    return args + first_arg_len + vars + first_var_len + file + bytes + slept + tcp + udp;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_alloc_and_io_source_pack_qualified_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::io;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    let grown: u32 = alloc::allocator::realloc(ptr, 16, 32, 4);
    let stdin_count: i32 = std::io::read_stdin(grown, 32);
    let stdout_count: i32 = std::io::write_stdout(grown, 32);
    let stderr_count: i32 = std::io::write_stderr(grown, 32);
    let flushed: i32 = std::io::flush_stderr();
    std::io::print_i32(stdin_count + stdout_count + stderr_count + flushed);
    alloc::allocator::dealloc(grown, 32, 4);
    alloc::allocator::alloc_failed(64, 8);
    return std::io::flush_stdout();
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_direct_host_abi_extern_fixtures() {
    assert_gpu_type_check_accepts(
        r#"
extern "lanius_std" fn argc() -> i32;
extern "lanius_std" fn var_count() -> i32;
extern "lanius_std" fn open_read(path_ptr: u32, path_len: usize) -> i32;
extern "lanius_std" fn monotonic_now_ns() -> i64;
extern "lanius_std" fn tcp_connect(addr_ptr: u32, addr_len: usize, port: i32) -> i32;
extern "lanius_std" fn print_i32(value: i32);

fn main() {
    let args: i32 = argc();
    let vars: i32 = var_count();
    let file: i32 = open_read(0, 0);
    let sock: i32 = tcp_connect(0, 0, 80);
    let now: i64 = monotonic_now_ns();
    print_i32(args + vars + file + sock);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_direct_allocator_abi_extern_fixture() {
    assert_gpu_type_check_accepts(
        r#"
extern "lanius_alloc" fn alloc(size: usize, align: usize) -> u32;
extern "lanius_alloc" fn realloc(ptr: u32, old_size: usize, new_size: usize, align: usize) -> u32;
extern "lanius_alloc" fn dealloc(ptr: u32, size: usize, align: usize);
extern "lanius_alloc" fn alloc_failed(size: usize, align: usize);

fn main() {
    let ptr: u32 = alloc(16, 4);
    let grown: u32 = realloc(ptr, 16, 32, 4);
    dealloc(grown, 32, 4);
    alloc_failed(64, 8);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_core_target_source_pack_seed() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/target.lani"),
        r#"
module app::main;

import core::target;

fn main() {
    let native: bool = core::target::is_native();
    let has_stdio: bool = core::target::HAS_STDIO;
    let threaded: bool = core::target::has_threads();
    if (native && has_stdio && !threaded) {
        return 0;
    }
    return 1;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_panic_source_pack_seed() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/panic.lani"),
        r#"
module app::main;

import core::panic;

fn main() {
    core::panic::unreachable();
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_trait_bounds_via_gpu_module_records() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::missing::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub struct Eq<T> {
    value: T,
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
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
fn type_checker_rejects_private_cross_module_constants() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = core::limits::SECRET;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = SECRET;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_same_module_private_qualified_values() {
    assert_gpu_type_check_accepts(
        r#"
module app;

const SECRET: i32 = 7;

fn helper() -> i32 {
    return app::SECRET;
}

fn main() {
    return app::helper();
}
"#,
    );
}

#[test]
fn type_checker_rejects_private_cross_module_qualified_paths() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

fn hidden() -> i32 {
    return 7;
}
"#,
        r#"
module app::main;

fn main() {
    return core::secret::hidden();
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

struct Hidden {
    value: i32,
}
"#,
        r#"
module app::main;

fn accept(value: core::secret::Hidden) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_names() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub struct Item {
    value: i32,
}
"#,
        r#"
module core::right;

pub struct Item {
    value: i32,
}
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn accept(value: Item) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_unit_enum_variants_via_hir_value_consumer() {
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
