use std::{
    env,
    fs,
    io,
    time::{SystemTime, UNIX_EPOCH},
};

use laniusc::{
    codegen::unit::{SourcePackArtifactTarget, SourcePackJob, SourcePackJobPhase},
    compiler::GpuSourcePackArtifactDescriptor,
};

use super::{
    CliEmission,
    CliOutputError,
    diagnostics::output_stream_write_diagnostic,
    stream::write_output_stream_bytes,
    write_cli_emission,
};

fn linked_output_descriptor_json() -> Vec<u8> {
    let job = SourcePackJob {
        job_index: 0,
        phase: SourcePackJobPhase::Link,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 0,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::X86_64,
        &job,
        0,
        1,
    );
    serde_json::to_vec_pretty(&descriptor).expect("serialize valid linked-output descriptor")
}

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
    fs::write(&linked_output, linked_output_descriptor_json())
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
