// build.rs — compile Slang entrypoints (no duplicate module sources) and bundle prebuilt lexer tables.

use std::{
    collections::HashSet,
    env,
    fs,
    io,
    path::{Path, PathBuf},
    process::Command,
    time::SystemTime,
};

use anyhow::{Context, Result, anyhow};

fn main() -> Result<()> {
    println!("cargo:rustc-check-cfg=cfg(has_prebuilt_tables)");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_DEBUG");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_OPT_LEVEL");
    println!("cargo:rerun-if-env-changed=SLANGC_EXTRA_FLAGS");
    track_dir_recursively("shaders");

    let slangc = find_slangc()
        .context("could not locate `slangc` binary. Set $SLANGC or add it to PATH.")?;
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR not set"));
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
        if is_unwired_shader_entrypoint(&ep) {
            // These are retained as source/audit fixtures, but the default compiler no longer
            // loads their SPIR-V. Skipping them keeps clean builds from paying for dead pipelines.
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
        let opt_level = shader_opt_level();
        let stamp_out = shader_out_dir.join(format!("{file_stem}.stamp"));
        let compile_stamp = format!(
            "slangc={}\nopt={opt_level}\nextra={extra}\n",
            slangc.display()
        );
        if shader_outputs_fresh(&ep, &spv_out, &refl_out, &stamp_out, &compile_stamp)? {
            continue;
        }

        let mut cmd = Command::new(&slangc);
        cmd.arg("-target")
            .arg("spirv")
            .arg("-profile")
            .arg("glsl_450")
            .arg("-fvk-use-entrypoint-name")
            .arg("-reflection-json")
            .arg(&refl_out)
            .arg("-emit-spirv-directly")
            .arg(format!("-O{opt_level}"))
            // Let `import utils;` and other modules resolve from source by search path:
            .arg("-I")
            .arg("shaders")
            .arg("-I")
            .arg("shaders/lexer")
            .arg("-I")
            .arg("shaders/parser")
            .arg("-I")
            .arg("shaders/type_checker")
            .arg("-o")
            .arg(&spv_out);

        if env_truthy("LANIUS_SHADER_DEBUG") {
            cmd.arg("-g3");
        }

        for a in &extra_args {
            cmd.arg(a);
        }

        // Finally, the entrypoint source itself (no module/library sources added!)
        cmd.arg(&ep);

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
        fs::write(&stamp_out, compile_stamp)
            .with_context(|| format!("write shader stamp {}", stamp_out.display()))?;
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

fn env_truthy(name: &str) -> bool {
    env::var(name)
        .map(|value| {
            let value = value.to_ascii_lowercase();
            value != "0" && value != "false" && value != "off"
        })
        .unwrap_or(false)
}

fn shader_opt_level() -> String {
    env::var("LANIUS_SHADER_OPT_LEVEL").unwrap_or_else(|_| "1".into())
}

fn is_unwired_shader_entrypoint(path: &Path) -> bool {
    matches!(
        path.to_str(),
        Some("shaders/codegen/wasm_body.slang")
            | Some("shaders/codegen/wasm_bool_body.slang")
            | Some("shaders/codegen/wasm_bool_compact.slang")
            | Some("shaders/codegen/wasm_bool_probe.slang")
            | Some("shaders/codegen/wasm_bool_scan.slang")
            | Some("shaders/codegen/wasm_functions.slang")
            | Some("shaders/codegen/wasm_functions_probe.slang")
    )
}

fn shader_outputs_fresh(
    ep: &Path,
    spv_out: &Path,
    refl_out: &Path,
    stamp_out: &Path,
    compile_stamp: &str,
) -> Result<bool> {
    if fs::read_to_string(stamp_out).ok().as_deref() != Some(compile_stamp) {
        return Ok(false);
    }
    let output_mtime = oldest_mtime([spv_out, refl_out, stamp_out]);
    let Some(output_mtime) = output_mtime else {
        return Ok(false);
    };

    let mut deps = Vec::new();
    let mut seen = HashSet::new();
    collect_shader_dependencies(ep, &mut seen, &mut deps)?;
    for dep in deps {
        let input_mtime = fs::metadata(&dep)
            .and_then(|metadata| metadata.modified())
            .with_context(|| format!("read shader dependency mtime for {}", dep.display()))?;
        if input_mtime > output_mtime {
            return Ok(false);
        }
    }
    Ok(true)
}

fn oldest_mtime<const N: usize>(paths: [&Path; N]) -> Option<SystemTime> {
    paths
        .into_iter()
        .map(|path| {
            fs::metadata(path)
                .and_then(|metadata| metadata.modified())
                .ok()
        })
        .try_fold(None, |oldest, mtime| {
            let mtime = mtime?;
            Some(Some(match oldest {
                Some(oldest) if oldest <= mtime => oldest,
                _ => mtime,
            }))
        })
        .flatten()
}

fn collect_shader_dependencies(
    path: &Path,
    seen: &mut HashSet<PathBuf>,
    out: &mut Vec<PathBuf>,
) -> Result<()> {
    let path = path.to_path_buf();
    if !seen.insert(path.clone()) {
        return Ok(());
    }
    out.push(path.clone());

    let text = fs::read_to_string(&path)
        .with_context(|| format!("read shader dependency {}", path.display()))?;
    for import in shader_imports(&text) {
        if let Some(dep) = resolve_shader_import(&path, import) {
            collect_shader_dependencies(&dep, seen, out)?;
        }
    }
    Ok(())
}

fn shader_imports(text: &str) -> impl Iterator<Item = &str> {
    text.lines().filter_map(|line| {
        let line = line.split("//").next().unwrap_or("").trim();
        let rest = line.strip_prefix("import ")?;
        rest.strip_suffix(';').map(str::trim)
    })
}

fn resolve_shader_import(importer: &Path, import: &str) -> Option<PathBuf> {
    let rel = PathBuf::from(format!("{}.slang", import.replace("::", "/")));
    let mut candidates = Vec::new();
    if let Some(parent) = importer.parent() {
        candidates.push(parent.join(&rel));
    }
    candidates.extend([
        Path::new("shaders").join(&rel),
        Path::new("shaders/lexer").join(&rel),
        Path::new("shaders/parser").join(&rel),
        Path::new("shaders/type_checker").join(&rel),
        Path::new("shaders/codegen").join(&rel),
    ]);
    candidates.into_iter().find(|candidate| candidate.is_file())
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
