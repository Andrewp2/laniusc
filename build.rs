// build.rs — compile Slang entrypoints (no duplicate module sources) and bundle prebuilt lexer tables.

use std::{
    env,
    fs,
    io,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{Context, Result, anyhow};

fn main() -> Result<()> {
    println!("cargo:rustc-check-cfg=cfg(has_prebuilt_tables)");
    track_dir_recursively("shaders");

    let slangc = find_slangc()
        .context("could not locate `slangc` binary. Set $SLANGC or add it to PATH.")?;
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let shader_out_dir = out_dir.join("shaders");
    fs::create_dir_all(&shader_out_dir).context("create OUT_DIR/shaders")?;

    let sources =
        collect_slang_sources(Path::new("shaders")).context("walk shaders/ for .slang files")?;

    // Only compile files that contain an entrypoint attribute, e.g. [shader("compute")]
    for ep in sources {
        if ep.extension().and_then(|e| e.to_str()) != Some("slang") {
            continue;
        }
        if !has_entrypoint(&ep).unwrap_or(false) {
            // Still tracked for rebuild via track_dir_recursively; just not compiled as an entrypoint.
            continue;
        }

        let file_stem = ep
            .file_stem()
            .and_then(|n| n.to_str())
            .ok_or_else(|| anyhow!("invalid shader filename: {ep:?}"))?;

        let spv_out = shader_out_dir.join(format!("{file_stem}.spv"));
        let refl_out = shader_out_dir.join(format!("{file_stem}.reflect.json"));

        let extra = env::var("SLANGC_EXTRA_FLAGS").unwrap_or_default();
        let extra_args: Vec<&str> = extra.split_whitespace().filter(|s| !s.is_empty()).collect();

        let mut cmd = Command::new(&slangc);
        cmd.arg("-target")
            .arg("spirv")
            .arg("-profile")
            .arg("glsl_450")
            .arg("-fvk-use-entrypoint-name")
            .arg("-reflection-json")
            .arg(&refl_out)
            // Let `import utils;` and other modules resolve from source by search path:
            .arg("-I")
            .arg("shaders")
            .arg("-I")
            .arg("shaders/lexer")
            .arg("-o")
            .arg(&spv_out)
            // Finally, the entrypoint source itself (no module/library sources added!)
            .arg(&ep);

        for a in &extra_args {
            cmd.arg(a);
        }

        let out = cmd
            .output()
            .with_context(|| format!("failed running slangc for {ep:?}"))?;
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
                ep,
                out.status.code()
            ));
        }
    }

    // Prefer a compact .bin; fall back to .json
    let bin_prebuilt = PathBuf::from("tables/lexer_tables.bin");
    let json_prebuilt = PathBuf::from("tables/lexer_tables.json");

    if bin_prebuilt.exists() || json_prebuilt.exists() {
        let (src, ext) = if bin_prebuilt.exists() {
            (bin_prebuilt, ".bin")
        } else {
            (json_prebuilt, ".json")
        };
        let dest = out_dir.join(format!("lexer_tables{ext}"));
        fs::copy(&src, &dest).with_context(|| {
            format!(
                "copy prebuilt tables from {} to {}",
                src.display(),
                dest.display()
            )
        })?;
        println!("cargo:rerun-if-changed={}", src.display());
        println!("cargo:rustc-cfg=has_prebuilt_tables");
        println!("cargo:rustc-env=LEXER_TABLES_EXT={ext}");
        println!(
            "cargo:warning=Using prebuilt lexer tables: {}",
            src.display()
        );
    } else {
        println!(
            "cargo:warning=No prebuilt lexer tables found (tables/lexer_tables.bin|.json). Will build at runtime."
        );
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
            if p.ends_with("lib")
                && let Some(c) = p.parent().map(|x| x.join("bin").join("slangc"))
                && c.is_file()
            {
                return Ok(c);
            }
        }
    }
    Err(anyhow!("`slangc` not found"))
}

fn track_dir_recursively<P: AsRef<Path>>(dir: P) {
    let path = dir.as_ref();

    println!("cargo:rerun-if-changed={}", path.display());

    let Ok(read_dir) = fs::read_dir(path) else {
        return;
    };
    for entry in read_dir.flatten() {
        let p = entry.path();
        let Ok(ft) = entry.file_type() else {
            continue;
        };

        #[cfg(unix)]
        if ft.is_symlink() {
            continue;
        }

        if ft.is_dir() {
            track_dir_recursively(&p);
        } else if ft.is_file() {
            println!("cargo:rerun-if-changed={}", p.display());
        }
    }
}

fn collect_slang_sources(root: &Path) -> io::Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
        for ent in fs::read_dir(dir)? {
            let ent = ent?;
            let p = ent.path();
            if p.is_dir() {
                walk(&p, out)?;
            } else if p.extension().and_then(|e| e.to_str()) == Some("slang") {
                out.push(p);
            }
        }
        Ok(())
    }
    walk(root, &mut out)?;
    Ok(out)
}

/// Heuristic: does this source contain a Slang entrypoint attribute?
/// We detect `[shader("...")]` anywhere in the file.
fn has_entrypoint(path: &Path) -> io::Result<bool> {
    let text = fs::read_to_string(path)?;
    Ok(text.contains("[shader(\"") || text.contains("[shader('") || text.contains("[shader("))
}
