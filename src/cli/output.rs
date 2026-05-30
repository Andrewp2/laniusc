use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use laniusc::{
    codegen::unit::SourcePackArtifactTarget,
    compiler::{
        Diagnostic,
        DiagnosticLabel,
        GpuSourcePackArtifactDescriptor,
        GpuSourcePackArtifactStage,
    },
};

pub(crate) enum CliEmission {
    Bytes(Vec<u8>),
    ContractDescriptorFile(PathBuf),
}

#[derive(Debug)]
pub(crate) enum CliOutputError {
    Diagnostic(Diagnostic),
    Message(String),
}

impl From<String> for CliOutputError {
    fn from(value: String) -> Self {
        Self::Message(value)
    }
}

impl std::fmt::Display for CliOutputError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Diagnostic(diagnostic) => write!(f, "{diagnostic}"),
            Self::Message(message) => f.write_str(message),
        }
    }
}

pub(crate) fn write_cli_emission(
    emitted: CliEmission,
    output: Option<PathBuf>,
    emit: &str,
) -> Result<(), CliOutputError> {
    match emitted {
        CliEmission::Bytes(bytes) => {
            if let Some(output) = output {
                fs::write(&output, bytes).map_err(|err| {
                    output_write_diagnostic(&output, emit, "write target bytes", err)
                })?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                write_stdout_bytes(emit, "write target bytes", &bytes)?;
            }
        }
        CliEmission::ContractDescriptorFile(path) => {
            let bytes = read_linked_output_contract_descriptor(&path, emit)?;
            if let Some(output) = output {
                fs::write(&output, bytes).map_err(|err| {
                    output_write_diagnostic(
                        &output,
                        emit,
                        "write linked-output contract descriptor",
                        err,
                    )
                })?;
            } else {
                write_stdout_bytes(
                    emit,
                    format!(
                        "stream linked-output contract descriptor {}",
                        path.display()
                    ),
                    &bytes,
                )?;
            }
        }
    }
    Ok(())
}

fn write_stdout_bytes(
    emit: &str,
    operation: impl Into<String>,
    bytes: &[u8],
) -> Result<(), CliOutputError> {
    let operation = operation.into();
    let mut stdout = std::io::stdout();
    write_output_stream_bytes("stdout", emit, &operation, &mut stdout, bytes)
}

fn write_output_stream_bytes<W: Write>(
    stream: &str,
    emit: &str,
    operation: &str,
    writer: &mut W,
    bytes: &[u8],
) -> Result<(), CliOutputError> {
    writer
        .write_all(bytes)
        .map_err(|err| output_stream_write_diagnostic(stream, emit, operation, err))?;
    writer.flush().map_err(|err| {
        output_stream_write_diagnostic(stream, emit, format!("flush after {operation}"), err)
    })?;
    Ok(())
}

fn read_linked_output_contract_descriptor(
    path: &Path,
    emit: &str,
) -> Result<Vec<u8>, CliOutputError> {
    let bytes = fs::read(path).map_err(|err| {
        CliOutputError::Diagnostic(
            linked_output_contract_descriptor_diagnostic(path, emit).with_note(format!(
                "could not read linked-output contract descriptor: {err}"
            )),
        )
    })?;
    if let Some(kind) = executable_magic_kind(&bytes) {
        return Err(CliOutputError::Diagnostic(
            linked_output_contract_descriptor_diagnostic(path, emit)
                .with_note(format!("descriptor payload contains {kind} target bytes"))
                .with_note(
                    "descriptor mode expects JSON linked-output contract metadata".to_string(),
                ),
        ));
    }
    let descriptor =
        serde_json::from_slice::<GpuSourcePackArtifactDescriptor>(&bytes).map_err(|err| {
            CliOutputError::Diagnostic(
                linked_output_contract_descriptor_diagnostic(path, emit).with_note(format!(
                    "descriptor payload is not valid JSON contract metadata: {err}"
                )),
            )
        })?;
    descriptor
        .validate_contract_for(
            GpuSourcePackArtifactStage::LinkedOutput,
            expected_contract_target(emit),
        )
        .map_err(|err| {
            CliOutputError::Diagnostic(
                linked_output_contract_descriptor_diagnostic(path, emit).with_note(format!(
                    "descriptor contract is not valid for --emit {emit}: {err}"
                )),
            )
        })?;
    Ok(bytes)
}

fn linked_output_contract_descriptor_diagnostic(path: &Path, emit: &str) -> Diagnostic {
    Diagnostic::error("LNC0022", "linked-output contract descriptor")
        .with_primary_label(DiagnosticLabel::primary(
            path,
            1,
            1,
            1,
            None,
            "linked-output contract descriptor here",
        ))
        .with_note(format!(
            "expected linked-output JSON contract descriptor for --emit {emit}"
        ))
}

fn expected_contract_target(emit: &str) -> Option<SourcePackArtifactTarget> {
    match emit {
        "wasm" => Some(SourcePackArtifactTarget::Wasm),
        "x86_64" => Some(SourcePackArtifactTarget::X86_64),
        _ => None,
    }
}

fn executable_magic_kind(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x7fELF") {
        return Some("ELF executable");
    }
    if bytes.starts_with(b"\0asm") {
        return Some("Wasm module");
    }
    None
}

fn output_write_diagnostic(
    output: &Path,
    emit: &str,
    operation: &str,
    err: std::io::Error,
) -> CliOutputError {
    CliOutputError::Diagnostic(
        Diagnostic::error("LNC0034", "output write failed")
            .with_primary_label(DiagnosticLabel::primary(
                output,
                1,
                1,
                1,
                None,
                "requested output path here",
            ))
            .with_help("choose a writable output path or omit -o/--out to write bytes to stdout")
            .with_note(format!("{operation} for --emit {emit} failed: {err}")),
    )
}

fn output_stream_write_diagnostic(
    stream: &str,
    emit: &str,
    operation: impl Into<String>,
    err: std::io::Error,
) -> CliOutputError {
    let operation = operation.into();
    let error_kind = format!("{:?}", err.kind());
    CliOutputError::Diagnostic(
        Diagnostic::error("LNC0035", "output stream write failed")
            .with_help("keep the output stream open or pass -o/--out to write to a file")
            .with_note(format!("output stream: {stream}"))
            .with_note(format!("operation: {operation}"))
            .with_note(format!("emit mode: {emit}"))
            .with_note(format!("I/O error kind: {error_kind}"))
            .with_note(format!("I/O error: {err}")),
    )
}

fn mark_output_executable_if_needed(output: &Path, emit: &str) -> Result<(), CliOutputError> {
    #[cfg(unix)]
    if emit != "wasm" {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(output)
            .map_err(|err| output_write_diagnostic(output, emit, "stat output file", err))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(output, permissions)
            .map_err(|err| output_write_diagnostic(output, emit, "mark output executable", err))?;
    }
    #[cfg(not(unix))]
    let _ = (output, emit);
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        env,
        fs,
        io,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;

    #[test]
    fn contract_file_emission_copies_without_marking_executable() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-file-emission-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create file emission root");
        let linked_output = root.join("linked-output.bin");
        let output = root.join("out.bin");
        fs::write(
            &linked_output,
            br#"{
  "version": 1,
  "target": "X86_64",
  "stage": "LinkedOutput",
  "job_index": 0,
  "phase": "Link",
  "library_id": 0,
  "first_source_index": 0,
  "source_file_count": 1,
  "source_bytes": 1,
  "source_lines": 1,
  "dependency_interface_count": 0,
  "dependency_codegen_object_count": 1,
  "dependency_partial_link_count": 0,
  "dependency_interface_batch_count": 0,
  "record_arrays": []
}"#,
        )
        .expect("write linked-output contract descriptor");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&linked_output, fs::Permissions::from_mode(0o644))
                .expect("set contract input permissions");
        }

        write_cli_emission(
            CliEmission::ContractDescriptorFile(linked_output.clone()),
            Some(output.clone()),
            "x86_64",
        )
        .expect("copy contract file emission");

        let copied = fs::read(&output).expect("read copied output");
        assert!(copied.starts_with(b"{"));
        assert!(String::from_utf8_lossy(&copied).contains("\"stage\": \"LinkedOutput\""));
        assert!(!copied.starts_with(b"\x7fELF"));
        assert!(linked_output.is_file());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&output)
                .expect("stat output")
                .permissions()
                .mode();
            assert_eq!(
                mode & 0o111,
                0,
                "contract output must not be chmodded executable"
            );
        }

        fs::remove_dir_all(&root).expect("remove temp file emission root");
    }

    #[test]
    fn byte_emission_output_path_failure_is_structured_diagnostic() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-output-error-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create output error root");

        let err = write_cli_emission(
            CliEmission::Bytes(b"target bytes".to_vec()),
            Some(root.clone()),
            "wasm",
        )
        .expect_err("writing bytes to a directory path should fail");

        let CliOutputError::Diagnostic(diagnostic) = err else {
            panic!("output write failure should be a diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0034");
        assert_eq!(diagnostic.category, "tooling");
        assert_eq!(
            diagnostic
                .primary_label
                .as_ref()
                .expect("output diagnostic should label the requested path")
                .path,
            root
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("output diagnostic should include public recovery help")
                .contains("-o/--out")
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note.contains("--emit wasm")),
            "diagnostic should preserve the requested emit mode"
        );

        fs::remove_dir_all(root).expect("remove temp output error root");
    }

    #[test]
    fn stdout_emission_failure_is_structured_diagnostic() {
        let err = output_stream_write_diagnostic(
            "stdout",
            "wasm",
            "write target bytes",
            io::Error::from(io::ErrorKind::BrokenPipe),
        );

        let CliOutputError::Diagnostic(diagnostic) = err else {
            panic!("stdout write failure should be a diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0035");
        assert_eq!(diagnostic.category, "tooling");
        assert!(
            diagnostic.primary_label.is_none(),
            "stream failures are intentionally spanless"
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("stream diagnostic should include public recovery help")
                .contains("-o/--out")
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "output stream: stdout"),
            "stream diagnostic should preserve stream context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "emit mode: wasm"),
            "stream diagnostic should preserve emit context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "operation: write target bytes"),
            "stream diagnostic should preserve operation context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "I/O error kind: BrokenPipe"),
            "stream diagnostic should preserve stable I/O error kind"
        );
    }

    #[derive(Default)]
    struct FlushFailsWriter {
        bytes: Vec<u8>,
    }

    impl io::Write for FlushFailsWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.bytes.extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::from(io::ErrorKind::BrokenPipe))
        }
    }

    #[test]
    fn stdout_emission_flush_failure_is_structured_diagnostic() {
        let mut writer = FlushFailsWriter::default();
        let err =
            write_output_stream_bytes("stdout", "wasm", "write target bytes", &mut writer, b"wasm")
                .expect_err("flush failure should fail the stdout emission");

        assert_eq!(writer.bytes.as_slice(), b"wasm");
        let CliOutputError::Diagnostic(diagnostic) = err else {
            panic!("stdout flush failure should be a diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0035");
        assert_eq!(diagnostic.category, "tooling");
        assert!(
            diagnostic.primary_label.is_none(),
            "stream failures are intentionally spanless"
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("stream diagnostic should include public recovery help")
                .contains("-o/--out")
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "output stream: stdout"),
            "flush diagnostic should preserve stream context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "emit mode: wasm"),
            "flush diagnostic should preserve emit context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "operation: flush after write target bytes"),
            "flush diagnostic should preserve operation context"
        );
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "I/O error kind: BrokenPipe"),
            "flush diagnostic should preserve stable I/O error kind"
        );
    }

    #[test]
    fn contract_descriptor_emission_rejects_executable_bytes() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-contract-magic-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create contract magic root");
        let linked_output = root.join("linked-output.contract");
        let output = root.join("out");
        fs::write(&linked_output, b"\x7fELFnot-a-contract").expect("write fake elf");

        let err = write_cli_emission(
            CliEmission::ContractDescriptorFile(linked_output.clone()),
            Some(output.clone()),
            "x86_64",
        )
        .expect_err("descriptor-mode output must reject executable bytes");

        let CliOutputError::Diagnostic(diagnostic) = err else {
            panic!("descriptor-mode rejection should be a diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0022");
        assert_eq!(diagnostic.category, "native codegen");
        assert_eq!(
            diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should label the linked output")
                .path,
            linked_output
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("descriptor diagnostic should include public help")
                .contains("target bytes")
        );
        assert!(!diagnostic.notes.is_empty());
        assert!(
            !output.exists(),
            "rejected contract output must not leave a runnable-looking file"
        );

        fs::remove_dir_all(&root).expect("remove temp contract magic root");
    }

    #[test]
    fn contract_descriptor_emission_rejects_incoherent_json_descriptor() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-contract-shape-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create contract shape root");
        let linked_output = root.join("linked-output.contract");
        let output = root.join("out");
        fs::write(
            &linked_output,
            br#"{
  "version": 1,
  "target": "X86_64",
  "stage": "LinkedOutput",
  "job_index": 0,
  "phase": "Codegen",
  "library_id": 0,
  "first_source_index": 0,
  "source_file_count": 1,
  "source_bytes": 1,
  "source_lines": 1,
  "dependency_interface_count": 0,
  "dependency_codegen_object_count": 1,
  "dependency_partial_link_count": 0,
  "dependency_interface_batch_count": 0,
  "record_arrays": []
}"#,
        )
        .expect("write incoherent linked-output descriptor");

        let err = write_cli_emission(
            CliEmission::ContractDescriptorFile(linked_output.clone()),
            Some(output.clone()),
            "x86_64",
        )
        .expect_err("descriptor-mode output must reject incoherent contract JSON");

        let CliOutputError::Diagnostic(diagnostic) = err else {
            panic!("descriptor-mode rejection should be a diagnostic");
        };
        assert_eq!(diagnostic.code, "LNC0022");
        assert_eq!(diagnostic.category, "native codegen");
        assert_eq!(
            diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should label the linked output")
                .path,
            linked_output
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .expect("descriptor diagnostic should include public help")
                .contains("target bytes")
        );
        assert!(!diagnostic.notes.is_empty());
        assert!(
            !output.exists(),
            "rejected contract output must not leave a runnable-looking file"
        );

        fs::remove_dir_all(&root).expect("remove temp contract shape root");
    }
}
