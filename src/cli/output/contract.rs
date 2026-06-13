use std::{fs, path::Path};

use laniusc::{
    codegen::unit::SourcePackArtifactTarget,
    compiler::{GpuSourcePackArtifactDescriptor, GpuSourcePackArtifactStage},
};

use super::{CliOutputError, diagnostics::linked_output_contract_descriptor_diagnostic};

pub(super) fn read_linked_output_contract_descriptor(
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
