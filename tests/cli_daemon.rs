use crate::common;

use std::{
    env,
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::OnceLock,
    thread,
    time::{Duration, Instant},
};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
}

fn assert_twenty_capacity_stable_jobs(backend: &str, emit: &str, extension: Option<&str>) {
    let source = common::temp_artifact_path("laniusc_daemon_capacity", backend, Some("lani"));
    let alternate_source = common::temp_artifact_path(
        "laniusc_daemon_capacity",
        &format!("{backend}_alternate"),
        Some("lani"),
    );
    let grown_source = common::temp_artifact_path("laniusc_daemon_capacity", "grown", Some("lani"));
    let dense_source = common::temp_artifact_path("laniusc_daemon_capacity", "dense", Some("lani"));
    let artifact = common::temp_artifact_path("laniusc_daemon_capacity", emit, extension);
    let requests = common::temp_artifact_path("laniusc_daemon_capacity", "requests", Some("jsonl"));
    fs::write(&source, "fn main() -> i32 { return 42; }\n")
        .expect("write capacity-stable daemon source");
    fs::write(&alternate_source, "fn main() -> i32 { return 41; }\n")
        .expect("write alternate capacity-stable daemon source");
    fs::write(
        &grown_source,
        format!(
            "fn main() -> i32 {{ return 42; }}\n//{}\n",
            "x".repeat(4096)
        ),
    )
    .expect("write grown daemon source");
    fs::write(
        &dense_source,
        "fn main() -> i32 { let a = 1; let b = 2; let c = 3; let d = 4; let e = 5; return a + b + c + d + e; }\n",
    )
    .expect("write token-dense daemon source");

    let mut request_lines = (0..21)
        .map(|job| {
            let input = if job % 2 == 0 {
                &source
            } else {
                &alternate_source
            };
            serde_json::json!({
                "id": format!("compile-{job}"),
                "command": "compile",
                "emit": emit,
                "input": input,
                "output": artifact,
            })
            .to_string()
        })
        .collect::<Vec<_>>();
    for job in ["dense", "dense-repeat"] {
        request_lines.push(
            serde_json::json!({
                "id": job,
                "command": "compile",
                "emit": emit,
                "input": dense_source,
                "output": artifact,
            })
            .to_string(),
        );
    }
    for job in ["growth", "growth-repeat"] {
        request_lines.push(
            serde_json::json!({
                "id": job,
                "command": "compile",
                "emit": emit,
                "input": grown_source,
                "output": artifact,
            })
            .to_string(),
        );
    }
    request_lines.push(serde_json::json!({"id": "shutdown", "command": "shutdown"}).to_string());
    fs::write(&requests, format!("{}\n", request_lines.join("\n")))
        .expect("write capacity-stable daemon requests");

    let stdin = fs::File::open(&requests).expect("open capacity-stable daemon requests");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("daemon")
        .arg("--stdio")
        .arg("--backend")
        .arg(backend)
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
        .stdin(Stdio::from(stdin));
    let output = common::codegen_command_output_with_timeout(
        &format!("laniusc daemon {backend} twenty-job reuse"),
        &mut command,
    );
    common::assert_command_success("laniusc daemon twenty-job reuse", &output);

    let responses = String::from_utf8(output.stdout)
        .expect("daemon stdout should be UTF-8")
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).expect("daemon response JSON"))
        .collect::<Vec<_>>();
    assert_eq!(
        responses.len(),
        27,
        "ready, 21 stable jobs, token growth and repeat, byte growth and repeat, and shutdown"
    );
    assert_eq!(responses[0]["event"], "ready");
    assert_eq!(responses[0]["targets"], serde_json::json!([emit]));
    assert_eq!(
        responses[1]["workspace_request_kind"],
        "cold_or_grown_workspace"
    );
    assert_eq!(
        responses[1]["resources_created_during_job"]["compute_pipelines"], 0,
        "the first job must not create pipelines after readiness: {}",
        responses[1]
    );
    let retained_wgpu_buffers = responses[2]["wgpu_resources"]["buffers"]["kept_from_user"]
        .as_u64()
        .expect("warm response should report resident WGPU buffers");
    for response in &responses[2..22] {
        assert_eq!(
            response["ok"], true,
            "capacity-stable job failed: {response}"
        );
        assert_eq!(response["workspace_request_kind"], "retained_capacity");
        assert_eq!(response["resources_created_during_job"]["buffers"], 0);
        assert_eq!(response["resources_created_during_job"]["bind_groups"], 0);
        assert_eq!(
            response["resources_created_during_job"]["compute_pipelines"],
            0
        );
        assert_eq!(
            response["wgpu_resources"]["buffers"]["kept_from_user"], retained_wgpu_buffers,
            "warm job changed the raw WGPU buffer population: {response}"
        );
        assert_eq!(
            response["wgpu_resources"]["buffers"]["released_from_user"], 0,
            "warm job created and dropped an untracked raw WGPU buffer: {response}"
        );
    }
    assert_eq!(responses[22]["id"], "dense");
    assert_eq!(responses[22]["ok"], true);
    assert_eq!(responses[22]["workspace_request_kind"], "retained_capacity");
    assert_eq!(responses[23]["id"], "dense-repeat");
    assert_eq!(responses[23]["ok"], true);
    assert_eq!(responses[23]["workspace_request_kind"], "retained_capacity");
    assert_eq!(responses[24]["id"], "growth");
    assert_eq!(
        responses[24]["workspace_request_kind"],
        "cold_or_grown_workspace"
    );
    assert_eq!(responses[25]["id"], "growth-repeat");
    assert_eq!(
        responses[25]["workspace_request_kind"], "retained_capacity",
        "repeat after growth created resources: {}",
        responses[25]
    );
    assert_eq!(responses[25]["resources_created_during_job"]["buffers"], 0);
    assert_eq!(
        responses[25]["resources_created_during_job"]["bind_groups"],
        0
    );
    assert_eq!(
        responses[25]["resources_created_during_job"]["compute_pipelines"],
        0
    );
}

#[test]
fn cli_daemon_reuses_capacity_for_twenty_jobs_on_each_target() {
    assert_twenty_capacity_stable_jobs("x86_64", "x86_64", None);
    assert_twenty_capacity_stable_jobs("wasm", "wasm", Some("wasm"));
}

/// A daemon process that listens on a Unix socket.
struct SocketDaemon {
    /// Ends the process when the daemon is dropped.
    _child: ChildGuard,
    socket: PathBuf,
}

impl SocketDaemon {
    /// Starts a daemon for both targets.
    fn start(name: &str) -> Self {
        let socket = common::temp_artifact_path("laniusc_daemon", name, Some("sock"));
        let child = Command::new(laniusc_bin())
            .arg("daemon")
            .arg("--unix-socket")
            .arg(&socket)
            .arg("--stdlib-root")
            .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn Unix-socket daemon");
        Self {
            _child: ChildGuard(child),
            socket,
        }
    }

    /// Connects one more client and reads its ready event.
    fn connect(&self) -> DaemonSession {
        // The daemon binds the socket after it has created its pipelines.
        let deadline = Instant::now() + Duration::from_secs(120);
        let stream = loop {
            match UnixStream::connect(&self.socket) {
                Ok(stream) => break stream,
                Err(err) => {
                    assert!(
                        Instant::now() < deadline,
                        "connect to the daemon at {}: {err}",
                        self.socket.display()
                    );
                    thread::sleep(Duration::from_millis(10));
                }
            }
        };
        // A request waits for the other clients' jobs queued before it.
        stream
            .set_read_timeout(Some(Duration::from_secs(300)))
            .expect("set daemon socket read timeout");
        let mut session = DaemonSession {
            reader: BufReader::new(stream.try_clone().expect("clone daemon client socket")),
            writer: stream,
            ready: serde_json::Value::Null,
        };
        session.ready = session.response();
        assert_eq!(session.ready["event"], "ready");
        session
    }
}

/// One client of a socket daemon.
struct DaemonSession {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
    ready: serde_json::Value,
}

impl DaemonSession {
    fn send(&mut self, request: &serde_json::Value) {
        writeln!(self.writer, "{request}").expect("send daemon request");
        self.writer.flush().expect("flush daemon request");
    }

    fn response(&mut self) -> serde_json::Value {
        let mut line = String::new();
        self.reader
            .read_line(&mut line)
            .expect("read daemon response");
        serde_json::from_str(&line)
            .unwrap_or_else(|error| panic!("daemon response {line:?}: {error}"))
    }

    fn request(&mut self, request: &serde_json::Value) -> serde_json::Value {
        self.send(request);
        self.response()
    }

    fn compile_project(&mut self, project: &Path, output: &Path) -> serde_json::Value {
        self.request(&serde_json::json!({
            "id": "compile",
            "command": "compile",
            "emit": "x86_64",
            "input": project.join("main.lani"),
            "source_root": project.join("src"),
            "output": output,
        }))
    }

    fn compile_file(&mut self, emit: &str, input: &Path, output: &Path) -> serde_json::Value {
        self.request(&serde_json::json!({
            "id": "compile",
            "command": "compile",
            "emit": emit,
            "input": input,
            "output": output,
        }))
    }
}

/// Connects a client to the daemon that the tests in this file share. The
/// daemon serves both targets and runs the clients' requests one at a time,
/// so these tests need no lock. A test that asserts what a job allocates
/// starts its own daemon instead, because another client's job or trim
/// changes that.
///
/// The first client stays connected for as long as the test process runs.
/// The daemon exits when its last client disconnects, which is when this
/// process ends.
fn shared_daemon() -> DaemonSession {
    static SHARED: OnceLock<(SocketDaemon, DaemonSession)> = OnceLock::new();
    let (daemon, _first_client) = SHARED.get_or_init(|| {
        let daemon = SocketDaemon::start("shared");
        let first_client = daemon.connect();
        (daemon, first_client)
    });
    daemon.connect()
}

#[test]
fn cli_daemon_answers_each_socket_client_with_its_own_responses() {
    let first_source = common::TempArtifact::new("laniusc_daemon_clients", "first", Some("lani"));
    let second_source = common::TempArtifact::new("laniusc_daemon_clients", "second", Some("lani"));
    let first_artifact = common::TempArtifact::new("laniusc_daemon_clients", "first", None);
    let second_artifact = common::TempArtifact::new("laniusc_daemon_clients", "second", None);
    fs::write(
        first_source.path(),
        "fn main() -> i32 {\n    print(7);\n    return 0;\n}\n",
    )
    .expect("write the first client's source");
    fs::write(
        second_source.path(),
        "fn main() -> i32 {\n    print(9);\n    return 0;\n}\n",
    )
    .expect("write the second client's source");
    let compile = |id: &str, input: &Path, output: &Path| {
        serde_json::json!({
            "id": id,
            "command": "compile",
            "emit": "x86_64",
            "input": input,
            "output": output,
        })
    };

    let mut first = shared_daemon();
    let mut second = shared_daemon();
    // Both requests are queued before either response is read.
    first.send(&compile("first", first_source.path(), first_artifact.path()));
    second.send(&compile("second", second_source.path(), second_artifact.path()));
    let second_response = second.response();
    let first_response = first.response();
    assert_eq!(first_response["id"], "first");
    assert_eq!(first_response["ok"], true, "{first_response:#}");
    assert_eq!(second_response["id"], "second");
    assert_eq!(second_response["ok"], true, "{second_response:#}");
    assert_eq!(second.request(&serde_json::json!({"id": "s", "command": "status"}))["id"], "s");

    for (artifact, expected) in [(&first_artifact, "7\n"), (&second_artifact, "9\n")] {
        let run = common::short_process_output_with_timeout(
            "run a socket client's x86 artifact",
            &mut Command::new(artifact.path()),
        );
        common::assert_command_success("run a socket client's x86 artifact", &run);
        assert_eq!(String::from_utf8_lossy(&run.stdout), expected);
    }
}

#[test]
fn cli_daemon_links_a_native_executable_from_several_source_roots() {
    let fixture =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/cli_daemon/native_roots");
    let artifact = common::TempArtifact::new("laniusc_daemon_native", "artifact", None);
    let compile = |id: &str| {
        serde_json::json!({
            "id": id,
            "command": "compile",
            "emit": "x86_64",
            "input": fixture.join("app/main.lani"),
            "output": artifact.path(),
            "source_roots": [fixture.join("first_root"), fixture.join("second_root")],
            "native_link": true,
            "native_libraries": ["m"],
        })
    };
    let unknown = serde_json::json!({
        "id": "unknown",
        "command": "compile",
        "emit": "x86_64",
        "input": fixture.join("app/main.lani"),
        "output": artifact.path(),
        "linker_flags": ["-s"],
    });
    let both_roots = serde_json::json!({
        "id": "both_roots",
        "command": "compile",
        "emit": "x86_64",
        "input": fixture.join("app/main.lani"),
        "output": artifact.path(),
        "source_root": fixture.join("first_root"),
        "source_roots": [fixture.join("second_root")],
    });
    let mut session = shared_daemon();
    let capabilities = session.ready["capabilities"]
        .as_array()
        .expect("the ready event lists the request features")
        .clone();
    for capability in ["strict_request_fields", "source_roots", "native_link"] {
        assert!(
            capabilities.iter().any(|listed| listed == capability),
            "ready event does not list {capability}: {capabilities:?}"
        );
    }

    let response = session.request(&unknown);
    assert_eq!(response["id"], "unknown");
    assert_eq!(response["ok"], false);
    let message = response["protocol_error"]
        .as_str()
        .expect("an unknown request field is a protocol error");
    assert!(message.contains("unknown field `linker_flags`"), "{message}");

    let response = session.request(&both_roots);
    assert_eq!(response["id"], "both_roots");
    assert_eq!(response["ok"], false);
    let message = response["job_error"]
        .as_str()
        .expect("two root fields are a job error");
    assert!(message.contains("source_root and source_roots"), "{message}");

    for id in ["native", "repeat"] {
        let response = session.request(&compile(id));
        assert_eq!(response["id"], id);
        assert_eq!(response["ok"], true, "{response:#}");
        assert_eq!(response["native_link"], true);
        assert_eq!(response["source_roots"].as_array().map(Vec::len), Some(2));
        assert!(response["output_bytes"].as_u64().is_some_and(|bytes| bytes > 0));
    }

    // `abs` comes from libc, so the program runs only when it was linked.
    let status = Command::new(artifact.path())
        .status()
        .expect("run the daemon's native executable");
    assert_eq!(status.code(), Some(42));
}

#[test]
fn cli_daemon_reuses_one_process_to_emit_runnable_x86_artifact() {
    let source = common::temp_artifact_path("laniusc_daemon", "source", Some("lani"));
    let second_source = common::temp_artifact_path("laniusc_daemon", "second_source", Some("lani"));
    let invalid_source =
        common::temp_artifact_path("laniusc_daemon", "invalid_source", Some("lani"));
    let artifact = common::temp_artifact_path("laniusc_daemon", "artifact", None);
    let repeat_artifact = common::temp_artifact_path("laniusc_daemon", "repeat_artifact", None);
    let second_artifact = common::temp_artifact_path("laniusc_daemon", "second_artifact", None);
    let requests = common::temp_artifact_path("laniusc_daemon", "requests", Some("jsonl"));
    fs::write(
        &source,
        "fn main() -> i32 {\n    print(7);\n    return 0;\n}\n",
    )
    .expect("write daemon source fixture");
    fs::write(
        &second_source,
        "fn main() -> i32 {\n    print(9);\n    return 0;\n}\n",
    )
    .expect("write second daemon source fixture");
    fs::write(
        &invalid_source,
        "fn main() -> i32 {\n    print(8);\n    return 0;\n",
    )
    .expect("write invalid daemon source fixture");
    let missing = serde_json::json!({
        "id": "missing",
        "command": "compile",
        "emit": "x86_64",
        "input": source.with_extension("missing"),
        "output": artifact,
    });
    let compile = serde_json::json!({
        "id": "compile",
        "command": "compile",
        "emit": "x86_64",
        "input": source,
        "output": artifact,
    });
    let second_compile = serde_json::json!({
        "id": "second_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": second_source,
        "output": second_artifact,
    });
    let repeat_compile = serde_json::json!({
        "id": "repeat_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": source,
        "output": repeat_artifact,
    });
    let invalid_compile = serde_json::json!({
        "id": "invalid_compile",
        "command": "compile",
        "emit": "x86_64",
        "input": invalid_source,
        "output": second_artifact.with_extension("invalid"),
    });
    let trim = serde_json::json!({"id": "trim", "command": "trim"});
    let shutdown = serde_json::json!({"id": "shutdown", "command": "shutdown"});
    fs::write(
        &requests,
        format!(
            "{missing}\n{compile}\n{repeat_compile}\n{invalid_compile}\n{trim}\n{second_compile}\n{shutdown}\n"
        ),
    )
    .expect("write daemon request fixture");

    let stdin = fs::File::open(&requests).expect("open daemon request fixture");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("daemon")
        .arg("--stdio")
        .arg("--backend")
        .arg("x86_64")
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
        .env("LANIUS_REPORT", "host-timing")
        .stdin(Stdio::from(stdin));
    let output =
        common::codegen_command_output_with_timeout("laniusc daemon x86 job", &mut command);
    common::assert_command_success("laniusc daemon x86 job", &output);
    let daemon_stderr = String::from_utf8_lossy(&output.stderr).into_owned();

    let responses = String::from_utf8(output.stdout)
        .expect("daemon stdout should be UTF-8")
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).expect("daemon response JSON"))
        .collect::<Vec<_>>();
    assert_eq!(
        responses.len(),
        8,
        "ready, recoverable file error, split compile, fused repeat compile, syntax error, trim, post-trim compile, and shutdown responses"
    );
    assert_eq!(responses[0]["event"], "ready");
    assert!(
        responses[0]["resident_set_bytes"]
            .as_u64()
            .is_some_and(|bytes| bytes > 0)
    );
    assert!(
        responses[0]["tracked_gpu_buffers"]["allocations"]
            .as_u64()
            .is_some_and(|count| count > 0)
    );
    assert!(
        responses[0]["tracked_gpu_buffers"]["bytes"]
            .as_u64()
            .is_some_and(|bytes| bytes > 0)
    );
    assert!(responses[0]["wgpu_resources"]["buffers"].is_object());
    assert!(
        responses[0]["compute_pipelines_created"]
            .as_u64()
            .is_some_and(|count| count > 0)
    );
    assert_eq!(responses[1]["id"], "missing");
    assert_eq!(responses[1]["ok"], false);
    assert!(responses[1]["diagnostic"].is_object());
    assert_eq!(responses[2]["id"], "compile");
    assert_eq!(
        responses[2]["ok"], true,
        "compile response: {}\ndaemon stderr:\n{}",
        responses[2], daemon_stderr,
    );
    assert_eq!(responses[2]["emit"], "x86_64");
    for response in [&responses[2], &responses[3], &responses[4], &responses[6]] {
        assert_eq!(
            response["resources_created_during_job"]["compute_pipelines"], 0,
            "daemon compilation jobs must not create pipelines after readiness: {response}"
        );
    }
    assert_eq!(
        responses[2]["workspace_request_kind"],
        "cold_or_grown_workspace"
    );
    assert_eq!(
        responses[3]["workspace_request_kind"], "retained_capacity",
        "repeat job created resources: {}",
        responses[3]
    );
    assert_eq!(responses[3]["resources_created_during_job"]["buffers"], 0);
    assert_eq!(
        responses[3]["resources_created_during_job"]["bind_groups"],
        0
    );
    for phase in ["resource_plan", "cache", "wgpu_create"] {
        assert!(
            responses[2]["bind_group_timing_ms"][phase]
                .as_f64()
                .is_some_and(|ms| ms >= 0.0),
            "cold daemon response should report bind-group {phase} time"
        );
    }
    assert_eq!(
        responses[3]["bind_group_timing_ms"]["wgpu_create"], 0.0,
        "warm retained-capacity job must not call Device::create_bind_group"
    );
    assert!(
        responses[0]["startup_ms"]
            .as_f64()
            .is_some_and(|ms| ms < 60_000.0),
        "daemon must eagerly create every pipeline and become ready within 60 seconds: {}",
        responses[0]
    );
    assert!(responses[2]["tracked_gpu_buffers"].is_object());
    assert!(responses[2]["wgpu_resources"]["command_buffers"].is_object());
    assert!(
        responses[2]["elapsed_ms"]
            .as_f64()
            .is_some_and(|ms| ms > 0.0)
    );
    for field in ["load_ms", "compile_ms", "write_ms"] {
        assert!(
            responses[2][field].as_f64().is_some_and(|ms| ms >= 0.0),
            "successful compile response should contain nonnegative {field}"
        );
    }
    assert_eq!(responses[3]["id"], "repeat_compile");
    assert_eq!(responses[3]["ok"], true);
    assert_eq!(responses[3]["emit"], "x86_64");
    assert_eq!(responses[4]["id"], "invalid_compile");
    assert_eq!(responses[4]["ok"], false);
    assert!(responses[4]["diagnostic"].is_object());
    assert_eq!(responses[5]["id"], "trim");
    assert_eq!(responses[5]["ok"], true);
    assert_eq!(responses[5]["event"], "trimmed");
    let tracked_before_trim = responses[5]["tracked_gpu_buffers_before"]["bytes"]
        .as_u64()
        .expect("trim response should report tracked bytes before release");
    let tracked_after_trim = responses[5]["tracked_gpu_buffers"]["bytes"]
        .as_u64()
        .expect("trim response should report tracked bytes after release");
    assert!(
        tracked_after_trim < tracked_before_trim,
        "trim should release job-sized tracked buffers: before={tracked_before_trim} after={tracked_after_trim}"
    );
    assert_eq!(responses[6]["id"], "second_compile");
    assert_eq!(responses[6]["ok"], true);
    assert_eq!(responses[6]["emit"], "x86_64");
    assert_eq!(
        responses[6]["workspace_request_kind"],
        "cold_or_grown_workspace"
    );
    assert_eq!(responses[7]["event"], "shutdown");

    for path in [&artifact, &repeat_artifact, &second_artifact] {
        common::x86_jumps::assert_x86_64_file_jumps_stay_in_functions(path);
    }
    let run = common::short_process_output_with_timeout(
        "run daemon-emitted x86 artifact",
        &mut Command::new(&artifact),
    );
    common::assert_command_success("run daemon-emitted x86 artifact", &run);
    assert_eq!(run.stdout, b"7\n");

    let repeat_run = common::short_process_output_with_timeout(
        "run repeat daemon-emitted x86 artifact",
        &mut Command::new(&repeat_artifact),
    );
    common::assert_command_success("run repeat daemon-emitted x86 artifact", &repeat_run);
    assert_eq!(repeat_run.stdout, b"7\n");

    let second_run = common::short_process_output_with_timeout(
        "run second daemon-emitted x86 artifact",
        &mut Command::new(&second_artifact),
    );
    common::assert_command_success("run second daemon-emitted x86 artifact", &second_run);
    assert_eq!(second_run.stdout, b"9\n");

    let _ = fs::remove_file(source);
    let _ = fs::remove_file(second_source);
    let _ = fs::remove_file(invalid_source);
    let _ = fs::remove_file(artifact);
    let _ = fs::remove_file(repeat_artifact);
    let _ = fs::remove_file(second_artifact);
    let _ = fs::remove_file(requests);
}

#[test]
fn cli_daemon_traced_compile_stamps_every_dispatch() {
    let source = common::temp_artifact_path("laniusc_daemon_trace", "source", Some("lani"));
    let artifact = common::temp_artifact_path("laniusc_daemon_trace", "artifact", None);
    let repeat_artifact = common::temp_artifact_path("laniusc_daemon_trace", "repeat", None);
    let trace = common::temp_artifact_path("laniusc_daemon_trace", "trace", Some("json"));
    let requests = common::temp_artifact_path("laniusc_daemon_trace", "requests", Some("jsonl"));
    fs::write(
        &source,
        "fn main() -> i32 {\n    print(7);\n    return 0;\n}\n",
    )
    .expect("write traced daemon source fixture");
    let compile = |id: &str, output: &PathBuf| {
        serde_json::json!({
            "id": id,
            "command": "compile",
            "emit": "x86_64",
            "input": source,
            "output": output,
        })
    };
    let shutdown = serde_json::json!({"id": "shutdown", "command": "shutdown"});
    fs::write(
        &requests,
        format!(
            "{}\n{}\n{shutdown}\n",
            compile("cold", &artifact),
            compile("warm", &repeat_artifact)
        ),
    )
    .expect("write traced daemon request fixture");

    let stdin = fs::File::open(&requests).expect("open traced daemon request fixture");
    let mut command = Command::new(laniusc_bin());
    command
        .arg("daemon")
        .arg("--stdio")
        .arg("--backend")
        .arg("x86_64")
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
        .env("LANIUS_PERFETTO_TRACE", &trace)
        .stdin(Stdio::from(stdin));
    let output =
        common::codegen_command_output_with_timeout("laniusc traced daemon job", &mut command);
    common::assert_command_success("laniusc traced daemon job", &output);
    let daemon_stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let responses = String::from_utf8(output.stdout)
        .expect("daemon stdout should be UTF-8")
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).expect("daemon response JSON"))
        .collect::<Vec<_>>();

    assert_eq!(responses.len(), 4, "ready, two compiles and shutdown: {responses:?}");
    for response in &responses[1..3] {
        // A traced job fails unless every recorded dispatch has a timestamp.
        assert_eq!(
            response["ok"], true,
            "traced compile response: {response}\ndaemon stderr:\n{daemon_stderr}"
        );
        let dispatches = response["recorded_compute_dispatches_during_job"]
            .as_u64()
            .expect("traced compile reports its dispatches");
        assert!(dispatches > 0, "traced compile recorded no dispatches: {response}");
        assert_eq!(
            response["operation_timestamps_during_job"].as_u64(),
            Some(dispatches),
            "traced compile response: {response}"
        );
    }
    let trace_text = fs::read_to_string(&trace).expect("daemon writes the trace at shutdown");
    for job in ["daemon.job.cold", "daemon.job.warm"] {
        assert!(trace_text.contains(job), "trace has no {job} span");
    }
    for path in [&artifact, &repeat_artifact] {
        let run = common::short_process_output_with_timeout(
            "run traced daemon-emitted x86 artifact",
            &mut Command::new(path),
        );
        common::assert_command_success("run traced daemon-emitted x86 artifact", &run);
        assert_eq!(run.stdout, b"7\n");
    }

    for path in [source, artifact, repeat_artifact, trace, requests] {
        let _ = fs::remove_file(path);
    }
}

#[test]
fn cli_daemon_emits_a_runnable_wasm_artifact() {
    common::require_node();

    let source = common::TempArtifact::new("laniusc_daemon_wasm", "source", Some("lani"));
    let artifact = common::TempArtifact::new("laniusc_daemon_wasm", "artifact", Some("wasm"));
    fs::write(
        source.path(),
        "fn main() -> i32 {\n    print(7);\n    return 0;\n}\n",
    )
    .expect("write daemon Wasm source fixture");

    let mut session = shared_daemon();
    assert_eq!(session.ready["targets"], serde_json::json!(["x86_64", "wasm"]));
    let response = session.compile_file("wasm", source.path(), artifact.path());
    assert_eq!(response["ok"], true, "Wasm daemon compile failed: {response}");
    assert_eq!(response["emit"], "wasm");
    assert_eq!(
        response["resources_created_during_job"]["compute_pipelines"], 0,
        "daemon Wasm jobs must not create pipelines after readiness: {response}"
    );

    let wasm = fs::read(artifact.path()).expect("read daemon Wasm artifact");
    let stdout = common::run_wasm_main_with_node("daemon Wasm job", "daemon_wasm_job", &wasm);
    assert_eq!(stdout, "7\n");
}

// A warm daemon keeps a project's parser shape between jobs. An edit that
// removes tokens (padding functions deleted, or turned into spaces so the
// bytes stay the same) must compile exactly as a fresh daemon compiles the
// edited files; a shrinking comment, which removes no tokens, is the
// control. The reference is the same daemon after a trim: a trim frees the
// resident buffers, so the job after it holds no more token capacity than it
// needs, as a fresh daemon's first job does. The project reads fields through imported generic records, the
// shape that went wrong when a warm job's token capacity exceeded its count.
#[test]
fn cli_daemon_matches_a_trimmed_daemon_after_edits_that_remove_tokens() {
    let mut session = shared_daemon();
    let padding: String = (0..60)
        .map(|index| {
            format!(
                "fn pad_{index}(x: i32) -> i32 {{ let y: i32 = x + {index}; return (y * 3 + 1) & 1023; }}\n"
            )
        })
        .collect();
    let spaces: String = padding
        .chars()
        .map(|c| if c == '\n' { c } else { ' ' })
        .collect();
    let comment: String = padding.lines().map(|line| format!("// {line}\n")).collect();
    let extract = "module lib::extract;\nimport lib::inner;\nimport lib::outer;\n\
        pub fn take<T>(value: lib::outer::Wrap<T>) -> T { return value.child.value; }\n";
    let main = "module app::main;
import lib::inner;
import lib::outer;
import lib::extract;
fn main() -> i32 {
    let original: lib::outer::Wrap<[i32; 2]> = Wrap {
        child: Boxed { value: [19, 23], code: 7 }, marker: 11
    };
    let extracted: [i32; 2] = lib::extract::take(original);
    extracted[0] = -9;
    if (original.child.value[0] != 19 || original.child.code != 7 || original.marker != 11) {
        return 1;
    }
    let saved = original;
    original.child.value[1] = -3;
    original.child.code = 99;
    if (saved.child.code != 7 || saved.child.value[1] != 23 || extracted[1] != 23) {
        return 2;
    }
    return saved.child.value[0] + saved.child.value[1];
}
";
    for (edit, big, small) in [
        ("tokens removed", padding.as_str(), ""),
        ("tokens turned into spaces", padding.as_str(), spaces.as_str()),
        ("comment removed", comment.as_str(), ""),
    ] {
        let project = common::temp_artifact_path("laniusc_daemon_shrink", edit, None);
        let lib = project.join("src/lib");
        fs::create_dir_all(&lib).expect("create shrink project");
        fs::write(
            lib.join("inner.lani"),
            "module lib::inner;\npub struct Boxed<T> { value: T, code: i32 }\n",
        )
        .expect("write lib::inner");
        fs::write(
            lib.join("outer.lani"),
            "module lib::outer;\nimport lib::inner;\npub struct Wrap<T> { child: lib::inner::Boxed<T>, marker: i32 }\n",
        )
        .expect("write lib::outer");
        fs::write(project.join("main.lani"), main).expect("write app::main");
        let extract_path = lib.join("extract.lani");
        fs::write(&extract_path, format!("{extract}{big}")).expect("write padded lib::extract");
        let warm = project.join("warm");
        let fresh = project.join("fresh");

        let response = session.compile_project(&project, &warm);
        assert_eq!(response["ok"], true, "{edit}: padded project: {response}");
        fs::write(&extract_path, format!("{extract}{small}")).expect("write edited lib::extract");
        let response = session.compile_project(&project, &warm);
        assert_eq!(
            response["ok"], true,
            "{edit}: warm daemon after the edit: {response}"
        );
        // Queued together, so that another client's job seldom runs between.
        session.send(&serde_json::json!({"id": "trim", "command": "trim"}));
        let response = session.compile_project(&project, &fresh);
        assert_eq!(response["event"], "trimmed", "{edit}: {response}");
        let response = session.response();
        assert_eq!(response["ok"], true, "{edit}: after a trim: {response}");

        assert!(
            fs::read(&warm).expect("read warm artifact")
                == fs::read(&fresh).expect("read fresh artifact"),
            "{edit}: the warm job's artifact differs from the job after a trim"
        );
        let run = common::short_process_output_with_timeout(
            format!("run the {edit} artifact"),
            &mut Command::new(&warm),
        );
        assert_eq!(run.status.code(), Some(42), "{edit}: exit status");
        let _ = fs::remove_dir_all(project);
    }
}

// The first job of a fresh daemon once typed `original.value` as i32 or as
// unknown depending on warp order: type_checker/scope/hir read a struct
// declaration's visible type while that declaration's own lane was writing
// it (2026-10-19; about one fresh daemon in three emitted an extra spill
// pair). A trim frees the resident buffers, so the job after it starts from
// new, zeroed buffers as a fresh daemon's first job does. Every such job
// must emit the same bytes for the same source.
#[test]
fn cli_daemon_first_jobs_after_a_trim_emit_identical_artifacts() {
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
        "tests/fixtures/stdlib_foundation/repro_nominal_parameter_after_field_assignment.lani",
    );
    let mut session = shared_daemon();
    let mut first: Option<Vec<u8>> = None;
    for round in 0..8 {
        let output = common::temp_artifact_path(
            "laniusc_daemon_fresh_first_job",
            &round.to_string(),
            None,
        );
        // Queued together, so that another client's job seldom runs between.
        session.send(&serde_json::json!({"id": "trim", "command": "trim"}));
        let response = session.compile_file("x86_64", &input, &output);
        assert_eq!(response["event"], "trimmed", "round {round}: {response}");
        let response = session.response();
        assert_eq!(response["ok"], true, "round {round}: {response}");
        let bytes = fs::read(&output).expect("read the artifact");
        if round == 0 {
            let run = common::short_process_output_with_timeout(
                "run the first-job artifact",
                &mut Command::new(&output),
            );
            assert_eq!(run.status.code(), Some(0), "first-job artifact exit status");
        }
        let _ = fs::remove_file(&output);
        match &first {
            Some(expected) => assert!(
                *expected == bytes,
                "round {round} emitted {} bytes; the first emitted {}",
                bytes.len(),
                expected.len()
            ),
            None => first = Some(bytes),
        }
    }
}

/// The daemons that one-shot compiles started under a private runtime
/// directory. Dropping this asks each one to shut down and removes the
/// directory.
struct OneShotDaemons {
    runtime: PathBuf,
}

impl OneShotDaemons {
    fn sockets(&self) -> Vec<PathBuf> {
        let Ok(entries) = fs::read_dir(self.runtime.join("laniusc-daemons")) else {
            return Vec::new();
        };
        entries
            .filter_map(|entry| Some(entry.ok()?.path()))
            .filter(|path| path.extension().is_some_and(|extension| extension == "sock"))
            .collect()
    }

    /// Connects to the daemon on `socket` and returns its process id.
    fn pid(socket: &Path) -> u64 {
        let stream = UnixStream::connect(socket).expect("connect to the shared daemon");
        let mut ready = String::new();
        BufReader::new(&stream).read_line(&mut ready).expect("read the ready event");
        let ready: serde_json::Value = serde_json::from_str(&ready).expect("parse the ready event");
        ready["pid"].as_u64().expect("the ready event names the daemon's process")
    }
}

impl Drop for OneShotDaemons {
    fn drop(&mut self) {
        for socket in self.sockets() {
            if let Ok(stream) = UnixStream::connect(&socket) {
                let mut lines = BufReader::new(&stream);
                let mut line = String::new();
                let _ = lines.read_line(&mut line);
                let _ = (&stream).write_all(b"{\"id\":\"end\",\"command\":\"shutdown\"}\n");
                let _ = lines.read_line(&mut line);
            }
        }
        let _ = fs::remove_dir_all(&self.runtime);
    }
}

#[test]
fn cli_compile_runs_in_the_shared_daemon_of_its_build() {
    // A runtime directory of this test's own. A developer's compiles do not
    // reach the daemon started here, and `systemd-run --user` finds no bus
    // under it, so the daemon is a plain child that the test can stop. The
    // name is short: a socket path holds about 100 bytes.
    let daemons = OneShotDaemons {
        runtime: env::temp_dir().join(format!("lsd-{}", std::process::id())),
    };
    let project = daemons.runtime.join("project");
    fs::create_dir_all(&project).expect("create the project directory");
    fs::write(project.join("good.lani"), "fn main() -> i32 { return 42; }\n")
        .expect("write the source that compiles");
    fs::write(project.join("other.lani"), "fn main() -> i32 { return 7; }\n")
        .expect("write the second source that compiles");
    fs::write(project.join("bad.lani"), "fn main() -> i32 { return 41 }\n")
        .expect("write the source with a syntax error");
    let compile = |flags: &[&str], input: &str, output: &str| {
        let mut command = Command::new(laniusc_bin());
        command
            .current_dir(&project)
            .env("XDG_RUNTIME_DIR", &daemons.runtime)
            .args(flags)
            .args(["--emit", "x86_64", "--stdlib-root"])
            .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"))
            .args(["-o", output, input]);
        // A diagnostic option keeps a compile in its own process.
        for name in [
            "LANIUS_DAEMON",
            "LANIUS_TRACE",
            "LANIUS_REPORT",
            "LANIUS_CHECK",
            "LANIUS_EXPERIMENT",
            "LANIUS_PERFETTO_TRACE",
            "LANIUS_CAPTURE",
            "LANIUS_DUMP",
            "LANIUS_OPERATION_LIMIT",
        ] {
            command.env_remove(name);
        }
        common::command_output_with_timeout("one-shot compile", &mut command)
    };
    let exit_code = |artifact: &str| {
        common::short_process_output_with_timeout(
            "run a one-shot compile's artifact",
            &mut Command::new(project.join(artifact)),
        )
        .status
        .code()
    };

    // The first compile starts the daemon. The second one finds it.
    let first = compile(&[], "good.lani", "good");
    common::assert_command_success("first one-shot compile", &first);
    assert_eq!(exit_code("good"), Some(42));
    let sockets = daemons.sockets();
    assert_eq!(sockets.len(), 1, "one daemon serves x86_64 for this build: {sockets:?}");
    let daemon = OneShotDaemons::pid(&sockets[0]);
    let second = compile(&[], "other.lani", "other");
    common::assert_command_success("second one-shot compile", &second);
    assert_eq!(exit_code("other"), Some(7));
    assert_eq!(daemons.sockets(), sockets);
    assert_eq!(OneShotDaemons::pid(&sockets[0]), daemon, "the second compile reused the daemon");

    // The daemon and a compile in the client's own process agree on the
    // artifact and on the diagnostic, including the path as it was typed.
    let local = compile(&["--no-daemon"], "good.lani", "good_local");
    common::assert_command_success("compile in the client's process", &local);
    assert_eq!(
        fs::read(project.join("good")).expect("read the daemon's artifact"),
        fs::read(project.join("good_local")).expect("read the local artifact"),
    );
    let rejected = compile(&[], "bad.lani", "bad");
    let rejected_locally = compile(&["--no-daemon"], "bad.lani", "bad_local");
    assert_eq!(rejected.status.code(), Some(1));
    assert_eq!(rejected_locally.status.code(), Some(1));
    let diagnostic = String::from_utf8_lossy(&rejected.stderr);
    assert!(diagnostic.contains("--> bad.lani:1:30"), "{diagnostic}");
    assert_eq!(diagnostic, String::from_utf8_lossy(&rejected_locally.stderr));
    let json = compile(&["--diagnostic-format", "json"], "bad.lani", "bad");
    let json_locally = compile(&["--no-daemon", "--diagnostic-format", "json"], "bad.lani", "bad");
    assert_eq!(
        String::from_utf8_lossy(&json.stderr),
        String::from_utf8_lossy(&json_locally.stderr),
    );
    assert_eq!(OneShotDaemons::pid(&sockets[0]), daemon, "a rejected compile keeps the daemon");
}
