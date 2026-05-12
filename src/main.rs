use std::{env, fs, io::Write, path::PathBuf};

use laniusc::compiler::{
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
    let mut input: Option<PathBuf> = None;
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
            "-o" | "--out" => {
                output = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| format!("{arg} requires an output path"))?,
                ));
            }
            flag if flag.starts_with("--emit=") => {
                emit = flag.trim_start_matches("--emit=").to_string();
            }
            flag if flag.starts_with('-') => {
                return Err(format!("unknown flag {flag}"));
            }
            path => {
                if input.replace(PathBuf::from(path)).is_some() {
                    return Err("only one input file is supported right now".into());
                }
            }
        }
    }

    if emit != "wasm" && emit != "x86_64" {
        return Err(format!(
            "unsupported emit target {emit:?}; accepted targets: wasm, x86_64 (x86_64 currently reports unavailable)"
        ));
    }

    let emitted = if let Some(input) = &input {
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
        "Usage: laniusc [--emit x86_64|wasm] [-o output] <input.lani>\n\
         Emits WASM using GPU lexing, GPU parsing, GPU type checking, and GPU emission.\n\
         x86_64 is accepted only to report explicit unavailability until its GPU backend is wired.\n\
         Without an input file, compiles a tiny built-in WASM sample to stdout."
    );
}
