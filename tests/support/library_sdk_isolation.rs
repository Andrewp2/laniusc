//! Linux SDK acceptance support, deliberately local to the SDK tests.
//!
//! This proves independence from the original source/build trees, not a
//! hermetic Linux distribution. System libraries, GPU devices/drivers and
//! ordinary host tools remain available. No compiler or shader root is supplied
//! here: the installed launcher must find its own relocated payload.

use std::{
    collections::BTreeSet,
    ffi::{OsStr, OsString},
    fs,
    io::{BufRead, BufReader},
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
};

pub struct Sandbox {
    work: PathBuf,
    state: PathBuf,
    hidden: Vec<PathBuf>,
}

impl Sandbox {
    /// `work` is a new, caller-owned external directory. Its `.isolation`
    /// directory must not exist. Cache state may be reused by subsequent commands
    /// within this one gate, but never seeded from the host or another gate.
    pub fn new(checkout: &Path, sdk: &Path, work: &Path, extra_hidden: &[PathBuf]) -> Self {
        let checkout = fs::canonicalize(checkout).expect("canonical checkout");
        let sdk = fs::canonicalize(sdk).expect("canonical relocated SDK");
        let work = fs::canonicalize(work).expect("canonical fresh SDK workspace");
        assert!(!sdk.starts_with(&checkout), "SDK must be outside checkout");
        assert!(
            !work.starts_with(&checkout),
            "work must be outside checkout"
        );
        assert!(
            !work.starts_with(&sdk) && !sdk.starts_with(&work),
            "SDK and mutable work must be disjoint"
        );
        let mut hidden = vec![checkout];
        for path in extra_hidden {
            assert!(path.is_absolute(), "hidden path must be absolute: {path:?}");
            hidden.push(resolved(path));
        }
        hidden.sort();
        hidden.dedup();
        // A hidden ancestor already hides every descendant. Avoid mounting a
        // nested path inside the empty ancestor overmount.
        let mut roots: Vec<PathBuf> = Vec::new();
        for path in hidden {
            assert!(path.parent().is_some(), "cannot hide filesystem root");
            assert!(
                !sdk.starts_with(&path) && !work.starts_with(&path),
                "hidden root covers SDK/work: {path:?}"
            );
            if !roots.iter().any(|root| path.starts_with(root)) {
                roots.push(path);
            }
        }
        for tool in ["/usr/bin/bwrap", "/usr/bin/strace"] {
            assert!(
                Path::new(tool).is_file(),
                "required SDK acceptance tool missing: {tool}"
            );
        }
        let state = work.join(".isolation");
        fs::create_dir(&state).expect("fresh isolation state; never reuse a gate's cache");
        for name in ["home", "cache", "tmp", "cwd", "traces", "runtime"] {
            fs::create_dir(state.join(name)).unwrap();
        }
        fs::set_permissions(state.join("runtime"), fs::Permissions::from_mode(0o700)).unwrap();
        fs::create_dir(state.join("cache/pipelines")).unwrap();
        Self {
            work,
            state,
            hidden: roots,
        }
    }

    pub fn trace_prefix(&self, label: &str) -> PathBuf {
        assert!(
            !label.is_empty()
                && label
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        );
        self.state.join("traces").join(label)
    }

    pub fn command<I, S>(&self, label: &str, program: impl AsRef<OsStr>, args: I) -> Command
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let program = program.as_ref();
        assert!(
            Path::new(program).is_absolute(),
            "use an absolute installed executable"
        );
        let trace = self.trace_prefix(label);
        assert!(
            self.trace_files(label).is_empty(),
            "trace label reused: {label}"
        );
        let mut command = Command::new("/usr/bin/bwrap");
        command
            .env_clear()
            .current_dir(&self.work)
            .stdin(Stdio::null());
        command.args([
            "--die-with-parent",
            "--unshare-pid",
            "--unshare-net",
            "--ro-bind",
            "/",
            "/",
            "--proc",
            "/proc",
            "--dev-bind",
            "/dev",
            "/dev",
        ]);
        command.arg("--bind").arg(&self.work).arg(&self.work);
        for path in &self.hidden {
            // Relocation removes the original SDK path. Existing checkout/build
            // roots are overmounted, rather than merely relying on lack of use.
            if path.exists() {
                assert!(path.is_dir(), "hidden root must be a directory: {path:?}");
                command.arg("--tmpfs").arg(path);
            }
        }
        command.args([
            "--clearenv",
            "--setenv",
            "PATH",
            "/usr/bin:/bin",
            "--setenv",
            "LC_ALL",
            "C",
        ]);
        for (name, path) in [
            ("HOME", self.state.join("home")),
            ("XDG_CACHE_HOME", self.state.join("cache")),
            ("XDG_CONFIG_HOME", self.state.join("home/.config")),
            ("XDG_DATA_HOME", self.state.join("home/.local/share")),
            ("XDG_RUNTIME_DIR", self.state.join("runtime")),
            ("TMPDIR", self.state.join("tmp")),
            (
                "LANIUS_PIPELINE_CACHE_DIR",
                self.state.join("cache/pipelines"),
            ),
        ] {
            command.arg("--setenv").arg(name).arg(path);
        }
        command.arg("--chdir").arg(self.state.join("cwd"));
        command.args([
            "--",
            "/usr/bin/strace",
            "--seccomp-bpf",
            "-ff",
            "-qq",
            "-yy",
            "-s",
            "4096",
            "-e",
            "trace=%file",
            "-o",
        ]);
        command.arg(trace).arg("--").arg(program).args(args);
        command
    }

    fn trace_files(&self, label: &str) -> Vec<PathBuf> {
        let prefix = format!("{label}.");
        let mut files: Vec<_> = fs::read_dir(self.state.join("traces"))
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with(&prefix)
            })
            .collect();
        files.sort();
        files
    }

    /// Required reads are successful readable opens, never mere argument/stat
    /// mentions. Required executions are successful execve calls. `-yy` annotates
    /// open results with resolved paths, including relative and symlink opens.
    pub fn assert_trace(
        &self,
        label: &str,
        required_reads: &[PathBuf],
        required_execs: &[PathBuf],
    ) {
        let evidence = self.evidence(label);
        evidence
            .require(required_reads, required_execs)
            .unwrap_or_else(|why| panic!("{label}: {why}"));
    }

    /// Successful resolved readable opens and executable paths for predicates
    /// such as an installed SPIR-V read or the suite driver's temporary ELF.
    /// The same hidden-root and bounded-trace checks always apply.
    pub fn evidence(&self, label: &str) -> Evidence {
        let files = self.trace_files(label);
        assert!(!files.is_empty(), "no filesystem trace for {label}");
        assert!(files.len() <= 4096, "unexpected trace file count");
        let mut evidence = Evidence::default();
        let mut total = 0u64;
        for path in &files {
            total += fs::metadata(path).unwrap().len();
            assert!(
                total <= 64 * 1024 * 1024,
                "unexpected filesystem trace size"
            );
            let mut pending = None;
            for line in BufReader::new(fs::File::open(path).unwrap()).lines() {
                let line = line.unwrap();
                if let Some(start) = line.strip_suffix(" <unfinished ...>") {
                    assert!(
                        pending.replace(start.to_owned()).is_none(),
                        "overlapping unfinished file calls"
                    );
                } else if let Some((_, tail)) = line
                    .strip_prefix("<... ")
                    .and_then(|s| s.split_once(" resumed>"))
                {
                    let start = pending
                        .take()
                        .expect("resumed filesystem call without start");
                    evidence
                        .record(&format!("{start}{tail}"), &self.hidden)
                        .unwrap_or_else(|why| panic!("{label}: {why}"));
                } else {
                    evidence
                        .record(&line, &self.hidden)
                        .unwrap_or_else(|why| panic!("{label}: {why}"));
                }
            }
            assert!(pending.is_none(), "incomplete filesystem trace: {path:?}");
        }
        eprintln!(
            "SDK isolation {label}: {} process traces, {} successful readable paths, {} executed paths; original roots hidden",
            files.len(),
            evidence.reads.len(),
            evidence.execs.len()
        );
        evidence
    }
}

#[derive(Default)]
pub struct Evidence {
    pub reads: BTreeSet<PathBuf>,
    pub execs: BTreeSet<PathBuf>,
}

impl Evidence {
    fn record(&mut self, line: &str, hidden: &[PathBuf]) -> Result<(), String> {
        let Some((call, result)) = line.rsplit_once(" = ") else {
            return Ok(());
        };
        let number = result
            .split(|c: char| !c.is_ascii_digit() && c != '-')
            .next()
            .unwrap_or("");
        let Ok(number) = number.parse::<i64>() else {
            return Ok(());
        };
        if number < 0 {
            return Ok(());
        }
        let opened = call.starts_with("open(")
            || call.starts_with("openat(")
            || call.starts_with("openat2(");
        let executed = call.starts_with("execve(") && number == 0;
        let path = if opened {
            let annotation = result
                .strip_prefix(&number.to_string())
                .and_then(|s| s.strip_prefix('<'));
            let Some(path) = annotation.and_then(|s| s.rsplit_once('>').map(|(path, _)| path))
            else {
                return Err(format!(
                    "successful file open lacks -yy resolved path: {line}"
                ));
            };
            unescape(path.strip_suffix(" (deleted)").unwrap_or(path))?
        } else if executed {
            quoted_path(call.strip_prefix("execve(").unwrap())?
        } else {
            return Ok(());
        };
        if !path.is_absolute() {
            return Err(format!(
                "successful file operation lacks absolute path: {line}"
            ));
        }
        let path = resolved(&path);
        if hidden.iter().any(|root| path.starts_with(root)) {
            return Err(format!(
                "successful access into hidden original root: {path:?}"
            ));
        }
        if opened
            && !call.contains("O_PATH")
            && (call.contains("O_RDONLY") || call.contains("O_RDWR"))
        {
            self.reads.insert(path.clone());
        }
        if executed {
            self.execs.insert(path);
        }
        Ok(())
    }

    fn require(&self, reads: &[PathBuf], execs: &[PathBuf]) -> Result<(), String> {
        for (kind, required, observed) in
            [("read", reads, &self.reads), ("exec", execs, &self.execs)]
        {
            for path in required {
                if !observed.contains(&resolved(path)) {
                    return Err(format!(
                        "missing successful installed {kind} witness: {path:?}"
                    ));
                }
            }
        }
        Ok(())
    }
}

fn resolved(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| {
        let mut normalized = PathBuf::new();
        for component in path.components() {
            match component {
                Component::CurDir => (),
                Component::ParentDir => {
                    normalized.pop();
                }
                other => normalized.push(other.as_os_str()),
            }
        }
        normalized
    })
}

fn quoted_path(value: &str) -> Result<PathBuf, String> {
    let tail = value.strip_prefix('"').ok_or("unquoted execve path")?;
    let mut escaped = false;
    for (index, byte) in tail.bytes().enumerate() {
        if escaped {
            escaped = false;
        } else if byte == b'\\' {
            escaped = true;
        } else if byte == b'"' {
            return unescape(&tail[..index]);
        }
    }
    Err("unterminated execve path".into())
}

fn unescape(value: &str) -> Result<PathBuf, String> {
    let bytes = value.as_bytes();
    let mut result = Vec::new();
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        index += 1;
        if byte != b'\\' {
            result.push(byte);
            continue;
        }
        let Some(&escaped) = bytes.get(index) else {
            return Err("truncated trace path escape".into());
        };
        index += 1;
        match escaped {
            b'\\' | b'"' => result.push(escaped),
            b'n' => result.push(b'\n'),
            b'r' => result.push(b'\r'),
            b't' => result.push(b'\t'),
            b'0'..=b'7' => {
                let mut octal = u16::from(escaped - b'0');
                for _ in 0..2 {
                    if let Some(&next @ b'0'..=b'7') = bytes.get(index) {
                        octal = octal * 8 + u16::from(next - b'0');
                        index += 1;
                    } else {
                        break;
                    }
                }
                result.push(u8::try_from(octal).map_err(|_| "invalid trace octal escape")?);
            }
            _ => {
                return Err(format!(
                    "unsupported trace path escape: {}",
                    escaped as char
                ));
            }
        }
    }
    Ok(PathBuf::from(OsString::from_vec(result)))
}

#[test]
fn sdk_trace_witnesses_require_success_and_resolved_owner_paths() {
    let hidden = vec![PathBuf::from("/original/build")];
    let file = PathBuf::from("/relocated SDK/stdlib/core/result.lani");
    let exe = PathBuf::from("/relocated SDK/libexec/laniusc");
    let mut evidence = Evidence::default();
    evidence.record(r#"openat(AT_FDCWD, "/relocated SDK/stdlib/core/result.lani", O_RDONLY) = -1 ENOENT (No such file or directory)"#, &hidden).unwrap();
    assert!(evidence.require(&[file.clone()], &[]).is_err());
    evidence.record(r#"openat(4</relocated SDK>, "stdlib/core/result.lani", O_RDONLY|O_CLOEXEC) = 9</relocated SDK/stdlib/core/result.lani>"#, &hidden).unwrap();
    evidence
        .record(
            r#"execve("/relocated SDK/libexec/laniusc", ["laniusc"], 0x1 /* 8 vars */) = 0"#,
            &hidden,
        )
        .unwrap();
    evidence.require(&[file], &[exe]).unwrap();
    assert!(evidence.record(r#"openat(AT_FDCWD, "/innocent-alias/shader.spv", O_RDONLY) = 5</original/build/shader.spv>"#, &hidden).is_err());
    assert!(evidence.record(r#"openat(AT_FDCWD, "/original/build/../build/shader.spv", O_RDONLY) = 5</original/build/../build/shader.spv>"#, &hidden).is_err());
    assert_eq!(
        quoted_path(r#""/relocated\040SDK/quote\"name", []"#).unwrap(),
        PathBuf::from("/relocated SDK/quote\"name")
    );
}
