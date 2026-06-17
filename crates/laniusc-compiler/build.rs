use std::{
    env,
    fs,
    io,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

fn main() {
    const DEFAULT_SLANGC_VERSION_TIMEOUT_MS: u64 = 2_000;
    const DEFAULT_SHADER_COMPILE_TIMEOUT_MS: u64 = 120_000;

    println!("cargo:rerun-if-env-changed=CARGO_TARGET_DIR");
    println!("cargo:rerun-if-env-changed=SLANGC");
    println!("cargo:rerun-if-env-changed=LANIUS_SLANGC_VERSION_TIMEOUT_MS");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_COMPILE_TIMEOUT_MS");

    let workspace_root = workspace_root();
    let slangc_version_timeout = timeout_from_env_ms(
        "LANIUS_SLANGC_VERSION_TIMEOUT_MS",
        DEFAULT_SLANGC_VERSION_TIMEOUT_MS,
    );
    let shader_compile_timeout = timeout_from_env_ms(
        "LANIUS_SHADER_COMPILE_TIMEOUT_MS",
        DEFAULT_SHADER_COMPILE_TIMEOUT_MS,
    );
    let slangc_version = find_slangc()
        .map(|slangc| slangc_version(&slangc, slangc_version_timeout))
        .unwrap_or_else(|| "unknown".to_string());

    println!(
        "cargo:rerun-if-changed={}",
        workspace_root.join("Cargo.lock").display()
    );
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rustc-env=LANIUS_SLANGC_VERSION={slangc_version}");
    println!(
        "cargo:rustc-env=LANIUS_SLANGC_VERSION_TIMEOUT_MS={}",
        timeout_metadata_value(slangc_version_timeout)
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_COMPILE_TIMEOUT_MS={}",
        timeout_metadata_value(shader_compile_timeout)
    );
    println!(
        "cargo:rustc-env=LANIUS_WGPU_VERSION={}",
        cargo_lock_package_version(&workspace_root, "wgpu")
            .unwrap_or_else(|| "unknown".to_string())
    );
    println!(
        "cargo:rustc-env=LANIUS_BUILD_PROFILE={}",
        env::var("PROFILE").unwrap_or_else(|_| "unknown".to_string())
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_ROOT={}",
        shader_artifact_root(&workspace_root).display()
    );
}

fn workspace_root() -> PathBuf {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .expect("laniusc-compiler should live under crates/")
}

fn shader_artifact_root(workspace_root: &Path) -> PathBuf {
    let target_dir = env::var_os("CARGO_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| workspace_root.join("target"));
    let profile = env::var("PROFILE").unwrap_or_else(|_| "debug".to_string());
    target_dir
        .join("laniusc-shader-artifacts")
        .join(profile)
        .join("shaders")
}

fn timeout_from_env_ms(name: &str, default_ms: u64) -> Option<Duration> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) => return Some(Duration::from_millis(default_ms)),
    };
    let value = value.trim();
    if value.is_empty() {
        return Some(Duration::from_millis(default_ms));
    }
    let Ok(parsed) = value.parse::<u64>() else {
        return Some(Duration::from_millis(default_ms));
    };
    (parsed != 0).then_some(Duration::from_millis(parsed))
}

fn timeout_metadata_value(timeout: Option<Duration>) -> String {
    timeout
        .map(|timeout| timeout.as_millis().to_string())
        .unwrap_or_else(|| "disabled".to_string())
}

fn find_slangc() -> Option<PathBuf> {
    if let Ok(path) = env::var("SLANGC") {
        let path = PathBuf::from(path);
        if path.is_file() {
            return Some(path);
        }
    }
    which::which("slangc").ok()
}

fn slangc_version(slangc: &PathBuf, timeout: Option<Duration>) -> String {
    let mut command = Command::new(slangc);
    command.arg("-version");
    match command_output_with_timeout(&mut command, timeout) {
        Ok(out) if out.status.success() => {
            let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !stdout.is_empty() {
                return stdout;
            }
            let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
            if !stderr.is_empty() {
                return stderr;
            }
            "unknown".to_string()
        }
        Err(err) if err.kind() == io::ErrorKind::TimedOut => timeout
            .map(|timeout| format!("timeout_after_{}ms", timeout.as_millis()))
            .unwrap_or_else(|| "timeout".to_string()),
        _ => "unknown".to_string(),
    }
}

fn command_output_with_timeout(
    command: &mut Command,
    timeout: Option<Duration>,
) -> io::Result<std::process::Output> {
    let Some(timeout) = timeout else {
        return command.output();
    };

    let mut child = command
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;
    let start = std::time::Instant::now();
    loop {
        if child.try_wait()?.is_some() {
            return child.wait_with_output();
        }
        if start.elapsed() >= timeout {
            if let Err(err) = child.kill()
                && err.kind() != io::ErrorKind::InvalidInput
            {
                return Err(err);
            }
            let _ = child.wait_with_output();
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("command timed out after {} ms", timeout.as_millis()),
            ));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn cargo_lock_package_version(workspace_root: &Path, package_name: &str) -> Option<String> {
    let text = fs::read_to_string(workspace_root.join("Cargo.lock")).ok()?;
    let mut in_package = false;
    let mut saw_name = false;
    for line in text.lines() {
        let line = line.trim();
        if line == "[[package]]" {
            in_package = true;
            saw_name = false;
            continue;
        }
        if !in_package {
            continue;
        }
        if let Some(name) = quoted_field(line, "name") {
            saw_name = name == package_name;
            continue;
        }
        if saw_name && let Some(version) = quoted_field(line, "version") {
            return Some(version.to_string());
        }
    }
    None
}

fn quoted_field<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(key)?.trim_start();
    let rest = rest.strip_prefix('=')?.trim_start();
    rest.strip_prefix('"')?.split('"').next()
}
