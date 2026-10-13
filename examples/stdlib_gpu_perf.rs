//! Focused warmed GPU compiler benchmark for a real source entry and its imports.
//! Use identical inputs and separate compiled shader sets for paired comparisons.
//! LANIUS_PERF_REBUILD_ENTRY=1 forces an entry cache miss through a private copy.
use std::{
    env,
    fs,
    path::PathBuf,
    process::Command,
    time::{Instant, SystemTime},
};

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn main() {
    if let Err(error) = pollster::block_on(run()) {
        eprintln!("stdlib_gpu_perf: {error}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() != 5 {
        return Err(
            "usage: stdlib_gpu_perf ENTRY STDLIB_ROOT EXPECTED_STDOUT_FILE_OR_DASH WARMUPS ITERS"
                .into(),
        );
    }
    let mut entry = PathBuf::from(&args[0]);
    let root = PathBuf::from(&args[1]);
    let expected = if args[2] == "-" {
        Vec::new()
    } else {
        fs::read(&args[2]).map_err(|error| error.to_string())?
    };
    let warmups: usize = args[3]
        .parse()
        .map_err(|error| format!("warmups: {error}"))?;
    let iters: usize = args[4].parse().map_err(|error| format!("iters: {error}"))?;
    if warmups == 0 || iters == 0 {
        return Err("warmups and iterations must both be positive".into());
    }
    let rebuild_entry = env::var("LANIUS_PERF_REBUILD_ENTRY").as_deref() == Ok("1");
    let mut input_copy = InputCopy(None);
    if rebuild_entry {
        let path = env::temp_dir().join(format!(
            "laniusc_stdlib_perf_input_{}.lani",
            std::process::id()
        ));
        fs::copy(&entry, &path).map_err(|error| error.to_string())?;
        input_copy.0 = Some(path.clone());
        entry = path;
    }
    let mut samples = Vec::with_capacity(iters);
    let mut output = Vec::new();
    for index in 0..warmups + iters {
        if rebuild_entry {
            // Invalidate the path-backed unit cache using a private entry copy.
            // Changing its modification time happens outside the measured span.
            fs::File::open(&entry)
                .and_then(|file| file.set_modified(SystemTime::now()))
                .map_err(|error| error.to_string())?;
        }
        let start = Instant::now();
        output = compile_entry_to_x86_64_with_stdlib(&entry, &root)
            .await
            .map_err(|error| format!("{}: {error}", entry.display()))?;
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        if index >= warmups {
            samples.push(elapsed);
            println!("sample={} ms={elapsed:.3}", index - warmups);
        }
    }
    validate_output(&output, &expected)?;
    samples.sort_by(f64::total_cmp);
    let middle = samples.len() / 2;
    let median = if samples.len() % 2 == 0 {
        (samples[middle - 1] + samples[middle]) / 2.0
    } else {
        samples[middle]
    };
    let mean = samples.iter().sum::<f64>() / samples.len() as f64;
    println!(
        "entry={} rebuild_entry={rebuild_entry} warmups={warmups} iters={iters} output_bytes={} min_ms={:.3} median_ms={median:.3} avg_ms={mean:.3} max_ms={:.3} output_verified=true",
        args[0],
        output.len(),
        samples[0],
        samples[samples.len() - 1]
    );
    Ok(())
}

struct InputCopy(Option<PathBuf>);

impl Drop for InputCopy {
    fn drop(&mut self) {
        if let Some(path) = &self.0 {
            let _ = fs::remove_file(path);
        }
    }
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn validate_output(bytes: &[u8], expected: &[u8]) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    if !bytes.starts_with(b"\x7fELF") {
        return Err("compiler did not emit an ELF program".into());
    }
    let path = env::temp_dir().join(format!("laniusc_stdlib_perf_{}", std::process::id()));
    fs::write(&path, bytes).map_err(|error| error.to_string())?;
    let result = (|| {
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700))
            .map_err(|error| error.to_string())?;
        let output = Command::new("timeout")
            .args(["5s"])
            .arg(&path)
            .output()
            .map_err(|error| error.to_string())?;
        if !output.status.success() || output.stdout != expected || !output.stderr.is_empty() {
            return Err(format!(
                "emitted program failed its output contract: {output:?}"
            ));
        }
        Ok(())
    })();
    let _ = fs::remove_file(&path);
    result
}

#[cfg(not(all(unix, target_arch = "x86_64")))]
fn validate_output(_: &[u8], _: &[u8]) -> Result<(), String> {
    Err("this benchmark validates emitted programs on x86_64 Unix".into())
}
