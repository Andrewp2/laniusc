mod common;

use laniusc::compiler::{
    CompileError,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

fn assert_x86_64_elf_header(bytes: &[u8]) {
    const ELF64_HEADER_SIZE: usize = 64;
    const ELF64_PROGRAM_HEADER_SIZE: usize = 56;
    const PT_LOAD: u32 = 1;
    const PF_X: u32 = 1;

    fn read_u16(bytes: &[u8], offset: usize) -> u16 {
        u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
    }

    fn read_u32(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
    }

    fn read_u64(bytes: &[u8], offset: usize) -> u64 {
        u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
    }

    assert!(
        bytes.len() >= ELF64_HEADER_SIZE,
        "ELF output too small: {}",
        bytes.len()
    );
    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(read_u16(bytes, 16), 2, "executable ELF type");
    assert_eq!(read_u16(bytes, 18), 62, "x86_64 machine type");

    let entry = read_u64(bytes, 24);
    let program_header_offset =
        usize::try_from(read_u64(bytes, 32)).expect("program header offset should fit usize");
    let elf_header_size = read_u16(bytes, 52) as usize;
    let program_header_size = read_u16(bytes, 54) as usize;
    let program_header_count = read_u16(bytes, 56) as usize;
    assert_eq!(elf_header_size, ELF64_HEADER_SIZE, "ELF header size");
    assert!(
        program_header_size >= ELF64_PROGRAM_HEADER_SIZE,
        "program header entries must be large enough for ELF64"
    );
    assert!(
        program_header_count > 0,
        "ELF output should include at least one program header"
    );
    let program_header_table_size = program_header_size
        .checked_mul(program_header_count)
        .expect("program header table size overflowed");
    let program_header_table_end = program_header_offset
        .checked_add(program_header_table_size)
        .expect("program header table end overflowed");
    assert!(
        program_header_table_end <= bytes.len(),
        "program header table must fit in returned ELF bytes"
    );

    let mut entry_in_executable_segment = false;
    for header_i in 0..program_header_count {
        let base = program_header_offset + header_i * program_header_size;
        let segment_type = read_u32(bytes, base);
        if segment_type != PT_LOAD {
            continue;
        }

        let flags = read_u32(bytes, base + 4);
        let file_offset = read_u64(bytes, base + 8);
        let virtual_address = read_u64(bytes, base + 16);
        let file_size = read_u64(bytes, base + 32);
        let memory_size = read_u64(bytes, base + 40);
        assert!(
            file_size <= memory_size,
            "load segment file size must not exceed memory size"
        );

        let file_end = file_offset
            .checked_add(file_size)
            .expect("load segment file range overflowed");
        let file_end_usize =
            usize::try_from(file_end).expect("load segment file end should fit usize");
        assert!(
            file_end_usize <= bytes.len(),
            "load segment file range must fit in returned ELF bytes"
        );

        let memory_end = virtual_address
            .checked_add(memory_size)
            .expect("load segment memory range overflowed");
        if flags & PF_X != 0 && entry >= virtual_address && entry < memory_end {
            let entry_file_offset = file_offset + (entry - virtual_address);
            assert!(
                entry_file_offset >= file_offset && entry_file_offset < file_end,
                "ELF entry point must map to bytes in the executable segment"
            );
            entry_in_executable_segment = true;
        }
    }
    assert!(
        entry_in_executable_segment,
        "ELF entry point should be inside an executable load segment"
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn assert_x86_exit_code(context: &str, artifact_stem: &str, bytes: &[u8], expected: i32) {
    let output = common::run_x86_64_elf_output(context, artifact_stem, bytes);
    assert_eq!(output.status.code(), Some(expected));
}

fn compile_source(context: &str, source: &str) -> Vec<u8> {
    let source = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"))
}

fn assert_source_exit(name: &str, source: &str, expected: i32) {
    let bytes = compile_source(&format!("x86 source {name}"), source);

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        &format!("x86 source {name}"),
        &format!("x86_source_{name}"),
        &bytes,
        expected,
    );
}

#[test]
fn x86_path_reports_missing_input() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    let _ = std::fs::remove_file(&missing);

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing source path should fail before codegen");
    let message = err.to_string();

    match err {
        CompileError::GpuFrontend(_) => {}
        other => panic!("expected source read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("read") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
}

#[test]
fn x86_executes_representative_scalar_programs() {
    let cases = [
        (
            "integer_arithmetic",
            "fn main() {\n    return 1 + 2 + 3;\n}\n",
            6,
        ),
        (
            "bool_branch",
            "fn main() -> bool {\n    let value: i32 = 4;\n    return value > 3;\n}\n",
            1,
        ),
        (
            "function_call",
            "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(7, 5);\n}\n",
            12,
        ),
        (
            "live_local_after_call",
            "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let left: i32 = 7 + 5;\n    let right: i32 = id(3);\n    return left + right;\n}\n",
            15,
        ),
        (
            "unsigned_compare",
            "fn main() -> bool {\n    let left: u32 = 4294967295;\n    let right: u32 = 1;\n    return left > right;\n}\n",
            1,
        ),
    ];

    for (name, source, expected) in cases {
        assert_source_exit(name, source, expected);
    }
}

#[test]
fn x86_executes_void_main_return_as_zero_exit() {
    assert_source_exit(
        "void_main_return",
        r#"
fn main() {
    return;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_while_loop_with_scalar_local_mutation() {
    assert_source_exit(
        "while_loop_scalar_mutation",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        total += i;
        i += 1;
    }
    return total;
}
"#,
        6,
    );
}

#[test]
fn x86_rejects_nested_loop_with_source_spanned_diagnostic() {
    let source = r#"
fn main() {
    let i: i32 = 0;
    let j: i32 = 0;
    let total: i32 = 0;
    while (i < 3) {
        j = 0;
        while (j < i) {
            total += j;
            j += 1;
        }
        i += 1;
    }
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 nested loop", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("nested loops should fail closed until x86 loop lowering supports them");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "nested-loop rejection should use the stable x86 backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "nested-loop rejection should stay in the native-codegen category: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the nested loop source line");
            assert_eq!(
                source_line, "        while (j < i) {",
                "diagnostic should point at the inner loop: {rendered}"
            );
            let loop_start_column = source_line
                .find("while")
                .map(|column| column + 1)
                .expect("fixture should contain the nested while token");
            let loop_end_column = source_line.len();
            assert!(
                (loop_start_column..=loop_end_column).contains(&label.column),
                "diagnostic column should fall inside the inner loop statement: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_nested_branch_with_scalar_local_mutation() {
    assert_source_exit(
        "nested_branch_scalar_mutation",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 5) {
        if (i < 2) {
            total += 10;
        } else {
            total += i;
        }
        i += 1;
    }
    return total;
}
"#,
        29,
    );
}

#[test]
fn x86_executes_nested_arithmetic_in_branch_conditions_and_bodies() {
    assert_source_exit(
        "nested_arithmetic_in_branches",
        r#"
fn main() {
    let base: i32 = 4;
    let total: i32 = 0;
    if ((base * 3 + 2) > 10) {
        total += (base + 1) * 2;
    } else {
        total += 40;
    }
    if ((total - base) == 6) {
        total += 3 * (base - 1);
    } else {
        total += 70;
    }
    return total;
}
"#,
        19,
    );
}

#[test]
fn x86_executes_scalar_boolean_operators_in_branches() {
    assert_source_exit(
        "scalar_boolean_operators",
        r#"
fn main() {
    let left: bool = true;
    let right: bool = false;
    let total: i32 = 0;
    if (left && !right) {
        total += 4;
    } else {
        total += 40;
    }
    if (right || (total == 4)) {
        total += 3;
    }
    if ((left && right) || false) {
        total += 100;
    } else {
        total += 5;
    }
    return total;
}
"#,
        12,
    );
}

#[test]
fn x86_rejects_non_return_match_expression_with_diagnostic() {
    let source = r#"
fn main() {
    let observed: i32 = match (0) {
        _ -> 7,
    };
    return observed;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 non-return match expression", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "non-return match expressions should fail closed until x86 match lowering broadens",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "match-expression rejection should use the stable x86 diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "match-expression rejection should stay in the native-codegen category: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 match expression")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the unsupported x86 match boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the match source line");
            assert_eq!(
                source_line, "    let observed: i32 = match (0) {",
                "diagnostic should point at the unsupported match expression: {rendered}"
            );
            let match_start_column = source_line
                .find("match")
                .map(|column| column + 1)
                .expect("fixture should contain the match expression");
            let match_end_column = match_start_column + "match".len();
            assert!(
                (match_start_column..=match_end_column).contains(&label.column),
                "diagnostic column should fall inside the match token: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_call_before_eager_lowering() {
    let cases = [
        (
            "and",
            r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && rhs();
}
"#,
            "    return left && rhs();",
        ),
        (
            "or",
            r#"
fn rhs() -> bool {
    return false;
}

fn main() -> bool {
    let left: bool = true;
    return left || rhs();
}
"#,
            "    return left || rhs();",
        ),
    ];

    for (name, source, expected_line) in cases {
        let source = source.to_owned();
        let err = common::run_gpu_codegen_with_timeout(
            &format!("x86 short-circuit RHS call {name}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .expect_err("RHS calls in short-circuit expressions should fail until conditional call lowering exists");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let rendered = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "short-circuit call rejection should use the stable backend diagnostic: {rendered}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "short-circuit call rejection should stay in the native-codegen category: {rendered}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 short-circuit call operand")
                        && rendered.contains("native x86 backend"),
                    "diagnostic should name the short-circuit call boundary: {rendered}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the short-circuit source line");
                assert_eq!(
                    source_line, expected_line,
                    "diagnostic should point at the short-circuit expression: {rendered}"
                );
                let call_start_column = source_line
                    .find("rhs")
                    .map(|column| column + 1)
                    .expect("fixture should contain the RHS call token");
                let call_end_column = source_line
                    .find("();")
                    .map(|column| column + 3)
                    .expect("fixture should contain the RHS call expression");
                assert!(
                    (call_start_column..=call_end_column).contains(&label.column),
                    "diagnostic column should fall inside the RHS call: {rendered}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn x86_rejects_nested_short_circuit_rhs_call_before_eager_lowering() {
    let source = r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && (rhs() == true);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 nested short-circuit RHS call",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "nested RHS calls in short-circuit expressions should fail until conditional call lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "nested short-circuit call rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "nested short-circuit call rejection should stay in the native-codegen category: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit call operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the short-circuit call boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            assert_eq!(
                source_line, "    return left && (rhs() == true);",
                "diagnostic should point at the short-circuit expression: {rendered}"
            );
            let call_start_column = source_line
                .find("rhs")
                .map(|column| column + 1)
                .expect("fixture should contain the RHS call token");
            let call_end_column = source_line
                .find("()")
                .map(|column| column + 2)
                .expect("fixture should contain the RHS call expression");
            assert!(
                (call_start_column..=call_end_column).contains(&label.column),
                "diagnostic column should fall inside the nested RHS call: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_deeply_nested_short_circuit_rhs_call_without_depth_limit() {
    let source = r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && ((((((((rhs() == true) == true) == true) == true) == true) == true) == true) == true);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 deeply nested short-circuit RHS call",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err("short-circuit RHS call rejection should not depend on a fixed parent depth");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "deep short-circuit call rejection should use the stable backend diagnostic: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit call operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the short-circuit call boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            let call_start_column = source_line
                .find("rhs")
                .map(|column| column + 1)
                .expect("fixture should contain the RHS call token");
            let call_end_column = source_line
                .find("()")
                .map(|column| column + 2)
                .expect("fixture should contain the RHS call expression");
            assert!(
                (call_start_column..=call_end_column).contains(&label.column),
                "diagnostic column should fall inside the deeply nested RHS call: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_trapping_arithmetic_before_eager_lowering() {
    let source = r#"
fn main() -> bool {
    let left: bool = false;
    return left && ((12 / 0) == 0);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 short-circuit RHS trapping arithmetic",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "RHS arithmetic that needs trap-aware lowering should fail until conditional lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "short-circuit arithmetic rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "short-circuit arithmetic rejection should stay in native codegen: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit trapping operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should identify the conditional trap-lowering boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            let operand_start = source_line
                .find("12 / 0")
                .map(|column| column + 1)
                .expect("fixture should contain the trapping RHS operand");
            let operand_end = operand_start + "12 / 0".len();
            assert!(
                (operand_start..=operand_end).contains(&label.column),
                "diagnostic column should fall inside the RHS trapping operand: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_dynamic_index_before_eager_lowering() {
    let source = r#"
fn check(index: i32) -> bool {
    let values: [i32; 2] = [1, 2];
    return true || (values[index] == 2);
}

fn main() -> bool {
    return check(1);
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 short-circuit RHS dynamic index", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "RHS dynamic indexing should fail until short-circuit lowering can avoid eager loads",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "short-circuit index rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "short-circuit index rejection should stay in native codegen: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit trapping operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should identify the conditional trap-lowering boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            assert_eq!(
                source_line, "    return true || (values[index] == 2);",
                "diagnostic should point at the short-circuit RHS index expression: {rendered}"
            );
            let index_start = source_line
                .find("index")
                .map(|column| column + 1)
                .expect("fixture should contain the dynamic index operand");
            let index_end = index_start + "index".len();
            assert!(
                (index_start..=index_end).contains(&label.column),
                "diagnostic column should fall inside the dynamic index operand: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_scalar_div_mod_bitwise_and_shift_ops() {
    assert_source_exit(
        "scalar_div_mod_bitwise_shift_ops",
        r#"
fn main() {
    let value: i32 = 27;
    let quotient: i32 = value / 3;
    let remainder: i32 = value % 4;
    let flags: i32 = (6 & 3) | (8 >> 1);
    let shifted: i32 = (1 << -(1 - 4)) ^ 2;
    return quotient * 10 + remainder + flags + shifted;
}
"#,
        109,
    );
}

#[test]
fn x86_emits_runtime_checked_dynamic_shift_counts() {
    let source = r#"
fn shift_by(amount: i32) -> i32 {
    return 1 << amount;
}

fn main() {
    let amount: i32 = 32;
    return shift_by(amount);
}
"#
    .to_owned();

    let bytes = common::run_gpu_codegen_with_timeout("x86 dynamic shift count", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("dynamic shift counts should compile with a generated runtime range check");

    assert_x86_64_elf_header(&bytes);
}

#[test]
fn x86_rejects_shaped_divisor_until_runtime_trap_lowering_exists() {
    let source = r#"
fn main() {
    return 12 / (1 + 2);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 shaped divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("shaped divisors should fail until native lowering inserts trap checks");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "shaped-divisor rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the divisor trap-check boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 / (1 + 2);"),
                "diagnostic should point at the shaped divisor expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_dynamic_divisor_until_runtime_trap_lowering_exists() {
    let source = r#"
fn divide(value: i32, divisor: i32) -> i32 {
    return value / divisor;
}

fn main() {
    return divide(12, 3);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 dynamic divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("dynamic divisors should fail until native lowering inserts trap checks");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the divisor trap-check boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return value / divisor;"),
                "diagnostic should point at the dynamic divisor expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_mutated_local_literal_divisor_until_runtime_trap_lowering_exists() {
    let source = r#"
fn main() {
    let divisor: i32 = 3;
    divisor = 0;
    return 12 / divisor;
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 mutated local literal divisor", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "mutable local literals should not prove divisor safety after later assignments",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the divisor trap-check boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 / divisor;"),
                "diagnostic should point at the divisor use, not the original let literal: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_negative_one_divisor_until_signed_overflow_check_exists() {
    let source = r#"
fn divide(value: i32) -> i32 {
    return value / -1;
}

fn main() {
    return divide(7);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 negative-one divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("negative-one divisors should fail until native lowering handles i32 MIN overflow");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the signed-divisor trap-check boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return value / -1;"),
                "diagnostic should point at the negative-one divisor expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_scalar_compound_assignment_ops() {
    assert_source_exit(
        "scalar_compound_assignment_ops",
        r#"
fn main() {
    let value: i32 = 48;
    value /= 3;
    value %= 5;
    value |= 8;
    value &= 11;
    value ^= 2;
    value <<= 1;
    value >>= 2;
    value -= 1;
    value *= 3;
    return value;
}
"#,
        12,
    );
}

#[test]
fn x86_executes_four_argument_call_with_mixed_argument_sources() {
    assert_source_exit(
        "four_argument_call_mixed_sources",
        r#"
fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {
    return first * 10 + second * 3 + third - fourth;
}

fn main() {
    let local: i32 = 4;
    let other: i32 = 6;
    return mix(local, 2 + 1, other, 5);
}
"#,
        50,
    );
}

#[test]
fn x86_executes_bool_returning_helper_call_in_branch_condition() {
    assert_source_exit(
        "bool_returning_helper_call_branch_condition",
        r#"
fn between(value: i32, low: i32, high: i32) -> bool {
    return value > low && value < high;
}

fn main() {
    if (between(7, 3, 10)) {
        return 9;
    } else {
        return 1;
    }
}
"#,
        9,
    );
}

#[test]
fn x86_executes_while_break_and_continue() {
    assert_source_exit(
        "while_break_continue",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 8) {
        i += 1;
        if (i == 3) {
            continue;
        }
        if (i > 5) {
            break;
        }
        total += i;
    }
    return total;
}
"#,
        12,
    );
}

#[test]
fn x86_executes_for_array_with_break_and_continue() {
    assert_source_exit(
        "for_array_break_continue",
        r#"
fn main() {
    let values: [i32; 6] = [1, 2, 3, 4, 5, 6];
    let total: i32 = 0;
    for value in values {
        if (value == 2) {
            continue;
        }
        if (value == 5) {
            break;
        }
        total += value;
    }
    return total;
}
"#,
        8,
    );
}

#[test]
fn x86_rejects_struct_for_iterable_without_record_with_diagnostic() {
    let source = r#"
struct Range {
    start: i32,
    end: i32,
}

fn main() {
    let range: Range = Range { start: 1, end: 5 };
    let total: i32 = 0;
    for value in range {
        total += value;
    }
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 struct for iterable", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "struct for iterables should fail until x86 lowering consumes an explicit iterable record",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "struct for-iterable rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "struct for-iterable rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 for iterable"),
                "diagnostic should identify the native iterable boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    for value in range {"),
                "diagnostic should point at the unsupported for statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_scalar_for_iterable_with_diagnostic() {
    let source = r#"
fn main() {
    let limit: i32 = 3;
    let total: i32 = 0;
    for value in limit {
        total += value;
    }
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 scalar for iterable", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "scalar for iterables should fail closed until x86 iteration lowering supports them",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "scalar for-iterable rejection should use the stable x86 diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("x86") && diagnostic.message.contains("iterable"),
                "diagnostic should identify the native iterable boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    for value in limit {"),
                "diagnostic should point at the unsupported for statement: {message}"
            );
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the source line");
            assert!(
                (1..=source_line.len()).contains(&label.column),
                "diagnostic column should fall inside the for statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_array_literal_index_sum() {
    assert_source_exit(
        "array_literal_index_sum",
        r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 3) {
        total += values[i];
        i += 1;
    }
    return total;
}
"#,
        6,
    );
}

#[test]
fn x86_executes_bounded_aggregate_copy_as_value() {
    assert_source_exit(
        "bounded_aggregate_copy_value",
        r#"
fn main() {
    let original: [i32; 3] = [4, 5, 6];
    let copied: [i32; 3] = original;
    copied[1] += 10;
    return original[1] * 10 + copied[1];
}
"#,
        65,
    );
}

#[test]
fn x86_executes_struct_literal_field_mutation_and_copy() {
    assert_source_exit(
        "struct_literal_field_mutation_copy",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() {
    let pair: Pair = Pair { left: 7, right: 5 };
    pair.right += 10;
    let copied: Pair = pair;
    return copied.left * 10 + copied.right;
}
"#,
        85,
    );
}

#[test]
fn x86_executes_struct_parameter_member_reads() {
    assert_source_exit(
        "struct_parameter_member_reads",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn score(pair: Pair) -> i32 {
    return pair.left * 10 + pair.right;
}

fn main() {
    let pair: Pair = Pair { left: 4, right: 7 };
    return score(pair);
}
"#,
        47,
    );
}

#[test]
fn x86_compiles_source_pack_struct_literal_return_from_helper_like_names() {
    let sources = [
        r#"
module core::i32;

pub struct WrappingMul {
    value: i32,
    rhs: i32,
}

pub fn wrapping_mul(value: i32, rhs: i32) -> WrappingMul {
    return WrappingMul { value: value, rhs: rhs };
}
"#,
        r#"
module app::main;

import core::i32;

fn main() {
    let computed: core::i32::WrappingMul = core::i32::wrapping_mul(7, 5);
    return computed.value + computed.rhs;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack struct literal helper-like names",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack struct literal return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
}

#[test]
fn x86_rejects_parameter_aggregate_member_assignment_with_diagnostic() {
    let source = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn rewrite(pair: Pair) -> i32 {
    pair.left = 5;
    return pair.left;
}

fn main() {
    let pair: Pair = Pair { left: 1, right: 2 };
    return rewrite(pair);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 parameter aggregate member assignment",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "parameter aggregate member assignments should fail closed until writable aggregate-parameter lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "parameter aggregate assignment rejection should use the stable backend diagnostic: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the aggregate assignment line");
            assert!(
                source_line.contains("pair.left = 5"),
                "diagnostic should point at the unsupported member assignment: {message}"
            );
            let member_start = source_line
                .find("pair.left")
                .map(|column| column + 1)
                .expect("fixture should contain the assigned member");
            let member_end = member_start + "pair.left".len();
            assert!(
                (member_start..=member_end).contains(&label.column),
                "diagnostic column should fall inside the assigned member path: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_parameter_aggregate_indexed_assignment_with_diagnostic() {
    let source = r#"
fn rewrite(values: [i32; 3]) -> i32 {
    values[1] = 9;
    return values[1];
}

fn main() {
    let values: [i32; 3] = [1, 2, 3];
    return rewrite(values);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 parameter aggregate indexed assignment",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "parameter aggregate indexed assignments should fail closed until writable aggregate-parameter lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "parameter aggregate indexed assignment rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 parameter aggregate indexed assignment")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the indexed aggregate-parameter boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the aggregate indexed assignment line");
            assert!(
                source_line.contains("values[1] = 9"),
                "diagnostic should point at the unsupported indexed assignment: {message}"
            );
            let index_start = source_line
                .find("values[1]")
                .map(|column| column + 1)
                .expect("fixture should contain the indexed assignment target");
            let index_end = index_start + "values[1]".len();
            assert!(
                (index_start..=index_end).contains(&label.column),
                "diagnostic column should fall inside the indexed assignment target: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_indexed_assignment_with_dynamic_index() {
    assert_source_exit(
        "indexed_assignment_dynamic_index",
        r#"
fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let index: i32 = 1;
    values[index] = values[2] + 5;
    values[3] += values[index];
    return values[0] + values[1] + values[2] + values[3];
}
"#,
        24,
    );
}

#[test]
fn x86_executes_indexed_assignment_inside_loop_branch() {
    assert_source_exit(
        "indexed_assignment_loop_branch",
        r#"
fn main() {
    let values: [i32; 4] = [0, 10, 20, 30];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        if (i == 1) {
            values[i] += 5;
        } else {
            values[i] = values[i] + i;
        }
        total += values[i];
        i += 1;
    }
    return total;
}
"#,
        70,
    );
}

#[test]
fn x86_rejects_static_out_of_bounds_array_index_before_native_memory_access() {
    let cases = [(
        "literal_read",
        r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    return values[3];
}
"#,
        "    return values[3];",
    )];

    for (name, source, expected_line) in cases {
        let source = source.to_owned();
        let err = common::run_gpu_codegen_with_timeout(
            &format!("x86 static out-of-bounds array index {name}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .expect_err("known out-of-bounds array indexes should fail before native memory access");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "array-index rejection should use the stable backend diagnostic: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 array index bounds")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the static array-index boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                assert_eq!(
                    label.source_line.as_deref(),
                    Some(expected_line),
                    "diagnostic should point at the out-of-bounds index expression: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn x86_traps_local_literal_array_index_through_runtime_bounds_check() {
    assert_source_exit(
        "local_literal_array_index_runtime_bounds_check",
        r#"
fn main() {
    let values: [i32; 2] = [7, 8];
    let index: i32 = 3;
    return values[index];
}
"#,
        101,
    );
}

#[test]
fn x86_executes_parameter_array_index_with_runtime_bounds_check() {
    assert_source_exit(
        "parameter_array_index_runtime_bounds_check",
        r#"
fn pick(values: [i32; 2], index: i32) -> i32 {
    return values[index];
}

fn main() {
    let values: [i32; 2] = [7, 8];
    return pick(values, 1);
}
"#,
        8,
    );
}

#[test]
fn x86_traps_mutated_local_array_index_out_of_bounds() {
    assert_source_exit(
        "mutated_local_array_index_out_of_bounds",
        r#"
fn main() {
    let values: [i32; 2] = [7, 8];
    let index: i32 = 0;
    index = 3;
    return values[index];
}
"#,
        101,
    );
}

#[test]
fn x86_rejects_aggregate_temporary_index_with_diagnostic() {
    let source = r#"
fn values() -> [i32; 2] {
    return [4, 5];
}

fn main() {
    return values()[1];
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 aggregate temporary index", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("aggregate temporaries should fail closed until indexed temporary lowering exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate temporary index rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate temporary index rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate temporary index")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the aggregate temporary index boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the indexed temporary source line");
            let index_start = source_line
                .find("[1]")
                .map(|column| column + 1)
                .expect("fixture should contain the index expression");
            assert!(
                (1..index_start).contains(&label.column),
                "diagnostic column should point at the aggregate source before the index: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_return_temporary_member_with_diagnostic() {
    let source = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn pair() -> Pair {
    return Pair { left: 4, right: 5 };
}

fn main() {
    return pair().left;
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 aggregate return temporary member", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "aggregate temporaries should fail closed until member temporary lowering exists",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate temporary member rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate temporary member rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate temporary member")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the aggregate temporary member boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the member temporary source line");
            assert_eq!(
                source_line, "    return pair().left;",
                "diagnostic should point at the aggregate temporary member expression: {message}"
            );
            let member_start = source_line
                .find(".left")
                .map(|column| column + 1)
                .expect("fixture should contain the member access");
            assert!(
                (1..member_start).contains(&label.column),
                "diagnostic column should point at the aggregate source before the member: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_copy_above_bounded_gpu_row_width() {
    let elements = (0..33)
        .map(|value| value.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    let source = format!(
        r#"
fn main() {{
    let a: [i32; 33] = [{elements}];
    let b: [i32; 33] = a;
    return b[0];
}}
"#
    );

    let err = common::run_gpu_codegen_with_timeout("x86 oversized aggregate copy", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("oversized aggregate copies should fail before virtual row generation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate copy width")
                    && message.contains("native x86 backend"),
                "diagnostic should name the aggregate row-width boundary: {message}"
            );
            assert!(
                message.contains("let b: [i32; 33] = a;"),
                "diagnostic should point at the oversized aggregate copy: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_postfix_increment_before_silent_noop() {
    let source = r#"
fn main() {
    let i: i32 = 0;
    i++;
    return i;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 postfix increment", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("postfix expressions should fail closed until x86 lowering supports them");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 postfix expression")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the postfix-expression boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    i++;"),
                "diagnostic should point at the unsupported postfix statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_prefix_increment_before_silent_noop() {
    let source = r#"
fn main() {
    let i: i32 = 0;
    ++i;
    return i;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 prefix increment", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("prefix increment should fail closed until x86 lowering supports read/write rows");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 unary expression")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the unsupported unary-expression boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    ++i;"),
                "diagnostic should point at the unsupported prefix statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_compile_time_zero_divisor_before_native_fault() {
    let source = r#"
fn main() {
    return 12 / 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 compile-time zero divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("statically known zero divisors should fail before native idiv can fault");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 zero divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the zero-divisor boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 / 0;"),
                "diagnostic should point at the division expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_mutable_local_zero_divisor_as_dynamic_until_runtime_trap_lowering_exists() {
    let source = r#"
fn main() {
    let scale: i32 = 0;
    return 12 % scale;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 mutable local zero divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "mutable local literal divisors should fail closed until runtime trap lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the divisor trap-check boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 % scale;"),
                "diagnostic should point at the mutable divisor use: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_unsupported_five_argument_call_in_codegen() {
    let source = r#"
fn add5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    return a + b + c + d + e;
}

fn main() {
    return add5(1, 2, 3, 4, 5);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 five argument call", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("five-argument direct calls should fail before x86 ABI support exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert!(
                message.contains("error[LNC0017]")
                    && message.contains("unsupported x86 call ABI")
                    && message.contains("native x86 backend"),
                "codegen rejection should be rendered as an x86 diagnostic: {message}"
            );
            assert!(
                message.contains("return add5(1, 2, 3, 4, 5);"),
                "diagnostic should include the source line for the unsupported call: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_unsupported_five_argument_call_with_diagnostic() {
    let sources = [
        "module core::math;\npub fn add5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {\n    return a + b + c + d + e;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::add5(1, 2, 3, 4, 5);\n}\n",
    ];

    let err =
        common::run_gpu_codegen_with_timeout("x86 source pack five argument call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect_err("source-pack five-argument direct calls should fail with an x86 diagnostic");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "source-pack x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI")
                    && message.contains("native x86 backend"),
                "source-pack x86 rejection should identify the native x86 boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return core::math::add5(1, 2, 3, 4, 5);"),
                "diagnostic should point at the calling source-pack file: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_assignment_mismatch_reports_lnc0006_diagnostic() {
    let sources = [
        "module core::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    let value: i32 = false;\n    return core::math::identity(value);\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout(
        "x86 source pack assignment mismatch diagnostic",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect_err("source-pack assignment mismatch should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0006",
                "source-pack x86 type-check rejection should use the stable mismatch diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("type mismatch"),
                "source-pack x86 diagnostic should identify the type mismatch: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    let value: i32 = false;"),
                "diagnostic should point at the mismatched source-pack file line: {message}"
            );
            assert!(
                message.contains("expected a different type here")
                    && message.contains("= note:")
                    && !message.contains("GPU type check rejected"),
                "diagnostic should match the single-source type mismatch style: {message}"
            );
        }
        CompileError::GpuTypeCheck(message) => {
            panic!("expected source-pack x86 diagnostic, got GPU type-check error: {message}")
        }
        other => panic!("expected source-pack x86 type mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_unresolved_identifier_reports_lnc0005_diagnostic() {
    let sources = [
        "module core::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return missing_value;\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout(
        "x86 source pack unresolved identifier diagnostic",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect_err("source-pack unresolved identifier should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0005",
                "source-pack x86 type-check rejection should use the stable unresolved identifier diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unresolved identifier"),
                "source-pack x86 diagnostic should identify the unresolved identifier: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return missing_value;"),
                "diagnostic should point at the unresolved identifier source-pack file line: {message}"
            );
            assert!(
                message.contains("not found in this scope")
                    && message.contains(
                        "declare the value before using it or import its defining module"
                    )
                    && !message.contains("GPU type check rejected"),
                "diagnostic should match the single-source unresolved identifier style: {message}"
            );
        }
        CompileError::GpuTypeCheck(message) => {
            panic!("expected source-pack x86 diagnostic, got GPU type-check error: {message}")
        }
        other => panic!("expected source-pack x86 unresolved identifier diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_rejects_direct_recursive_call_before_lowering() {
    let source = r#"
fn countdown(n: i32) -> i32 {
    if (n <= 0) {
        return 0;
    }
    return countdown(n - 1);
}

fn main() {
    return countdown(3);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 direct recursive call", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("direct recursion should fail closed until x86 stack frames are real call frames");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "codegen rejection should be an x86 diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 recursive call")
                    && message.contains("native x86 backend"),
                "recursive call rejection should identify the native x86 boundary: {message}"
            );
            assert!(
                message.contains("return countdown(n - 1);"),
                "diagnostic should include the recursive call site: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_missing_main_entrypoint_with_diagnostic() {
    let source = "fn helper() -> i32 {\n    return 1;\n}\n".to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 missing main entrypoint", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("missing main should fail closed before entry selection");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "missing-main rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "missing-main rejection should stay in the native-codegen category: {message}"
            );
            assert!(
                diagnostic.message.contains("missing main entrypoint")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native entrypoint boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn helper() -> i32 {"),
                "diagnostic should anchor to the source when no main token exists: {message}"
            );
            assert!(
                label.line > 0 && label.column > 0,
                "diagnostic should include a concrete source span: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_empty_entrypoint_body_with_diagnostic() {
    let source = "fn main() -> i32 {\n}\n".to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 empty entrypoint body", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("empty entrypoint bodies should fail before x86 entry selection");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "codegen rejection should be an x86 diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 entrypoint body")
                    && message.contains("native x86 backend"),
                "entrypoint-body rejection should identify the native x86 boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn main() -> i32 {"),
                "diagnostic should point at the entrypoint source line: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_empty_entrypoint_body_with_diagnostic() {
    let sources = [
        "module helpers::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport helpers::math;\nfn main() -> i32 {\n}\n",
    ];

    let err =
        common::run_gpu_codegen_with_timeout("x86 source pack empty entrypoint body", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect_err("source-pack empty entrypoint bodies should fail with an x86 diagnostic");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "source-pack entrypoint rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 entrypoint body")
                    && message.contains("native x86 backend"),
                "entrypoint-body rejection should identify the native x86 boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn main() -> i32 {"),
                "diagnostic should point at the source-pack entrypoint declaration: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_unsupported_method_call_in_codegen() {
    let source = r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn start(self) -> i32 {
        return self.start;
    }
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    return range.start();
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 method call", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("method calls should fail before x86 method lowering exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert!(
                message.contains("error[LNC0017]")
                    && message.contains("unsupported x86 method call")
                    && message.contains("native x86 backend"),
                "codegen rejection should be rendered as an x86 diagnostic: {message}"
            );
            assert!(
                message.contains("return range.start();"),
                "diagnostic should include the source line for the unsupported method call: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_loop_condition_call_before_codegen_timeout() {
    let source = r#"
fn keep_going(value: i32) -> bool {
    return value < 2;
}

fn main() {
    let i: i32 = 0;
    while (keep_going(i)) {
        i += 1;
    }
    return i;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 loop condition call", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("calls inside loop subtrees should fail closed until loop call lowering exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert!(
                message.contains("error[LNC0017]")
                    && message.contains("unsupported x86 loop-contained call")
                    && message.contains("native x86 backend"),
                "codegen rejection should be rendered as a specific x86 diagnostic: {message}"
            );
            assert!(
                message.contains("while (keep_going(i)) {"),
                "diagnostic should include the loop condition call: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_loop_body_assignment_call_before_codegen_timeout() {
    let source = r#"
fn inc(value: i32) -> i32 {
    return value + 1;
}

fn main() {
    let i: i32 = 0;
    while (i < 2) {
        i = inc(i);
    }
    return i;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 loop body assignment call", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("loop-body calls should fail closed until loop call lowering exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "codegen rejection should be an x86 diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 loop-contained call")
                    && message.contains("native x86 backend"),
                "codegen rejection should identify the native x86 loop-call boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the source line");
            let call_start_column = source_line
                .find("inc")
                .map(|offset| offset + 1)
                .expect("fixture should contain the call token");
            let call_end_column = source_line
                .find(");")
                .map(|offset| offset + 2)
                .expect("fixture should contain the end of the call expression");
            assert_eq!(
                source_line, "        i = inc(i);",
                "diagnostic should include the loop-body assignment call: {message}"
            );
            assert!(
                (call_start_column..=call_end_column).contains(&label.column),
                "diagnostic should point into the call expression, not the assignment target: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_stdout_runtime_call_until_runtime_binding_exists() {
    let sources = [
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let a: i32 = 1 + 2 * 3;
    let b: i32 = (1 + 2) * 3;
    if (a < b) {
        std::io::print_i32(a);
    }
    std::io::print_i32(b);
    return 0;
}
"#,
    ];

    let err = common::run_gpu_codegen_with_timeout("x86 stdout runtime call", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect_err("stdio calls should fail closed until the x86 runtime/linker binding exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "stdio runtime rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "stdio runtime rejection should stay in the native-codegen category: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the unbound native call boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("        std::io::print_i32(a);"),
                "diagnostic should point at the first stdio runtime call: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_source_pack_qualified_scalar_const_return() {
    let sources = [
        "module core::numbers;\npub const LIMIT: i32 = 21;\npub const STEP: i32 = 6;\npub const DIVISOR: i32 = 3;\n",
        "module app::main;\nimport core::numbers;\nfn main() {\n    return (12 / core::numbers::DIVISOR) + core::numbers::LIMIT + core::numbers::STEP;\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack qualified scalar const", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack qualified scalar const should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack qualified scalar const",
        "x86_source_pack_qualified_scalar_const",
        &bytes,
        31,
    );
}

#[test]
fn x86_executes_source_pack_function_call() {
    let sources = [
        "module core::math;\npub fn abs(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    } else {\n        return value;\n    }\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::abs(-7);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack function call", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack function call",
        "x86_source_pack_call",
        &bytes,
        7,
    );
}

#[test]
fn x86_executes_source_pack_four_argument_helper_call() {
    let sources = [
        "module core::math;\npub fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {\n    return first * 10 + second * 3 + third - fourth;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    let local: i32 = 4;\n    let other: i32 = 6;\n    return core::math::mix(local, 2 + 1, other, 5);\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack four argument call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack four-argument helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack four argument call",
        "x86_source_pack_four_arg_call",
        &bytes,
        50,
    );
}

#[test]
fn x86_executes_source_pack_aggregate_return_helper_call() {
    let sources = [
        "module core::pairs;\npub fn pair(left: i32, right: i32) -> [i32; 2] {\n    return [left, right];\n}\n",
        "module app::main;\nimport core::pairs;\nfn main() {\n    let values: [i32; 2] = core::pairs::pair(8, 9);\n    return values[0] * 10 + values[1];\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack aggregate return call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack aggregate-return helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack aggregate return call",
        "x86_source_pack_aggregate_return_call",
        &bytes,
        89,
    );
}

#[test]
fn x86_executes_source_pack_locals_live_across_consecutive_calls() {
    let sources = [
        "module helpers::calls;\npub fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {\n    return first * 7 + second * 5 + third * 3 + fourth;\n}\npub fn bump(value: i32) -> i32 {\n    return value + 2;\n}\n",
        "module app::main;\nimport helpers::calls;\nfn main() {\n    let anchor: i32 = 11;\n    let left: i32 = helpers::calls::mix(1, 2, 3, 4);\n    let right: i32 = helpers::calls::bump(anchor);\n    return left + right + anchor;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack locals live across consecutive calls",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack consecutive helper calls should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack locals live across consecutive calls",
        "x86_source_pack_call_liveness",
        &bytes,
        54,
    );
}

#[test]
fn x86_executes_source_pack_array_param_helper_with_loop_and_branch() {
    let sources = [
        r#"
module helpers::fold;
pub fn weighted_sum(values: [i32; 4], bias: i32) -> i32 {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        let term: i32 = values[i] * (i + 1);
        if ((term + bias) > 10) {
            total += term - bias;
        } else {
            total += term + bias;
        }
        i += 1;
    }
    return total;
}
"#,
        r#"
module app::main;
import helpers::fold;
fn main() {
    let numbers: [i32; 4] = [2, 3, 4, 5];
    return helpers::fold::weighted_sum(numbers, 2);
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack array parameter loop helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack array-parameter helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack array parameter loop helper",
        "x86_source_pack_array_param_loop_helper",
        &bytes,
        40,
    );
}

#[test]
fn x86_executes_stdlib_helper_from_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_digit(53);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack stdlib helper", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("stdlib helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack stdlib helper",
        "x86_stdlib_helper",
        &bytes,
        1,
    );
}

#[test]
fn x86_reads_source_from_path() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 0;\n}\n");

    let path = src_path.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("x86 source path", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(&path))
    })
    .expect("source path should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 source path", "x86_source_path", &bytes, 0);
}
