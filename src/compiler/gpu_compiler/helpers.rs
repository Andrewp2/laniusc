use super::*;

pub(super) fn x86_inst_hir_node_count_for_backend_capacity(
    parser_tree_capacity: u32,
    semantic_hir_count: u32,
) -> u32 {
    semantic_hir_count.max(1).min(parser_tree_capacity.max(1))
}

pub(super) fn buffer_if_wgpu_u32_words(
    buffer: &wgpu::Buffer,
    words: usize,
) -> Option<&wgpu::Buffer> {
    (buffer.size() >= words.saturating_mul(4) as u64).then_some(buffer)
}

pub(super) fn hir_node_capacity_for_parser_emit(
    parser_tree_capacity: u32,
    parser_emit_len: u32,
) -> u32 {
    parser_emit_len.max(1).min(parser_tree_capacity.max(1))
}

pub(super) fn trace_wasm_compile(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

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

pub(in crate::compiler) fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

pub(in crate::compiler) fn prepare_source_for_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    fs::read_to_string(path.as_ref()).map_err(|err| {
        CompileError::GpuFrontend(format!("read {}: {err}", path.as_ref().display()))
    })
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
}
