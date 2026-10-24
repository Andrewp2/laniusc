mod common;

use laniusc_compiler::compiler::{CompileError, compile_source_to_x86_64_with_gpu_codegen};

fn reject(source: &str, code: &str, offending_literal: Option<(&str, usize)>) {
    let owned = source.to_owned();
    let error = common::run_gpu_codegen_with_timeout("array repeat context rejection", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&owned))
    })
    .expect_err("invalid array source must not produce an executable");
    let CompileError::Diagnostic(diagnostic) = error else {
        panic!("expected diagnostic {code}, got {error:?}");
    };
    assert_eq!(diagnostic.code, code, "{}", diagnostic.render());
    if let Some((anchor, length)) = offending_literal {
        let start = source.find(anchor).expect("fixture literal anchor");
        let end = start + length;
        let primary = diagnostic.primary_label.as_ref().expect("source label");
        let label_start = primary.byte_start.expect("literal byte start");
        let label_end = primary.byte_end.expect("literal byte end");
        assert!(
            label_start < end && label_end > start,
            "diagnostic must identify the expected literal span: {}",
            diagnostic.render()
        );
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn array_repeat_context_executes_modest_native_arrays() {
    let source = include_str!("fixtures/compiler_array_repeat_context/positive.lani");
    let bytes = common::run_gpu_codegen_with_timeout("array repeat extent contexts", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("repeat counts must be independent of their element types");

    let output = common::run_x86_64_elf_output(
        "array repeat extent contexts",
        "array_repeat_context",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

#[test]
fn array_repeat_context_rejects_unsigned_element_range_errors() {
    for (source, anchor, length) in [
        (
            include_str!("fixtures/compiler_array_repeat_context/u8-positive-overflow.lani"),
            "256; 256",
            3,
        ),
        (
            include_str!("fixtures/compiler_array_repeat_context/u8-negative-element.lani"),
            "1; 256",
            1,
        ),
        (
            include_str!("fixtures/compiler_array_repeat_context/ordinary-u8-overflow.lani"),
            "256, 0",
            3,
        ),
    ] {
        reject(source, "LNC0069", Some((anchor, length)));
    }
}

#[test]
fn array_repeat_context_rejects_signed_element_range_errors() {
    for (source, anchor, length) in [
        (
            include_str!("fixtures/compiler_array_repeat_context/i8-positive-overflow.lani"),
            "128; 128",
            3,
        ),
        (
            include_str!("fixtures/compiler_array_repeat_context/i8-negative-overflow.lani"),
            "129; 128",
            3,
        ),
        (
            include_str!(
                "fixtures/compiler_array_repeat_context/ordinary-i8-negative-overflow.lani"
            ),
            "129, 0",
            3,
        ),
    ] {
        reject(source, "LNC0069", Some((anchor, length)));
    }
}

#[test]
fn array_repeat_context_rejects_reserved_and_oversized_counts() {
    reject(
        include_str!("fixtures/compiler_array_repeat_context/reserved-count.lani"),
        "LNC0006",
        Some(("4294967295]", 10)),
    );
    reject(
        include_str!("fixtures/compiler_array_repeat_context/oversized-count.lani"),
        "LNC0069",
        Some(("4294967296]", 10)),
    );
}

#[test]
fn array_repeat_context_rejects_nonliteral_counts() {
    for source in [
        include_str!("fixtures/compiler_array_repeat_context/named-count.lani"),
        include_str!("fixtures/compiler_array_repeat_context/negative-count.lani"),
        include_str!("fixtures/compiler_array_repeat_context/float-count.lani"),
    ] {
        reject(source, "LNC0016", None);
    }
}

#[test]
fn array_repeat_context_rejects_malformed_and_mismatched_arrays() {
    for source in [
        include_str!("fixtures/compiler_array_repeat_context/after-list.lani"),
        include_str!("fixtures/compiler_array_repeat_context/wrong-length.lani"),
        include_str!("fixtures/compiler_array_repeat_context/wrong-element-type.lani"),
    ] {
        reject(source, "LNC0006", None);
    }
}
