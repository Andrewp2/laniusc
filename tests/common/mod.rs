#![allow(dead_code)]

pub mod sample_programs;

use std::{
    fmt,
    fs,
    io,
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Output},
    sync::atomic::{AtomicU64, Ordering},
};

static TEMP_ARTIFACT_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct TempArtifact {
    path: PathBuf,
}

impl TempArtifact {
    pub fn new(prefix: &str, stem: &str, extension: Option<&str>) -> Self {
        Self {
            path: temp_artifact_path(prefix, stem, extension),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn write_bytes(&self, contents: impl AsRef<[u8]>) {
        fs::write(&self.path, contents).unwrap_or_else(|err| {
            panic!("write temporary artifact {}: {err}", self.path.display())
        });
    }

    pub fn write_str(&self, contents: &str) {
        self.write_bytes(contents.as_bytes());
    }
}

impl Drop for TempArtifact {
    fn drop(&mut self) {
        match fs::remove_file(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(_) => {}
        }
    }
}

pub fn temp_artifact_path(prefix: &str, stem: &str, extension: Option<&str>) -> PathBuf {
    let mut path = std::env::temp_dir().join(format!(
        "{}_{}_{}_{}",
        prefix,
        sanitize_path_component(stem),
        std::process::id(),
        next_temp_artifact_id()
    ));
    if let Some(extension) = extension {
        path.set_extension(extension);
    }
    path
}

pub fn assert_command_success(context: impl fmt::Display, output: &Output) {
    assert!(
        output.status.success(),
        "{context} failed with status {}\nstdout:\n{}\nstderr:\n{}",
        format_exit_status(&output.status),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

pub fn stdout_utf8(context: impl fmt::Display, stdout: Vec<u8>) -> String {
    String::from_utf8(stdout).unwrap_or_else(|err| panic!("{context}: stdout was not UTF-8: {err}"))
}

pub fn node_available() -> bool {
    matches!(
        Command::new("node").arg("--version").output(),
        Ok(output) if output.status.success()
    )
}

pub fn require_node() {
    let output = Command::new("node")
        .arg("--version")
        .output()
        .expect("node is required to execute sample WASM modules");
    assert_command_success("node --version", &output);
}

pub fn run_wasm_main_with_node(
    context: impl fmt::Display,
    artifact_stem: &str,
    wasm: &[u8],
) -> String {
    let context = context.to_string();
    let wasm_path = TempArtifact::new("laniusc_exec_wasm", artifact_stem, Some("wasm"));
    wasm_path.write_bytes(wasm);

    let script = r#"
const fs = require('fs');
(async () => {
  let stdout = '';
  const imports = {
    env: {
      print_i64(value) {
        stdout += value.toString() + '\n';
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  const main = module.instance.exports.main;
  if (typeof main !== 'function') {
    throw new Error('missing exported main function');
  }
  const status = main();
  if (status !== 0) {
    console.error(`main returned ${String(status)}`);
    process.exit(1);
  }
  process.stdout.write(stdout);
})().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
"#;

    let output = Command::new("node")
        .arg("-e")
        .arg(script)
        .arg(wasm_path.path())
        .output()
        .unwrap_or_else(|err| {
            panic!(
                "{context}: run node for {}: {err}",
                wasm_path.path().display()
            )
        });
    assert_command_success(
        format!("{context}: node executing {}", wasm_path.path().display()),
        &output,
    );
    stdout_utf8(format!("{context}: node stdout"), output.stdout)
}

#[cfg(all(unix, target_arch = "x86_64"))]
pub fn run_x86_64_elf(context: impl fmt::Display, artifact_stem: &str, elf: &[u8]) -> String {
    use std::os::unix::fs::PermissionsExt;

    let context = context.to_string();
    let exe_path = TempArtifact::new("laniusc_sample_x86", artifact_stem, None);
    exe_path.write_bytes(elf);

    let mut permissions = fs::metadata(exe_path.path())
        .unwrap_or_else(|err| {
            panic!(
                "{context}: stat temporary ELF {}: {err}",
                exe_path.path().display()
            )
        })
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(exe_path.path(), permissions).unwrap_or_else(|err| {
        panic!(
            "{context}: chmod temporary ELF {}: {err}",
            exe_path.path().display()
        )
    });

    let output = Command::new(exe_path.path())
        .output()
        .unwrap_or_else(|err| {
            panic!(
                "{context}: run native ELF {}: {err}",
                exe_path.path().display()
            )
        });
    assert_command_success(
        format!(
            "{context}: native ELF execution {}",
            exe_path.path().display()
        ),
        &output,
    );
    stdout_utf8(format!("{context}: native stdout"), output.stdout)
}

fn sanitize_path_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn format_exit_status(status: &ExitStatus) -> String {
    status
        .code()
        .map(|code| code.to_string())
        .unwrap_or_else(|| "terminated by signal".to_string())
}

fn next_temp_artifact_id() -> u64 {
    TEMP_ARTIFACT_COUNTER.fetch_add(1, Ordering::Relaxed)
}
