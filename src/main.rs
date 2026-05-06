use std::{env, fs, path::PathBuf};

use laniusc::compiler::{
    compile_source_to_c,
    compile_source_to_c_with_gpu_codegen,
    compile_source_to_c_with_gpu_frontend,
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
    let mut emit = "c".to_string();
    let mut gpu_frontend = false;
    let mut gpu_codegen = true;

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
            "--gpu-frontend" => {
                gpu_frontend = true;
                gpu_codegen = false;
            }
            "--gpu-codegen" => {
                gpu_codegen = true;
                gpu_frontend = true;
            }
            "--cpu" => {
                gpu_frontend = false;
                gpu_codegen = false;
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

    if emit != "c" {
        return Err(format!(
            "unsupported emit target {emit:?}; supported target: c"
        ));
    }

    let src = if let Some(input) = &input {
        fs::read_to_string(input).map_err(|err| format!("read {}: {err}", input.display()))?
    } else {
        "fn main() { let x = 1 + 2; return x; }\n".to_string()
    };

    let emitted = if gpu_codegen {
        pollster::block_on(compile_source_to_c_with_gpu_codegen(&src))
    } else if gpu_frontend {
        pollster::block_on(compile_source_to_c_with_gpu_frontend(&src))
    } else {
        compile_source_to_c(&src)
    }
    .map_err(|err| err.to_string())?;
    if let Some(output) = output {
        fs::write(&output, emitted).map_err(|err| format!("write {}: {err}", output.display()))?;
    } else {
        print!("{emitted}");
    }
    Ok(())
}

fn print_help() {
    eprintln!(
        "Usage: laniusc [--emit c] [--gpu-frontend|--gpu-codegen] [-o output.c] <input.lani>\n\
         Emits C code for the current Lanius frontend subset. Without an input\n\
         file, compiles a tiny built-in sample to stdout. By default this uses\n\
         GPU lexing, GPU parsing, GPU type checking, and GPU C emission. Use\n\
         --cpu for the legacy CPU path or --gpu-frontend for GPU lexing plus\n\
         CPU HIR/code emission."
    );
}
