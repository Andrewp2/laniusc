use std::path::Path;

use crate::{
    cli::{common::CliError, output::CliEmission},
    compiler::{
        EntrySourceRoots,
        compile_entry_to_wasm_with_source_roots,
        compile_entry_to_wasm_with_stdlib,
        compile_entry_to_x86_64_with_source_roots,
        compile_entry_to_x86_64_with_stdlib,
        compile_source_to_wasm_with_gpu_codegen,
        compile_source_to_wasm_with_gpu_codegen_from_path,
        compile_source_to_x86_64_with_gpu_codegen,
        compile_source_to_x86_64_with_gpu_codegen_from_path,
        type_check_entry_with_source_roots,
        type_check_entry_with_stdlib,
        type_check_source_with_gpu_from_path,
    },
};

/// Compiles or checks one entry file using explicit source roots.
pub(super) fn compile_source_root(
    input: &Path,
    roots: &EntrySourceRoots,
    check_only: bool,
    emit: &str,
) -> Result<CliEmission, CliError> {
    if check_only {
        pollster::block_on(type_check_entry_with_source_roots(input, roots))
            .map_err(CliError::from_compile_error)?;
        Ok(CliEmission::Bytes(Vec::new()))
    } else if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_wasm_with_source_roots(input, roots))
                .map_err(CliError::from_compile_error)?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_x86_64_with_source_roots(input, roots))
                .map_err(CliError::from_compile_error)?,
        ))
    }
}

/// Compiles or checks one entry file using a stdlib root.
pub(super) fn compile_stdlib_root(
    input: &Path,
    stdlib_root: &Path,
    check_only: bool,
    emit: &str,
) -> Result<CliEmission, CliError> {
    if check_only {
        pollster::block_on(type_check_entry_with_stdlib(input, stdlib_root))
            .map_err(CliError::from_compile_error)?;
        Ok(CliEmission::Bytes(Vec::new()))
    } else if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_wasm_with_stdlib(input, stdlib_root))
                .map_err(CliError::from_compile_error)?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(input, stdlib_root))
                .map_err(CliError::from_compile_error)?,
        ))
    }
}

/// Compiles or checks one source file in isolation.
pub(super) fn compile_single_file(
    input: &Path,
    check_only: bool,
    emit: &str,
) -> Result<CliEmission, CliError> {
    if check_only {
        pollster::block_on(type_check_source_with_gpu_from_path(input))
            .map_err(CliError::from_compile_error)?;
        Ok(CliEmission::Bytes(Vec::new()))
    } else if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(input))
                .map_err(CliError::from_compile_error)?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(input))
                .map_err(CliError::from_compile_error)?,
        ))
    }
}

/// Compiles the built-in demo source used when no input file is passed.
pub(super) fn compile_default_demo(emit: &str) -> Result<CliEmission, CliError> {
    if emit == "wasm" {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_source_to_wasm_with_gpu_codegen(
                "fn main() { return 7; }\n",
            ))
            .map_err(CliError::from_compile_error)?,
        ))
    } else {
        Ok(CliEmission::Bytes(
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
                "fn main() { return 7; }\n",
            ))
            .map_err(CliError::from_compile_error)?,
        ))
    }
}
