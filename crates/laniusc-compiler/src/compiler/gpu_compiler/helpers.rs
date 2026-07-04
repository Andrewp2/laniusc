use super::*;

/// Caps x86 instruction HIR capacity to the parser tree capacity.
pub(super) fn x86_inst_hir_node_count_for_backend_capacity(
    parser_tree_capacity: u32,
    semantic_hir_count: u32,
) -> u32 {
    semantic_hir_count.max(1).min(parser_tree_capacity.max(1))
}

/// Returns a buffer only when it contains at least `words` 32-bit words.
pub(super) fn buffer_if_wgpu_u32_words(
    buffer: &wgpu::Buffer,
    words: usize,
) -> Option<&wgpu::Buffer> {
    (buffer.size() >= words.saturating_mul(4) as u64).then_some(buffer)
}

/// Caps parser-emitted HIR capacity to the parser tree capacity.
pub(super) fn hir_node_capacity_for_parser_emit(
    parser_tree_capacity: u32,
    parser_emit_len: u32,
) -> u32 {
    parser_emit_len.max(1).min(parser_tree_capacity.max(1))
}

/// Emits a WASM compile trace line when WASM tracing is enabled.
pub(super) fn trace_wasm_compile(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

/// Converts a packed type-mismatch detail code into diagnostic note text.
pub(super) fn type_mismatch_note(detail: u32) -> String {
    if detail == 0 {
        return "change the expression or the annotation so both sides have the same type"
            .to_string();
    }

    let expected = detail / 256;
    let actual = detail % 256;
    if expected == 0 {
        return format!(
            "found {}, but this context requires another type; change the expression or the annotation so they agree",
            type_code_note(actual)
        );
    }

    format!(
        "expected {}, found {}; change the expression or the annotation so they agree",
        type_code_note(expected),
        type_code_note(actual)
    )
}

/// Converts a packed type-mismatch detail code into primary-label text.
pub(super) fn type_mismatch_label(detail: u32) -> String {
    if detail == 0 {
        return "value type does not match this context".to_string();
    }

    let expected = detail / 256;
    let actual = detail % 256;
    if expected == 0 {
        return format!(
            "value type is {}, which is not accepted here",
            type_code_note(actual)
        );
    }

    format!(
        "value type is {} but this context expects {}",
        type_code_note(actual),
        type_code_note(expected)
    )
}

fn type_code_note(code: u32) -> String {
    const TY_UNKNOWN: u32 = 0;
    const TY_VOID: u32 = 1;
    const TY_BOOL: u32 = 2;
    const TY_INT: u32 = 3;
    const TY_UINT: u32 = 4;
    const TY_FLOAT: u32 = 5;
    const TY_CHAR: u32 = 6;
    const TY_STRING: u32 = 7;
    const TY_ARRAY_BASE: u32 = 128;
    const TY_STRUCT_BASE: u32 = 4096;
    const TY_ENUM_BASE: u32 = 6144;
    const TY_GENERIC_BASE: u32 = 8192;

    match code {
        TY_UNKNOWN => "unknown type".to_string(),
        TY_VOID => "void".to_string(),
        TY_BOOL => "bool".to_string(),
        TY_INT => "i32".to_string(),
        TY_UINT => "u32".to_string(),
        TY_FLOAT => "float".to_string(),
        TY_CHAR => "char".to_string(),
        TY_STRING => "str".to_string(),
        code if (TY_ARRAY_BASE..TY_STRUCT_BASE).contains(&code) => {
            let element_code = code - TY_ARRAY_BASE;
            if element_code == TY_UNKNOWN {
                "array".to_string()
            } else {
                format!("array of {}", type_code_note(element_code))
            }
        }
        code if (TY_STRUCT_BASE..TY_ENUM_BASE).contains(&code) => "struct".to_string(),
        code if (TY_ENUM_BASE..TY_GENERIC_BASE).contains(&code) => "enum".to_string(),
        code if code >= TY_GENERIC_BASE => {
            format!("generic parameter {}", code - TY_GENERIC_BASE)
        }
        _ => "an unsupported type".to_string(),
    }
}

/// Prepares already-loaded source text for GPU compiler input.
pub(in crate::compiler) fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

/// Reads source text from disk and prepares it for GPU compiler input.
pub(in crate::compiler) fn prepare_source_for_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    let path = path.as_ref();
    fs::read_to_string(path).map_err(|err| source_input_read_failed(path, err))
}

pub(super) fn source_tokenization_failed_for_source(
    diagnostic_path: &Path,
    source: &str,
    _err: impl std::fmt::Display,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0046", "source tokenization failed")
            .with_primary_label(diagnostic_label_from_source_span(
                diagnostic_path,
                source,
                0,
                source_first_label_len(source),
                "could not tokenize this source file",
            ))
            .with_note(format!("source input path: {}", diagnostic_path.display()))
            .with_note(
                "the lexer could not produce a complete token stream for this source",
            )
            .with_note(
                "try reducing the source size; if this happens on a small file, report a compiler bug",
            ),
    )
}

pub(super) fn source_tokenization_failed_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
    _err: impl std::fmt::Display,
) -> CompileError {
    let diagnostic = Diagnostic::error("LNC0046", "source tokenization failed")
        .with_note(format!("source file count: {}", diagnostic_files.len()))
        .with_note("the lexer could not produce a complete token stream for this source pack")
        .with_note(
            "try reducing the source size; if this happens on a small file, report a compiler bug",
        );

    let Some(file) = diagnostic_files.first() else {
        return CompileError::Diagnostic(diagnostic.with_primary_label(DiagnosticLabel::primary(
            "<source>",
            1,
            1,
            1,
            None,
            "could not tokenize this source input",
        )));
    };

    CompileError::Diagnostic(
        diagnostic.with_primary_label(diagnostic_label_from_source_span(
            &file.path,
            &file.source,
            0,
            source_first_label_len(&file.source),
            "could not tokenize this source file",
        )),
    )
}

pub(super) struct StageExecutionFailure<'a> {
    pub code: &'a str,
    pub message: &'a str,
    pub primary_label: &'a str,
    pub source_help: &'a str,
    pub source_pack_help: &'a str,
}

pub(super) fn stage_execution_failed_for_source(
    failure: StageExecutionFailure<'_>,
    diagnostic_path: &Path,
    source: &str,
    _err: impl std::fmt::Display,
) -> CompileError {
    let (start, len) = first_nonempty_source_span(source);
    CompileError::Diagnostic(
        Diagnostic::error(failure.code, failure.message)
            .with_primary_label(diagnostic_label_from_source_span(
                diagnostic_path,
                source,
                start,
                len,
                failure.primary_label,
            ))
            .with_note(format!("source input path: {}", diagnostic_path.display()))
            .with_note(failure.source_help),
    )
}

pub(super) fn stage_execution_failed_for_source_pack(
    failure: StageExecutionFailure<'_>,
    diagnostic_files: &[DiagnosticSourceFile],
    _err: impl std::fmt::Display,
) -> CompileError {
    let diagnostic = Diagnostic::error(failure.code, failure.message)
        .with_note(format!("source file count: {}", diagnostic_files.len()))
        .with_note(failure.source_pack_help);

    let Some(file) = diagnostic_files.first() else {
        return CompileError::Diagnostic(diagnostic.with_primary_label(DiagnosticLabel::primary(
            "<source pack>",
            1,
            1,
            1,
            None,
            failure.primary_label,
        )));
    };

    let (start, len) = first_nonempty_source_span(&file.source);
    CompileError::Diagnostic(
        diagnostic.with_primary_label(diagnostic_label_from_source_span(
            &file.path,
            &file.source,
            start,
            len,
            failure.primary_label,
        )),
    )
}

pub(super) fn parser_execution_failed_for_source(
    diagnostic_path: &Path,
    source: &str,
    err: impl std::fmt::Display,
) -> CompileError {
    stage_execution_failed_for_source(parser_execution_failure(), diagnostic_path, source, err)
}

pub(super) fn parser_execution_failed_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
    err: impl std::fmt::Display,
) -> CompileError {
    stage_execution_failed_for_source_pack(parser_execution_failure(), diagnostic_files, err)
}

fn parser_execution_failure() -> StageExecutionFailure<'static> {
    StageExecutionFailure {
        code: "LNC0066",
        message: "parser execution failed",
        primary_label: "parser failed before it could report a syntax error",
        source_help: "try reducing the source size; if this happens on a small file, report a compiler bug",
        source_pack_help: "try reducing the source pack; if this happens on a small package, report a compiler bug",
    }
}

fn source_first_label_len(source: &str) -> usize {
    source.chars().next().map(char::len_utf8).unwrap_or(1)
}

pub(super) fn first_nonempty_source_span(source: &str) -> (usize, usize) {
    let start = source
        .char_indices()
        .find(|(_, ch)| !ch.is_whitespace())
        .map(|(index, _)| index)
        .unwrap_or(0);
    let len = source[start..]
        .chars()
        .next()
        .map(char::len_utf8)
        .unwrap_or(1);
    (start, len)
}

fn source_input_read_failed(path: &Path, err: std::io::Error) -> CompileError {
    input_read_failed_error(
        path,
        "read source input",
        "could not read this source file",
        err,
        "create the source file or pass a readable .lani input path",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn type_mismatch_note_decodes_scalar_type_code_record() {
        let detail = 3 * 256 + 2;

        let note = type_mismatch_note(detail);
        assert!(note.contains("expected i32"));
        assert!(note.contains("found bool"));
        assert!(note.contains("change the expression or the annotation"));
        assert!(!note.contains("type code"));

        let label = type_mismatch_label(detail);
        assert!(label.contains("value type is bool"));
        assert!(label.contains("expects i32"));
        assert!(!label.contains("type code"));
    }

    #[test]
    fn type_mismatch_note_preserves_unknown_and_array_code_records() {
        let array_expected = 128 * 256;
        let array_note = type_mismatch_note(array_expected);
        assert!(array_note.contains("expected array"));
        assert!(array_note.contains("found unknown type"));
        assert!(!array_note.contains("type code"));

        let float_note = type_mismatch_note(5);
        assert!(float_note.contains("found float"));
        assert!(float_note.contains("requires another type"));
        assert!(!float_note.contains("type code"));
    }

    #[test]
    fn source_path_read_failure_is_structured_diagnostic() {
        let missing = std::env::temp_dir().join(format!(
            "laniusc_missing_source_{}_{}.lani",
            std::process::id(),
            "input"
        ));
        let _ = std::fs::remove_file(&missing);

        let err = prepare_source_for_gpu_from_path(&missing)
            .expect_err("missing source path should fail before GPU work");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0040");
                assert_eq!(diagnostic.message, "input read failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("input read diagnostic should label the source path");
                assert_eq!(label.path, missing);
                assert_eq!(label.message, "could not read this source file");
                let rendered = diagnostic.render();
                assert!(rendered.contains("error[LNC0040]: input read failed"));
                assert!(rendered.contains("operation: read source input"));
                assert!(rendered.contains("input path:"));
                assert!(rendered.contains("No such file") || rendered.contains("not found"));
                assert!(!rendered.contains("frontend error"));
                assert!(!rendered.contains("GpuFrontend"));
            }
            other => panic!("expected structured input-read diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn source_tokenization_failure_is_structured_diagnostic() {
        let err = source_tokenization_failed_for_source(
            Path::new("bad.lani"),
            "fn main() {}\n",
            "lexer token count unexpectedly exceeds byte capacity: count=9, capacity=4",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0046");
                assert_eq!(diagnostic.message, "source tokenization failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("tokenization diagnostic should label the source path");
                assert_eq!(label.path, PathBuf::from("bad.lani"));
                assert_eq!(label.message, "could not tokenize this source file");
                let rendered = diagnostic.render();
                assert!(rendered.contains("error[LNC0046]: source tokenization failed"));
                assert!(rendered.contains("source input path: bad.lani"));
                assert!(rendered.contains(
                    "the lexer could not produce a complete token stream for this source"
                ));
                assert!(!rendered.contains("lexer error:"));
                assert!(!rendered.contains("token count unexpectedly exceeds byte capacity"));
                assert!(!rendered.contains("frontend error"));
                assert!(!rendered.contains("lex source"));
            }
            other => panic!("expected structured tokenization diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn source_pack_tokenization_failure_omits_internal_detail() {
        let paths = [Some(PathBuf::from("first.lani"))];
        let files = source_pack_diagnostic_files(&["module first;\n"], Some(&paths));

        let err = source_tokenization_failed_for_source_pack(
            &files,
            "lexer token count unexpectedly exceeds byte capacity: count=9, capacity=4",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0046");
                assert_eq!(diagnostic.message, "source tokenization failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("source-pack tokenization diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("first.lani"));
                assert_eq!(label.message, "could not tokenize this source file");
                let rendered = diagnostic.render();
                assert!(rendered.contains("source file count: 1"));
                assert!(rendered.contains(
                    "the lexer could not produce a complete token stream for this source pack"
                ));
                assert!(!rendered.contains("lexer error:"));
                assert!(!rendered.contains("token count unexpectedly exceeds byte capacity"));
                assert!(!rendered.contains("frontend error"));
                assert!(!rendered.contains("lex source"));
            }
            other => {
                panic!("expected structured source-pack tokenization diagnostic, got {other:?}")
            }
        }
    }

    #[test]
    fn parser_execution_failure_for_source_is_structured_diagnostic() {
        let err = parser_execution_failed_for_source(
            Path::new("app.lani"),
            "fn main() { return 0; }\n",
            "status readback failed",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0066");
                assert_eq!(diagnostic.message, "parser execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("parser execution diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("app.lani"));
                assert_eq!(
                    label.message,
                    "parser failed before it could report a syntax error"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("error[LNC0066]: parser execution failed"));
                assert!(rendered.contains("source input path: app.lani"));
                assert!(!rendered.contains("status readback failed"));
                assert!(!rendered.contains("parser error:"));
                assert!(!rendered.contains("syntax error:"));
            }
            other => panic!("expected structured parser execution diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn parser_execution_failure_for_source_pack_is_structured_diagnostic() {
        let paths = [Some(PathBuf::from("first.lani"))];
        let files = source_pack_diagnostic_files(&["module first;\n"], Some(&paths));

        let err = parser_execution_failed_for_source_pack(&files, "status readback failed");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0066");
                assert_eq!(diagnostic.message, "parser execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("parser execution source-pack diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("first.lani"));
                assert_eq!(
                    label.message,
                    "parser failed before it could report a syntax error"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("source file count: 1"));
                assert!(!rendered.contains("status readback failed"));
                assert!(!rendered.contains("parser error:"));
                assert!(!rendered.contains("syntax error:"));
            }
            other => panic!("expected structured parser source-pack diagnostic, got {other:?}"),
        }
    }
}
