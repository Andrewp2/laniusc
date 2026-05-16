use std::{env, fs, io::Write, path::PathBuf};

use laniusc::compiler::{
    compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen,
    compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen,
    compile_source_to_wasm_with_gpu_codegen_from_path,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

fn main() {
    if let Err(err) = run() {
        eprintln!("laniusc: {err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut inputs: Vec<PathBuf> = Vec::new();
    let mut stdlib_paths: Vec<PathBuf> = Vec::new();
    let mut output: Option<PathBuf> = None;
    let mut emit = "wasm".to_string();

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            "--emit" => {
                emit = args
                    .next()
                    .ok_or_else(|| "--emit requires a target".to_string())?;
            }
            "--stdlib" => {
                stdlib_paths
                    .push(PathBuf::from(args.next().ok_or_else(|| {
                        "--stdlib requires a source file path".to_string()
                    })?));
            }
            "-o" | "--out" => {
                output = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| format!("{arg} requires an output path"))?,
                ));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with("--stdlib=") => {
                stdlib_paths.push(PathBuf::from(flag.trim_start_matches("--stdlib=")));
            }
            flag if flag.starts_with('-') => {
                return Err(format!("unknown flag {flag}"));
            }
            path => {
                inputs.push(PathBuf::from(path));
            }
        }
    }

    if emit != "wasm" && emit != "x86_64" {
        return Err(format!(
            "unsupported emit target {emit:?}; accepted targets: wasm, x86_64 (x86_64 currently supports only the direct GPU HIR main-return and resolver-backed scalar-const source-pack slices)"
        ));
    }

    let source_pack_requested = !stdlib_paths.is_empty() || inputs.len() > 1;
    if source_pack_requested && inputs.is_empty() {
        return Err("explicit source-pack compilation requires at least one input file".into());
    }

    let emitted = if source_pack_requested {
        if emit == "wasm" {
            pollster::block_on(compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen(
                &stdlib_paths,
                &inputs,
            ))
            .map_err(|err| err.to_string())?
        } else {
            pollster::block_on(
                compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen(
                    &stdlib_paths,
                    &inputs,
                ),
            )
            .map_err(|err| err.to_string())?
        }
    } else if let Some(input) = inputs.first() {
        if emit == "wasm" {
            pollster::block_on(compile_source_to_wasm_with_gpu_codegen_from_path(input))
                .map_err(|err| err.to_string())?
        } else {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(input))
                .map_err(|err| err.to_string())?
        }
    } else if emit == "wasm" {
        pollster::block_on(compile_source_to_wasm_with_gpu_codegen("let x = 7;\n"))
            .map_err(|err| err.to_string())?
    } else {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
            "fn main() { return 7; }\n",
        ))
        .map_err(|err| err.to_string())?
    };
    if let Some(output) = output {
        fs::write(&output, emitted).map_err(|err| format!("write {}: {err}", output.display()))?;
        #[cfg(unix)]
        if emit != "wasm" {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = fs::metadata(&output)
                .map_err(|err| format!("stat {}: {err}", output.display()))?
                .permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(&output, permissions)
                .map_err(|err| format!("chmod {}: {err}", output.display()))?;
        }
    } else {
        std::io::stdout()
            .write_all(&emitted)
            .map_err(|err| format!("write stdout: {err}"))?;
    }
    Ok(())
}

fn print_help() {
    eprintln!(
        "Usage: laniusc [--emit x86_64|wasm] [--stdlib path]... [-o output] <input.lani> [more-input.lani...]\n\
         Emits the selected target using GPU lexing, GPU parsing, GPU type checking, and GPU emission.\n\
         Repeating --stdlib adds explicitly supplied source-pack files before positional user files; imports are not loaded from the filesystem.\n\
         x86_64 currently supports only the direct GPU HIR main-return and resolver-backed scalar-const source-pack slices and rejects unsupported source shapes through GPU status.\n\
         Without an input file, compiles a tiny built-in sample to stdout."
    );
}
