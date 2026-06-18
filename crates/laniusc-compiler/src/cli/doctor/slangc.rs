use std::{
    env,
    io,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

const PROBE_TIMEOUT: Duration = Duration::from_millis(1500);
const PROBE_POLL_INTERVAL: Duration = Duration::from_millis(5);

/// Returns the `doctor` payload used when the user opts out of probing `slangc`.
pub(super) fn skipped_probe() -> serde_json::Value {
    let build_version = option_env!("LANIUS_SLANGC_VERSION").unwrap_or("unknown");
    let (source, command) = configured_command();
    serde_json::json!({
        "status": "skipped",
        "source": source,
        "path": command.display().to_string(),
        "build_version": build_version,
        "probe_attempted": false,
        "skip_reason": "--skip-slangc-probe requested",
        "required": "compatible slangc available through SLANGC or PATH for shader compilation"
    })
}

/// Probes the configured `slangc` binary and returns status plus JSON metadata.
pub(super) fn check() -> (&'static str, serde_json::Value) {
    let build_version = option_env!("LANIUS_SLANGC_VERSION").unwrap_or("unknown");
    let (source, command) = configured_command();
    let command_display = command.display().to_string();
    match version_output(&command) {
        VersionProbe::Output(output) if output.status.success() => {
            let runtime_version = first_nonempty_line(&output.stdout)
                .or_else(|| first_nonempty_line(&output.stderr))
                .unwrap_or_else(|| build_version.to_string());
            (
                "ok",
                serde_json::json!({
                    "status": "ok",
                    "source": source,
                    "path": command_display,
                    "version": runtime_version,
                    "build_version": build_version,
                    "probe_attempted": true,
                    "required": "compatible slangc available through SLANGC or PATH for shader compilation"
                }),
            )
        }
        VersionProbe::Output(output) => (
            "error",
            serde_json::json!({
                "status": "error",
                "source": source,
                "path": command_display,
                "exit_status": output.status.code(),
                "stdout": String::from_utf8_lossy(&output.stdout).trim(),
                "stderr": String::from_utf8_lossy(&output.stderr).trim(),
                "build_version": build_version,
                "probe_attempted": true,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
        VersionProbe::Timeout { arg, timeout } => (
            "error",
            serde_json::json!({
                "status": "error",
                "error_kind": "timeout",
                "source": source,
                "path": command_display,
                "arg": arg,
                "timeout_ms": duration_millis(timeout),
                "build_version": build_version,
                "probe_attempted": true,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
        VersionProbe::Error(err) if err.kind() == io::ErrorKind::NotFound => (
            "missing",
            serde_json::json!({
                "status": "missing",
                "source": source,
                "path": command_display,
                "build_version": build_version,
                "probe_attempted": true,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
        VersionProbe::Error(err) => (
            "error",
            serde_json::json!({
                "status": "error",
                "source": source,
                "path": command_display,
                "error": err.to_string(),
                "build_version": build_version,
                "probe_attempted": true,
                "required": "compatible slangc available through SLANGC or PATH for shader compilation"
            }),
        ),
    }
}

fn configured_command() -> (&'static str, PathBuf) {
    let configured_slangc = env::var_os("SLANGC").filter(|value| !value.is_empty());
    match configured_slangc.as_deref() {
        Some(path) => ("SLANGC", PathBuf::from(path)),
        None => ("PATH", PathBuf::from("slangc")),
    }
}

enum VersionProbe {
    Output(Output),
    Timeout {
        arg: &'static str,
        timeout: Duration,
    },
    Error(io::Error),
}

fn version_output(command: &Path) -> VersionProbe {
    match command_output(command, "-version") {
        VersionProbe::Output(output) if output.status.success() => VersionProbe::Output(output),
        VersionProbe::Output(primary_output) => match command_output(command, "--version") {
            VersionProbe::Output(output) if output.status.success() => VersionProbe::Output(output),
            VersionProbe::Timeout { arg, timeout } => VersionProbe::Timeout { arg, timeout },
            _ => VersionProbe::Output(primary_output),
        },
        result => result,
    }
}

fn command_output(command: &Path, arg: &'static str) -> VersionProbe {
    let mut child = match Command::new(command)
        .arg(arg)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) => return VersionProbe::Error(err),
    };
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => {
                return match child.wait_with_output() {
                    Ok(output) => VersionProbe::Output(output),
                    Err(err) => VersionProbe::Error(err),
                };
            }
            Ok(None) => {}
            Err(err) => return VersionProbe::Error(err),
        }

        if start.elapsed() >= PROBE_TIMEOUT {
            if let Err(err) = child.kill() {
                if err.kind() == io::ErrorKind::InvalidInput {
                    return match child.wait_with_output() {
                        Ok(output) => VersionProbe::Output(output),
                        Err(err) => VersionProbe::Error(err),
                    };
                }
                return VersionProbe::Error(err);
            }
            let _ = child.wait();
            return VersionProbe::Timeout {
                arg,
                timeout: PROBE_TIMEOUT,
            };
        }

        thread::sleep(PROBE_POLL_INTERVAL);
    }
}

fn duration_millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

fn first_nonempty_line(bytes: &[u8]) -> Option<String> {
    String::from_utf8_lossy(bytes)
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(ToOwned::to_owned)
}
