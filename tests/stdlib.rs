use std::{
    fs,
    path::{Path, PathBuf},
};

mod common;

use laniusc::{
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
            "{name}: stdlib source should define public functions or constants"
        );
        let is_module_source = hir
            .items
            .iter()
            .any(|item| matches!(item, HirItem::Module(_)));
        for item in hir.items {
            match item {
                HirItem::Import(_) => {
                    panic!("{name}: stdlib source should not contain import items")
                }
                HirItem::Module(_) => {
                    assert!(
                        is_module_source,
                        "{name}: module item should only appear in module-form stdlib sources"
                    );
                }
                HirItem::Fn(func) => assert!(func.public, "{name}: {} should be pub", func.name),
                HirItem::ExternFn(func) => {
                    assert!(func.public, "{name}: extern fn {} should be pub", func.name)
                }
                HirItem::Const(konst) => {
                    if is_module_source {
                        assert!(konst.public, "{name}: {} should be pub", konst.name);
                    } else {
                        assert!(
                            konst.name.starts_with("LSTD_"),
                            "{name}: {} should use the stdlib constant prefix",
                            konst.name
                        );
                    }
                }
                HirItem::TypeAlias(alias) => {
                    assert!(
                        alias.public,
                        "{name}: type alias {} should be public",
                        alias.name
                    )
                }
                HirItem::Enum(enm) => {
                    assert!(enm.public, "{name}: enum {} should be public", enm.name)
                }
                HirItem::Struct(strukt) => assert!(
                    strukt.public,
                    "{name}: struct {} should be public",
                    strukt.name
                ),
                HirItem::Impl(implementation) => {
                    assert!(
                        implementation.public,
                        "{name}: impl block should be public in stdlib sources"
                    );
                    for method in implementation.methods {
                        assert!(
                            method.public,
                            "{name}: impl method {} should be public",
                            method.name
                        );
                    }
                }
                HirItem::Trait(trait_item) => {
                    assert!(
                        trait_item.public,
                        "{name}: trait {} should be public",
                        trait_item.name
                    );
                    for method in trait_item.methods {
                        assert!(
                            method.public,
                            "{name}: trait method {} should be public",
                            method.name
                        );
                    }
                }
                HirItem::Stmt(_) => panic!("{name}: stdlib source should not contain statements"),
            }
        }
    }
}

#[test]
fn stdlib_generic_enum_seeds_type_check_on_gpu() {
    for relative in ["core/option.lani", "core/result.lani"] {
        let path = stdlib_root().join(relative);
        common::type_check_path_with_timeout(&path)
            .unwrap_or_else(|err| panic!("{} should type-check on GPU: {err}", path.display()));
    }
}

#[test]
fn stdlib_generic_sum_type_annotations_type_check_on_gpu() {
    let src = r#"
import core::option;
import core::result;

fn keep_option(value: core::option::Option<i32>) -> core::option::Option<i32> {
    return value;
}

fn make_option(value: i32) -> core::option::Option<i32> {
    return core::option::Some(value);
}

fn empty_option() -> core::option::Option<i32> {
    return core::option::None;
}

fn keep_result(value: core::result::Result<i32, bool>) -> core::result::Result<i32, bool> {
    return value;
}

fn ok_result(value: i32) -> core::result::Result<i32, bool> {
    return core::result::Ok(value);
}

fn err_result(flag: bool) -> core::result::Result<i32, bool> {
    return core::result::Err(flag);
}

fn main() {
    let some: core::option::Option<i32> = make_option(7);
    let none: core::option::Option<i32> = empty_option();
    let ok: core::result::Result<i32, bool> = ok_result(1);
    let err: core::result::Result<i32, bool> = err_result(false);
    let some_flag: bool = core::option::is_some(some);
    let none_flag: bool = core::option::is_none(none);
    let ok_flag: bool = core::result::is_ok(ok);
    let err_flag: bool = core::result::is_err(err);
    let some_value: i32 = core::option::unwrap_or(some, 0);
    let none_value: i32 = core::option::unwrap_or(none, 5);
    let ok_value: i32 = core::result::unwrap_or(ok, 0);
    let err_value: i32 = core::result::unwrap_or(err, 9);
    if (some_flag && none_flag && ok_flag && err_flag) {
        return some_value + none_value + ok_value + err_value;
    }
    return 0;
}
"#;

    parse_source(src).expect("generic sum type annotation usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("generic sum type annotation usage should type-check");
}

#[test]
fn stdlib_type_checks_ordering_compare_seed_usage() {
    let src = r#"
import core::ordering;

fn main() {
    let order: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    return 0;
}
"#;

    parse_source(src).expect("ordering compare seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("ordering compare seed usage should type-check");
}

#[test]
fn stdlib_type_checks_cmp_trait_seed_usage() {
    let src = r#"
import core::cmp;

fn main() {
    let left: i32 = 3;
    let right: i32 = 5;
    let same: bool = left.eq(left);
    let different: bool = left.ne(right);
    let ordered: bool = left.lt(right);
    if (same && different && ordered) {
        return 1;
    }
    return 0;
}
"#;

    parse_source(src).expect("cmp trait seed usage should parse as HIR");
    common::type_check_source_with_timeout(src).expect("cmp trait seed usage should type-check");
}

#[test]
fn stdlib_type_checks_cmp_trait_bound_seed_usage() {
    let src = r#"
import core::cmp;

fn same<T: core::cmp::Eq<T>>(left: T, right: T) -> bool {
    return left.eq(right);
}

fn main() {
    return 0;
}
"#;

    parse_source(src).expect("cmp trait bound seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("cmp trait bound seed usage should type-check");
}

#[test]
fn stdlib_type_checks_multiple_trait_bound_seed_usage() {
    let src = r#"
import core::cmp;
import core::hash;

fn same_hash<T: core::cmp::Eq<T> + core::hash::Hash<T>>(left: T, right: T) -> bool {
    let same: bool = left.eq(right);
    let left_hash: u32 = left.hash();
    let right_hash: u32 = right.hash();
    return same && left_hash == right_hash;
}

fn main() {
    return 0;
}
"#;

    parse_source(src).expect("multiple trait bound seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("multiple trait bound seed usage should type-check");
}

#[test]
fn stdlib_type_checks_range_i32_seed_usage() {
    let src = r#"
import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(2, 8);
    let start: i32 = core::range::start_i32(range);
    let end: i32 = core::range::end_i32(range);
    let contains: bool = core::range::contains_i32(range, 5);
    let empty: bool = core::range::is_empty_i32(range);
    let method_start: i32 = range.start();
    let method_contains: bool = range.contains(method_start);
    let total: i32 = 0;
    for index in range {
        total += index;
    }
    if (contains && method_contains && !empty) {
        return start + end + method_start + total;
    }
    return 0;
}
"#;

    parse_source(src).expect("range i32 seed usage should parse as HIR");
    common::type_check_source_with_timeout(src).expect("range i32 seed usage should type-check");
}

#[test]
fn stdlib_type_checks_target_capability_seed_usage() {
    let src = r#"
import core::target;

fn main() {
    let native: bool = core::target::is_native();
    let clock: bool = core::target::HAS_CLOCK;
    if (native && clock) {
        return 1;
    }
    return 0;
}
"#;

    parse_source(src).expect("target capability seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("target capability seed usage should type-check");
}

#[test]
fn stdlib_type_checks_module_primitive_seed_usage() {
    let src = r#"
import core::i32;
import core::u32;
import core::u8;
import core::bool;

fn main() {
    let absolute: i32 = core::i32::saturating_abs(-7);
    let added: u32 = core::u32::saturating_add(1, 2);
    let byte: u8 = core::u8::saturating_add(64, 1);
    let in_range: bool = core::i32::between_inclusive(absolute, 0, core::i32::MAX);
    let ascii: bool = core::u8::is_ascii_uppercase(byte);
    let ok: bool = core::bool::and(in_range, ascii);
    if (ok) {
        return absolute;
    }
    return 0;
}
"#;

    parse_source(src).expect("module primitive seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("module primitive seed usage should type-check");
}

#[test]
fn stdlib_type_checks_representative_import_usage() {
    let src = r#"
import "stdlib/i32.lani";
import "stdlib/bool.lani";
import "stdlib/array_i32_4.lani";

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = lstd_i32x4_copy(values);
    let reversed: [i32; 4] = lstd_i32x4_reversed(copied);
    let filled: [i32; 4] = lstd_i32x4_filled(reversed[0]);
    let total: i32 = lstd_i32x4_sum(filled);
    let found: bool = lstd_i32x4_contains(reversed, 4);
    let bounded: bool = lstd_i32_between_inclusive(total, 0, LSTD_I32_MAX);
    let ok: bool = lstd_bool_and(found, bounded);
    if (ok) {
        return lstd_i32_clamp(total, 0, 10);
    }
    return 0;
}
"#;

    parse_source(src).expect("representative stdlib usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("representative stdlib usage should type-check");
}

#[test]
fn stdlib_type_checks_array_i32_4_array_return_seed_usage() {
    let src = r#"
import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = core::array_i32_4::copy(values);
    let reversed: [i32; 4] = core::array_i32_4::reversed(copied);
    let filled: [i32; 4] = core::array_i32_4::filled(reversed[0]);
    return core::array_i32_4::sum(filled);
}
"#;

    parse_source(src).expect("core array_i32_4 array return usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("core array_i32_4 array return usage should type-check");
}

#[test]
fn stdlib_type_checks_test_assert_seed_usage() {
    let src = r#"
import test::assert;

fn main() {
    test::assert::is_true(true);
    test::assert::eq_i32(7, 7);
    return 0;
}
"#;

    parse_source(src).expect("test assertion seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("test assertion seed usage should type-check");
}

#[test]
fn stdlib_type_checks_core_panic_seed_usage() {
    let src = r#"
import core::panic;

fn main() {
    core::panic::panic();
    return 0;
}
"#;

    parse_source(src).expect("core panic seed usage should parse as HIR");
    common::type_check_source_with_timeout(src).expect("core panic seed usage should type-check");
}

#[test]
fn stdlib_type_checks_core_slice_seed_usage() {
    let src = r#"
import core::slice;

fn use_slice(values: [i32]) -> i32 {
    let first: i32 = core::slice::first_i32(values);
    return core::slice::get_or_i32(values, 4, 2, first);
}

fn main() {
    return 0;
}
"#;

    parse_source(src).expect("core slice seed usage should parse as HIR");
    common::type_check_source_with_timeout(src).expect("core slice seed usage should type-check");
}

#[test]
fn stdlib_type_checks_alloc_allocator_seed_usage() {
    let src = r#"
import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    let grown: u32 = alloc::allocator::realloc(ptr, 16, 32, 4);
    alloc::allocator::dealloc(grown, 32, 4);
    return 0;
}
"#;

    parse_source(src).expect("alloc allocator seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("alloc allocator seed usage should type-check");
}

#[test]
fn stdlib_type_checks_std_io_seed_usage() {
    let src = r#"
import std::io;

fn main() {
    let written: i32 = std::io::write_stdout(0, 4);
    std::io::print_i32(written);
    return written;
}
"#;

    parse_source(src).expect("std io seed usage should parse as HIR");
    common::type_check_source_with_timeout(src).expect("std io seed usage should type-check");
}

#[test]
fn stdlib_type_checks_const_generic_array_i32_seed_usage() {
    let src = r#"
import core::array_i32;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let first: i32 = core::array_i32::first(values);
    let third: i32 = core::array_i32::get_unchecked(values, 2);
    return first + third;
}
"#;

    parse_source(src).expect("core array_i32 seed usage should parse as HIR");
    common::type_check_source_with_timeout(src)
        .expect("core array_i32 seed usage should type-check");
}
