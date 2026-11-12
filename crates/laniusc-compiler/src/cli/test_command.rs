//! `laniusc test`: compiles and runs test programs through one resident
//! compiler.
//!
//! A test is a `.lani` file whose leading comment lines hold `//@`
//! directives. The command is a client of the daemon session loop inside this
//! process, so every file takes the compile path of a daemon request. Compiles
//! run one at a time; the compiled programs run on worker threads.

use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{Arc, Mutex, mpsc},
    thread,
    time::{Duration, Instant},
};

use serde_json::{Value, json};

use super::{
    common::{CliError, missing_cli_option_value_error, unknown_cli_option_error},
    daemon,
};

const DIRECTIVE: &str = "//@";
const DEFAULT_RUN_TIMEOUT_MS: u64 = 10_000;

/// What a test file states about its own outcome.
#[derive(Debug, Default, PartialEq, Eq)]
struct Expectation {
    /// Exit code of the program. Zero unless `exit` names another.
    exit: i32,
    /// The signal that ends the program, in place of an exit code.
    signal: Option<i32>,
    /// Lines the program must write to standard output, when any is given.
    stdout: Option<String>,
    /// Lines the program must write to standard error, when any is given.
    stderr: Option<String>,
    /// Texts the compile diagnostic must contain. Not empty: the compile fails.
    errors: Vec<String>,
    /// User source roots, relative to the directory of the test file.
    source_roots: Vec<PathBuf>,
}

struct TestCase {
    path: PathBuf,
    expect: Expectation,
}

struct Options {
    stdlib_root: PathBuf,
    paths: Vec<PathBuf>,
    filter: Option<String>,
    jobs: usize,
    run_timeout: Duration,
    verbose: bool,
}

enum Outcome {
    Passed,
    Failed(String),
}

pub(super) fn run(args: Vec<String>) -> Result<(), CliError> {
    if args.iter().any(|arg| matches!(arg.as_str(), "-h" | "--help")) {
        print_help();
        return Ok(());
    }
    if !cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        return Err(CliError::from(
            "laniusc test runs the programs it compiles, which needs an x86_64 Linux host",
        ));
    }
    let options = parse_options(args)?;
    let tests = discover(&options)?;
    if tests.is_empty() {
        return Err(CliError::from(
            "laniusc test found no test: a test is a .lani file that starts with a `//@` directive",
        ));
    }
    let out_dir = std::env::temp_dir().join(format!("laniusc-test-{}", std::process::id()));
    fs::create_dir_all(&out_dir)
        .map_err(|err| CliError::from(format!("create {}: {err}", out_dir.display())))?;

    let started = Instant::now();
    let tests = Arc::new(tests);
    let (run_sender, run_receiver) = mpsc::channel::<(usize, PathBuf)>();
    let (outcome_sender, outcome_receiver) = mpsc::channel::<(usize, Outcome)>();
    let run_receiver = Arc::new(Mutex::new(run_receiver));
    let workers: Vec<_> = (0..options.jobs)
        .map(|_| {
            let tests = tests.clone();
            let run_receiver = run_receiver.clone();
            let outcome_sender = outcome_sender.clone();
            let timeout = options.run_timeout;
            thread::spawn(move || {
                loop {
                    let job = run_receiver.lock().expect("run queue").recv();
                    let Ok((index, program)) = job else { break };
                    let outcome = run_and_check(&program, &tests[index].expect, timeout);
                    if outcome_sender.send((index, outcome)).is_err() {
                        break;
                    }
                }
            })
        })
        .collect();

    let mut driver = Driver {
        tests: tests.clone(),
        next: 0,
        response: Vec::new(),
        out_dir: out_dir.clone(),
        run_sender,
        outcome_sender,
        startup_ms: 0.0,
        compile_ms: vec![0.0; tests.len()],
    };
    let session = daemon::run_in_process(options.stdlib_root.clone(), &mut driver);
    let startup_ms = driver.startup_ms;
    let compile_ms = std::mem::take(&mut driver.compile_ms);
    // Dropping the driver closes both queues: the workers finish the programs
    // already queued and the outcome channel ends after the last one.
    drop(driver);
    let mut outcomes: Vec<Option<Outcome>> = tests.iter().map(|_| None).collect();
    for (index, outcome) in outcome_receiver {
        outcomes[index] = Some(outcome);
    }
    for worker in workers {
        let _ = worker.join();
    }
    let _ = fs::remove_dir_all(&out_dir);
    session?;

    let mut failed = 0usize;
    for (index, (test, outcome)) in tests.iter().zip(&outcomes).enumerate() {
        match outcome {
            Some(Outcome::Passed) => {
                if options.verbose {
                    println!("ok   {} (compile {:.0} ms)", test.path.display(), compile_ms[index]);
                }
            }
            Some(Outcome::Failed(reason)) => {
                failed += 1;
                println!("FAIL {}", test.path.display());
                for line in reason.lines() {
                    println!("  {line}");
                }
            }
            None => {
                failed += 1;
                println!("FAIL {}\n  the compiler session ended before this test", test.path.display());
            }
        }
    }
    println!(
        "test result: {}. {} passed; {failed} failed; {:.2} s (compiler start {:.2} s, compiles {:.2} s)",
        if failed == 0 { "ok" } else { "FAILED" },
        tests.len() - failed,
        started.elapsed().as_secs_f64(),
        startup_ms / 1000.0,
        compile_ms.iter().sum::<f64>() / 1000.0,
    );
    if failed != 0 {
        // The result line already says what failed. Returning an error would
        // add a diagnostic about the command itself.
        let _ = io::stdout().flush();
        std::process::exit(1);
    }
    Ok(())
}

fn print_help() {
    eprintln!(
        "Usage: laniusc test [--stdlib-root dir] [--filter text] [--jobs n] [--run-timeout-ms n] [--verbose] <path>...\n\
         Compiles every test below each path with one resident compiler, runs each program and checks the outcome.\n\
         A path is a .lani file or a directory, which is searched recursively.\n\
         A test is a .lani file whose leading `//` comment lines hold at least one directive:\n\
         \x20 //@ exit N            the program exits with code N (0 when the file has no exit directive)\n\
         \x20 //@ signal N          the program is ended by signal N, in place of an exit code\n\
         \x20 //@ stdout TEXT       one line of standard output; several directives give several lines\n\
         \x20 //@ stderr TEXT       one line of standard error, in the same way\n\
         \x20 //@ error TEXT        the compile fails and its diagnostic contains TEXT; may repeat\n\
         \x20 //@ source-root DIR   a user source root, relative to the directory of the file; may repeat\n\
         A .lani file without a directive is a module of some test and is not compiled alone.\n\
         --stdlib-root defaults to ./stdlib. --filter keeps the tests whose path contains the text.\n\
         --jobs is the number of programs run at once. The exit status is 0 when every test passes."
    );
}

fn parse_options(args: Vec<String>) -> Result<Options, CliError> {
    let mut options = Options {
        stdlib_root: PathBuf::from("stdlib"),
        paths: Vec::new(),
        filter: None,
        jobs: thread::available_parallelism().map_or(4, |count| count.get()),
        run_timeout: Duration::from_millis(DEFAULT_RUN_TIMEOUT_MS),
        verbose: false,
    };
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let mut value = |what: &str| {
            args.next()
                .ok_or_else(|| missing_cli_option_value_error(&arg, what))
        };
        match arg.as_str() {
            "--stdlib-root" => options.stdlib_root = PathBuf::from(value("a directory")?),
            "--filter" => options.filter = Some(value("a text")?),
            "--jobs" => options.jobs = positive_number(&arg, &value("a count")?)?,
            "--run-timeout-ms" => {
                options.run_timeout =
                    Duration::from_millis(positive_number(&arg, &value("milliseconds")?)? as u64);
            }
            "--verbose" | "-v" => options.verbose = true,
            flag if flag.starts_with('-') => {
                return Err(unknown_cli_option_error(
                    "laniusc test",
                    flag,
                    "--stdlib-root, --filter, --jobs, --run-timeout-ms, --verbose",
                ));
            }
            _ => options.paths.push(PathBuf::from(arg)),
        }
    }
    if options.paths.is_empty() {
        return Err(CliError::from("laniusc test needs at least one file or directory"));
    }
    Ok(options)
}

fn positive_number(flag: &str, value: &str) -> Result<usize, CliError> {
    match value.parse::<usize>() {
        Ok(number) if number > 0 => Ok(number),
        _ => Err(CliError::from(format!(
            "{flag} needs a whole number above zero, but the value is {value:?}"
        ))),
    }
}

/// The tests below the paths of `options`, in path order.
fn discover(options: &Options) -> Result<Vec<TestCase>, CliError> {
    let mut files = Vec::new();
    for path in &options.paths {
        let path = fs::canonicalize(path)
            .map_err(|err| CliError::from(format!("read {}: {err}", path.display())))?;
        if path.is_dir() {
            collect_lani_files(&path, &mut files)?;
        } else {
            files.push(path);
        }
    }
    files.sort();
    files.dedup();
    let mut tests = Vec::new();
    for path in files {
        if let Some(filter) = &options.filter
            && !path.to_string_lossy().contains(filter.as_str())
        {
            continue;
        }
        let source = fs::read_to_string(&path)
            .map_err(|err| CliError::from(format!("read {}: {err}", path.display())))?;
        let expect = parse_directives(&source)
            .map_err(|(line, message)| {
                CliError::from(format!("{}:{line}: {message}", path.display()))
            })?;
        if let Some(expect) = expect {
            tests.push(TestCase { path, expect });
        }
    }
    Ok(tests)
}

fn collect_lani_files(dir: &Path, files: &mut Vec<PathBuf>) -> Result<(), CliError> {
    let entries =
        fs::read_dir(dir).map_err(|err| CliError::from(format!("read {}: {err}", dir.display())))?;
    for entry in entries {
        let path = entry
            .map_err(|err| CliError::from(format!("read {}: {err}", dir.display())))?
            .path();
        if path.is_dir() {
            collect_lani_files(&path, files)?;
        } else if path.extension().and_then(|extension| extension.to_str()) == Some("lani") {
            files.push(path);
        }
    }
    Ok(())
}

/// Reads the directives in the leading comment lines of `source`. Returns
/// `None` for a file without a directive. An error is a 1-based line number
/// and a message.
fn parse_directives(source: &str) -> Result<Option<Expectation>, (usize, String)> {
    let mut expect = Expectation::default();
    let mut found = false;
    let mut exit_given = false;
    for (index, line) in source.lines().enumerate() {
        let line = line.trim();
        if !line.is_empty() && !line.starts_with("//") {
            break;
        }
        let Some(directive) = line.strip_prefix(DIRECTIVE) else {
            continue;
        };
        found = true;
        let directive = directive.strip_prefix(' ').unwrap_or(directive);
        let (name, value) = directive.split_once(' ').unwrap_or((directive, ""));
        let fail = |message: String| (index + 1, message);
        match name {
            "exit" => {
                expect.exit = value
                    .trim()
                    .parse()
                    .map_err(|_| fail(format!("`exit` needs an exit code, but found {value:?}")))?;
                exit_given = true;
            }
            "signal" => {
                expect.signal = Some(value.trim().parse().map_err(|_| {
                    fail(format!("`signal` needs a signal number, but found {value:?}"))
                })?);
            }
            "stdout" | "stderr" => {
                let stream = if name == "stdout" { &mut expect.stdout } else { &mut expect.stderr };
                let text = stream.get_or_insert_with(String::new);
                text.push_str(value);
                text.push('\n');
            }
            "error" if value.trim().is_empty() => {
                return Err(fail("`error` needs the text the diagnostic must contain".into()));
            }
            "error" => expect.errors.push(value.trim().to_owned()),
            "source-root" if value.trim().is_empty() => {
                return Err(fail("`source-root` needs a directory".into()));
            }
            "source-root" => expect.source_roots.push(PathBuf::from(value.trim())),
            _ => {
                return Err(fail(format!(
                    "unknown directive {name:?}; the directives are exit, signal, stdout, stderr, error and source-root"
                )));
            }
        }
    }
    if exit_given && expect.signal.is_some() {
        return Err((1, "a program ends with an exit code or a signal, so a test has `exit` or `signal`, not both".into()));
    }
    let runs =
        exit_given || expect.signal.is_some() || expect.stdout.is_some() || expect.stderr.is_some();
    if !expect.errors.is_empty() && runs {
        return Err((
            1,
            "a test with `error` does not run, so it cannot also have `exit`, `signal`, `stdout` or `stderr`"
                .into(),
        ));
    }
    Ok(found.then_some(expect))
}

/// The session client: sends one compile request per test and handles each
/// response before the next request.
struct Driver {
    tests: Arc<Vec<TestCase>>,
    next: usize,
    response: Vec<u8>,
    out_dir: PathBuf,
    run_sender: mpsc::Sender<(usize, PathBuf)>,
    outcome_sender: mpsc::Sender<(usize, Outcome)>,
    startup_ms: f64,
    /// Compile time of each test, in milliseconds.
    compile_ms: Vec<f64>,
}

impl Driver {
    fn program_path(&self, index: usize) -> PathBuf {
        self.out_dir.join(format!("test-{index}"))
    }

    fn handle_response(&mut self, response: &Value) {
        let Some(index) = response.get("id").and_then(Value::as_u64).map(|id| id as usize) else {
            return;
        };
        let Some(test) = self.tests.get(index) else {
            return;
        };
        self.compile_ms[index] = response.get("elapsed_ms").and_then(Value::as_f64).unwrap_or(0.0);
        let compiled = response.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let outcome = match (compiled, test.expect.errors.is_empty()) {
            (true, true) => {
                // The run queue only closes after the session ends.
                let _ = self.run_sender.send((index, self.program_path(index)));
                return;
            }
            (true, false) => Outcome::Failed(format!(
                "the compile succeeded, but the test expects an error with {:?}",
                test.expect.errors
            )),
            (false, true) => Outcome::Failed(format!("compile error\n{}", failure_report(response))),
            (false, false) => {
                let text = failure_text(response);
                match test.expect.errors.iter().find(|expected| !text.contains(expected.as_str())) {
                    None => Outcome::Passed,
                    Some(missing) => Outcome::Failed(format!(
                        "the diagnostic does not contain {missing:?}\n{}",
                        failure_report(response)
                    )),
                }
            }
        };
        let _ = self.outcome_sender.send((index, outcome));
    }
}

impl Write for Driver {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.response.extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        let response = std::mem::take(&mut self.response);
        if let Ok(response) = serde_json::from_slice::<Value>(&response) {
            self.handle_response(&response);
        }
        Ok(())
    }
}

impl daemon::Clients for Driver {
    fn announce(&mut self, ready: &Value) -> Result<(), CliError> {
        self.startup_ms = ready.get("startup_ms").and_then(Value::as_f64).unwrap_or(0.0);
        Ok(())
    }

    fn next_request(&mut self, line: &mut String) -> Result<bool, CliError> {
        line.clear();
        let index = self.next;
        let Some(test) = self.tests.get(index) else {
            return Ok(false);
        };
        self.next += 1;
        let directory = test.path.parent().unwrap_or(Path::new("."));
        let source_roots: Vec<PathBuf> =
            test.expect.source_roots.iter().map(|root| directory.join(root)).collect();
        let request = json!({
            "id": index,
            "command": "compile",
            "emit": "x86_64",
            "input": test.path,
            "output": self.program_path(index),
            "source_roots": source_roots,
        });
        line.push_str(&request.to_string());
        Ok(true)
    }
}

/// What a failure report prints of a failed compile response: the code and
/// message, the labeled source position with its line, and the help.
fn failure_report(response: &Value) -> String {
    let mut lines = Vec::new();
    if let Some(diagnostic) = response.get("diagnostic") {
        let text = |value: &Value, name: &str| value.get(name).and_then(Value::as_str).unwrap_or("").to_owned();
        lines.push(format!("{}: {}", text(diagnostic, "code"), text(diagnostic, "message")));
        if let Some(label) = diagnostic.get("primary_label").filter(|label| !label.is_null()) {
            let number = |name: &str| label.get(name).and_then(Value::as_u64).unwrap_or(0);
            let position = format!("{}:{}:{}", text(label, "path"), number("line"), number("column"));
            match text(label, "message") {
                message if message.is_empty() => lines.push(position),
                message => lines.push(format!("{position}: {message}")),
            }
            let source_line = text(label, "source_line");
            if !source_line.is_empty() {
                lines.push(format!("    {}", source_line.trim()));
            }
        }
        let help = text(diagnostic, "help");
        if !help.is_empty() {
            lines.push(format!("help: {help}"));
        }
    }
    for name in ["job_error", "protocol_error", "error"] {
        if let Some(message) = response.get(name).and_then(Value::as_str) {
            lines.push(message.to_owned());
        }
    }
    lines.join("\n")
}

/// The text of a failed compile response that `error` directives search: the
/// code and message, the labeled source position, then every other text in
/// the diagnostic.
fn failure_text(response: &Value) -> String {
    fn strings(value: &Value, out: &mut Vec<String>) {
        match value {
            Value::String(text) => out.push(text.clone()),
            Value::Array(items) => items.iter().for_each(|item| strings(item, out)),
            Value::Object(fields) => fields.values().for_each(|field| strings(field, out)),
            _ => {}
        }
    }
    let mut lines = Vec::new();
    if let Some(diagnostic) = response.get("diagnostic") {
        let text = |name: &str| diagnostic.get(name).and_then(Value::as_str).unwrap_or("");
        lines.push(format!("{}: {}", text("code"), text("message")));
        if let Some(label) = diagnostic.get("primary_label").filter(|label| !label.is_null()) {
            let field = |name: &str| label.get(name).cloned().unwrap_or(Value::Null);
            lines.push(format!(
                "{}:{}:{}",
                field("path").as_str().unwrap_or(""),
                field("line"),
                field("column")
            ));
        }
        let mut rest = Vec::new();
        strings(diagnostic, &mut rest);
        lines.extend(rest);
    }
    for name in ["job_error", "protocol_error", "error"] {
        if let Some(message) = response.get(name).and_then(Value::as_str) {
            lines.push(message.to_owned());
        }
    }
    lines.join("\n")
}

/// Runs a compiled program and compares its exit code and output with the
/// expectation.
fn run_and_check(program: &Path, expect: &Expectation, timeout: Duration) -> Outcome {
    let output = match run_program(program, timeout) {
        Ok(output) => output,
        Err(message) => return Outcome::Failed(message),
    };
    let mut problems = Vec::new();
    match expect.signal {
        Some(signal) if output.signal != Some(signal) => {
            problems.push(format!("{}, expected signal {signal}", output.status));
        }
        None if output.exit != Some(expect.exit) => {
            problems.push(format!("{}, expected exit code {}", output.status, expect.exit));
        }
        _ => {}
    }
    for (name, expected, actual) in [
        ("stdout", &expect.stdout, &output.stdout),
        ("stderr", &expect.stderr, &output.stderr),
    ] {
        if let Some(expected) = expected
            && expected != actual
        {
            problems.push(format!("{name} differs\nexpected: {expected:?}\n  actual: {actual:?}"));
        }
    }
    if problems.is_empty() {
        return Outcome::Passed;
    }
    if expect.stderr.is_none() && !output.stderr.is_empty() {
        problems.push(format!("stderr: {}", output.stderr.trim_end()));
    }
    Outcome::Failed(problems.join("\n"))
}

struct ProgramOutput {
    exit: Option<i32>,
    signal: Option<i32>,
    /// The exit code or the signal, for a report.
    status: String,
    stdout: String,
    stderr: String,
}

fn run_program(program: &Path, timeout: Duration) -> Result<ProgramOutput, String> {
    let capture = |suffix: &str| {
        let mut name = program.as_os_str().to_owned();
        name.push(suffix);
        PathBuf::from(name)
    };
    let (stdout_path, stderr_path) = (capture(".stdout"), capture(".stderr"));
    // Output goes to files: a pipe would block a program that writes more
    // than the pipe holds while this thread waits for it to exit.
    let create = |path: &Path| {
        fs::File::create(path).map_err(|err| format!("create {}: {err}", path.display()))
    };
    let started = Instant::now();
    let mut child = loop {
        let spawned = Command::new(program)
            .stdin(Stdio::null())
            .stdout(create(&stdout_path)?)
            .stderr(create(&stderr_path)?)
            .spawn();
        match spawned {
            Ok(child) => break child,
            // Another thread forked while the compiler still held this file
            // open for writing. The copy of that handle closes when the other
            // child starts its program.
            Err(err)
                if err.kind() == io::ErrorKind::ExecutableFileBusy
                    && started.elapsed() < Duration::from_secs(2) =>
            {
                thread::sleep(Duration::from_millis(1));
            }
            Err(err) => return Err(format!("run {}: {err}", program.display())),
        }
    };
    let mut pause = Duration::from_micros(100);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() > timeout => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!(
                    "the program did not exit within {} ms",
                    timeout.as_millis()
                ));
            }
            Ok(None) => {
                thread::sleep(pause);
                pause = (pause * 2).min(Duration::from_millis(5));
            }
            Err(err) => return Err(format!("wait for {}: {err}", program.display())),
        }
    };
    let read = |path: &Path| String::from_utf8_lossy(&fs::read(path).unwrap_or_default()).into_owned();
    Ok(ProgramOutput {
        exit: status.code(),
        signal: signal_of(status),
        status: describe_status(status),
        stdout: read(&stdout_path),
        stderr: read(&stderr_path),
    })
}

fn describe_status(status: std::process::ExitStatus) -> String {
    if let Some(code) = status.code() {
        return format!("exit code {code}");
    }
    match signal_of(status) {
        Some(signal) => format!("ended by signal {signal}"),
        None => "no exit code".into(),
    }
}

fn signal_of(status: std::process::ExitStatus) -> Option<i32> {
    #[cfg(unix)]
    return std::os::unix::process::ExitStatusExt::signal(&status);
    #[cfg(not(unix))]
    return None;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directives_are_read_from_the_leading_comment_lines() {
        let source = "// Adds two numbers.\n//@ exit 42\n//@ stdout 7\n//@ stdout  two\n\n//@ source-root .\nmodule app::main;\n//@ exit 1\n";
        assert_eq!(
            parse_directives(source),
            Ok(Some(Expectation {
                exit: 42,
                signal: None,
                stdout: Some("7\n two\n".into()),
                stderr: None,
                errors: Vec::new(),
                source_roots: vec![PathBuf::from(".")],
            }))
        );
    }

    #[test]
    fn a_file_without_a_directive_is_not_a_test() {
        assert_eq!(parse_directives("// A module.\nmodule app::util;\n"), Ok(None));
    }

    #[test]
    fn a_malformed_directive_names_its_line() {
        assert_eq!(
            parse_directives("//@ exit 0\n//@ exits 3\n").unwrap_err().0,
            2
        );
        assert_eq!(parse_directives("//@ exit many\n").unwrap_err().0, 1);
        assert!(parse_directives("//@ error LNC0006\n//@ exit 1\n").is_err());
    }

    #[test]
    fn an_error_test_matches_the_code_the_message_and_the_position() {
        let response = json!({
            "id": 0,
            "ok": false,
            "diagnostic": {
                "code": "LNC0006",
                "message": "type mismatch",
                "primary_label": {
                    "path": "/tests/programs/bad.lani",
                    "line": 4,
                    "column": 9,
                    "source_line": "    return true;",
                },
            },
        });
        let text = failure_text(&response);
        for expected in ["LNC0006", "type mismatch", "bad.lani:4", "return true;"] {
            assert!(text.contains(expected), "{expected} in {text}");
        }
        assert_eq!(
            failure_report(&response),
            "LNC0006: type mismatch\n/tests/programs/bad.lani:4:9\n    return true;"
        );
    }
}
