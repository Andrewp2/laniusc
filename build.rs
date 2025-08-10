// build.rs — compile .slang with slangc, emit SPIR-V + reflection JSON, print diagnostics.

use anyhow::{Context, Result, anyhow};
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

fn main() -> Result<()> {
    println!("cargo:rerun-if-changed=shaders");
    if let Ok(rd) = fs::read_dir("shaders") {
        for e in rd.flatten() {
            if e.path().extension().and_then(|s| s.to_str()) == Some("slang") {
                println!("cargo:rerun-if-changed={}", e.path().display());
            }
        }
    }

    let slangc = find_slangc()
        .context("could not locate `slangc` binary. Set $SLANGC or add it to PATH.")?;
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let shader_out_dir = out_dir.join("shaders");
    fs::create_dir_all(&shader_out_dir).context("create OUT_DIR/shaders")?;

    for entry in fs::read_dir("shaders").context("read_dir(shaders)")? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("slang") {
            continue;
        }

        let file_stem = path
            .file_stem()
            .and_then(|n| n.to_str())
            .ok_or_else(|| anyhow!("invalid shader filename: {path:?}"))?;

        let spv_out = shader_out_dir.join(format!("{file_stem}.spv"));
        let refl_out = shader_out_dir.join(format!("{file_stem}.reflect.json"));

        // Optional extra flags via env (e.g. "-O")
        let extra = env::var("SLANGC_EXTRA_FLAGS").unwrap_or_default();
        let extra_args: Vec<&str> = extra.split_whitespace().filter(|s| !s.is_empty()).collect();

        // We *don’t* pass -entry or -stage; Slang will discover [shader("compute")] entry points.
        // We *do* keep entrypoint names in SPIR-V.
        let mut cmd = Command::new(&slangc);
        cmd.arg(&path)
            .arg("-target")
            .arg("spirv")
            .arg("-profile")
            .arg("glsl_450")
            .arg("-fvk-use-entrypoint-name")
            .arg("-reflection-json")
            .arg(&refl_out)
            .arg("-o")
            .arg(&spv_out);

        for a in &extra_args {
            cmd.arg(a);
        }

        let out = cmd
            .output()
            .with_context(|| format!("failed running slangc for {:?}", path))?;

        if !out.stdout.is_empty() {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                println!("cargo:warning=slangc STDOUT: {line}");
            }
        }
        if !out.stderr.is_empty() {
            for line in String::from_utf8_lossy(&out.stderr).lines() {
                eprintln!("slangc: {line}");
            }
        }

        if !out.status.success() {
            return Err(anyhow!(
                "slangc failed on {:?} (exit: {:?}). See diagnostics above.",
                path,
                out.status.code()
            ));
        }

        println!("cargo:warning=Slang compiled {:?} -> {:?}", path, spv_out);
        println!("cargo:warning=Reflection JSON -> {:?}", refl_out);
    }

    Ok(())
}

fn find_slangc() -> Result<PathBuf> {
    if let Ok(p) = env::var("SLANGC") {
        let pb = PathBuf::from(p);
        if pb.is_file() {
            return Ok(pb);
        }
    }
    if let Ok(pb) = which::which("slangc") {
        return Ok(pb);
    }
    if let Ok(ld) = env::var("LD_LIBRARY_PATH") {
        for comp in ld.split(':') {
            let p = Path::new(comp);
            if p.ends_with("lib") {
                if let Some(c) = p.parent().map(|x| x.join("bin").join("slangc")) {
                    if c.is_file() {
                        return Ok(c);
                    }
                }
            }
        }
    }
    Err(anyhow!("`slangc` not found"))
}
