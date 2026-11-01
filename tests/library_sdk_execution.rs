#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
#[path = "support/library_sdk_isolation.rs"]
mod isolation;

use std::{
    ffi::OsString,
    fs,
    path::{Component, Path, PathBuf},
    process::Output,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const CALCULATOR_INPUT: &[u8] = b"1+2*3\n-(5+6)\n";
const CALCULATOR_OUTPUT: &[u8] = b"7\n-11\n";
const SHA256_ABC: &[u8] = b"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n";

fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

// Copy actual SDK bytes, never hard-link an installed file back to its source.
// The builder's accepted snapshot limits also bound acceptance setup.
fn copy_tree(source: &Path, target: &Path, files: &mut usize, bytes: &mut u64) {
    let metadata = fs::symlink_metadata(source).unwrap();
    assert!(!metadata.file_type().is_symlink(), "SDK symlink: {source:?}");
    if metadata.is_dir() {
        fs::create_dir(target).unwrap();
        for entry in fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            copy_tree(&entry.path(), &target.join(entry.file_name()), files, bytes);
        }
        fs::set_permissions(target, metadata.permissions()).unwrap();
    } else {
        assert!(metadata.is_file(), "SDK nonregular payload: {source:?}");
        *files += 1;
        *bytes = bytes.checked_add(metadata.len()).unwrap();
        assert!(*files <= 8193 && *bytes <= 520 * 1024 * 1024, "oversized SDK snapshot");
        assert_eq!(fs::copy(source, target).unwrap(), metadata.len());
    }
}

fn lanius_sources(root: &Path) -> Vec<PathBuf> {
    let mut result = Vec::new();
    for entry in fs::read_dir(root).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            result.extend(lanius_sources(&path));
        } else if path.extension().is_some_and(|extension| extension == "lani") {
            result.push(path);
        }
    }
    result.sort();
    result
}

struct Gate {
    root: PathBuf,
    sdk: PathBuf,
    work: PathBuf,
    sandbox: isolation::Sandbox,
    deadline: Instant,
}

impl Gate {
    fn new(name: &str) -> Self {
        let deadline = Instant::now() + Duration::from_secs(90);
        let supplied = std::env::var_os("LANIUS_SDK_TEST_ROOT")
            .map(PathBuf::from)
            .expect("set LANIUS_SDK_TEST_ROOT to the verified debug SDK; SDK acceptance never silently skips");
        let supplied = fs::canonicalize(supplied).expect("existing supplied SDK directory");
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        // Deliberately outside checkout/build and containing ordinary spaces.
        let root = PathBuf::from(format!("/tmp/lanius-sdk-{name}-{}-{stamp}", std::process::id()));
        fs::create_dir(&root).unwrap();
        let initial = root.join("initial SDK prefix");
        copy_tree(&supplied, &initial, &mut 0, &mut 0);
        let sdk = root.join("relocated SDK prefix");
        fs::rename(&initial, &sdk).unwrap();
        assert!(!initial.exists());
        let work = root.join("external project work");
        fs::create_dir(&work).unwrap();
        let metadata: serde_json::Value = serde_json::from_slice(&fs::read(sdk.join("SDK.json")).unwrap()).unwrap();
        // This finite acceptance matrix deliberately requires runtime shader
        // reads. Release/embedded SDKs need a separately recorded receipt.
        assert_eq!(metadata["profile"].as_str(), Some("debug"));
        let mut hidden = vec![supplied, initial];
        if let Some(directory) = metadata["build_inputs"]["target_dir"].as_str() {
            hidden.push(PathBuf::from(directory));
        } else {
            panic!("SDK metadata must identify its original target_dir for isolation");
        }
        if let Some(directory) = metadata["build_inputs"]["shaders"].as_str() {
            hidden.push(PathBuf::from(directory));
        }
        if let Some(directory) = metadata["initial_sdk_path"].as_str() {
            hidden.push(PathBuf::from(directory));
        }
        let sandbox = isolation::Sandbox::new(&repository(), &sdk, &work, &hidden);
        // Retain provenance/inventory alongside traces after removing the large
        // private SDK/cache copy at successful gate completion.
        fs::copy(sdk.join("SDK.json"), work.join("accepted-SDK.json")).unwrap();
        fs::copy(sdk.join("SHA256SUMS"), work.join("accepted-SHA256SUMS")).unwrap();
        Self { root, sdk, work, sandbox, deadline }
    }

    fn share(&self, path: &str) -> PathBuf { self.sdk.join("share/lanius").join(path) }
    fn bin(&self, name: &str) -> PathBuf { self.sdk.join("bin").join(name) }

    fn run(&self, label: &str, program: &Path, args: Vec<OsString>, input: Option<&[u8]>, maximum: u64) -> Output {
        let mut command = self.sandbox.command(label, program, args);
        if let Some(input) = input {
            let path = self.work.join(format!("{label}.stdin"));
            fs::write(&path, input).unwrap();
            command.stdin(fs::File::open(path).unwrap());
        }
        let remaining = self.deadline.saturating_duration_since(Instant::now());
        assert!(!remaining.is_zero(), "SDK gate's 90-second aggregate deadline exhausted");
        let output = common::process_output_with_timeout(
            format!("isolated SDK {label}"), &mut command, remaining.min(Duration::from_secs(maximum)),
        );
        fs::write(self.work.join(format!("{label}.stdout")), &output.stdout).unwrap();
        fs::write(self.work.join(format!("{label}.stderr")), &output.stderr).unwrap();
        fs::write(self.work.join(format!("{label}.status")), output.status.to_string()).unwrap();
        output
    }

    fn compiled(&self, label: &str, source: &Path, output: &Path, native: bool) {
        let mut args = vec![
            "LANIUS_GPU_COMPILE_HOST_TIMING=1".into(), self.bin("laniusc").into_os_string(),
            source.as_os_str().to_owned(), "--stdlib-root".into(),
            self.share("stdlib").into_os_string(), "--source-root".into(),
            self.share("extended").into_os_string(), "-o".into(), output.as_os_str().to_owned(),
        ];
        if native { args.extend(["--native-link".into(), "--native-library".into(), "crypto".into()]); }
        let result = self.run(label, Path::new("/usr/bin/env"), args, None, 80);
        common::assert_command_success(label, &result);
        self.compiler_witness(label, &[source.to_path_buf()]);
    }

    fn compiler_witness(&self, label: &str, sources: &[PathBuf]) {
        self.sandbox.assert_trace(label, sources, &[self.bin("laniusc"), self.sdk.join("libexec/laniusc")]);
        let evidence = self.sandbox.evidence(label);
        let shaders = self.sdk.join("shaders");
        for suffix in [".spv", ".reflect.json"] {
            assert!(evidence.reads.iter().any(|path| path.starts_with(&shaders) && path.to_string_lossy().ends_with(suffix)),
                    "{label}: no successful relocated {suffix} read");
        }
    }

    fn strict_elf(&self, path: &Path) {
        let bytes = fs::read(path).unwrap();
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "actual ELF64 x86-64 executable required");
        common::x86_jumps::assert_x86_64_file_jumps_stay_in_functions(path);
    }

    fn native_elf(&self, path: &Path) {
        assert!(common::x86_jumps::is_x86_64_executable(&fs::read(path).unwrap()));
        // Reuse the existing CRT/PLT-aware sized-Lanius function validator.
        // This copied test observer is not an SDK runtime dependency.
        let validator = self.work.join("validate_linked_elf.py");
        fs::copy(repository().join("tests/fixtures/native_c/validate_linked_elf.py"), &validator).unwrap();
        let output = self.run("native-elf", Path::new("/usr/bin/python3"), vec!["-B".into(), validator.clone().into_os_string(), path.as_os_str().to_owned()], None, 20);
        common::assert_command_success("SDK native linked ELF", &output);
        assert!(output.stderr.is_empty());
        assert!(output.stdout.starts_with(b"checked ") && output.stdout.ends_with(b" local branches\n"));
        self.sandbox.assert_trace("native-elf", &[validator, path.to_path_buf()], &[]);
    }

    fn program(&self, label: &str, executable: &Path, args: Vec<OsString>, input: &[u8], expected: &[u8]) {
        let output = self.run(label, executable, args, Some(input), 5);
        assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
        assert_eq!(output.stdout, expected, "{label}");
        assert!(output.stderr.is_empty(), "{label}: {output:?}");
        self.sandbox.assert_trace(label, &[], &[executable.to_path_buf()]);
    }

    fn finish(self, group: &str, native_cases: usize) {
        assert!(Instant::now() < self.deadline, "SDK aggregate deadline exceeded");
        fs::remove_dir_all(&self.sdk).unwrap();
        fs::remove_dir_all(self.work.join(".isolation/cache")).unwrap();
        eprintln!("library-sdk-{group} native_cases={native_cases} evidence={} (private SDK and fresh cache retired)", self.root.display());
    }
}

#[test]
#[ignore = "requires packaged debug SDK; set LANIUS_SDK_TEST_ROOT and run explicitly"]
fn relocated_sdk_compiles_core_and_extended_calculator() {
    let gate = Gate::new("calculator");
    let source = gate.share("examples/calculator/app/main.lani");
    let executable = gate.work.join("calculator program");
    gate.compiled("calculator-compile", &source, &executable, false);
    gate.sandbox.assert_trace("calculator-compile", &[gate.share("stdlib/core/i64.lani"), gate.share("extended/ext/parse.lani")], &[]);
    gate.strict_elf(&executable);
    gate.program("calculator-run", &executable, vec![], CALCULATOR_INPUT, CALCULATOR_OUTPUT);
    gate.finish("calculator", 1);
}

#[test]
#[ignore = "requires packaged debug SDK; set LANIUS_SDK_TEST_ROOT and run explicitly"]
fn relocated_sdk_links_and_executes_openssl_service() {
    let gate = Gate::new("openssl");
    let source = gate.share("examples/hash/app/main.lani");
    let executable = gate.work.join("hash program");
    gate.compiled("hash-compile", &source, &executable, true);
    gate.sandbox.assert_trace("hash-compile", &[gate.share("extended/ext/openssl_digest.lani")], &[]);
    gate.native_elf(&executable);
    gate.program("hash-run", &executable, vec!["sha256".into()], b"abc", SHA256_ABC);
    let evidence = gate.sandbox.evidence("hash-run");
    assert!(evidence.reads.iter().any(|path| path.file_name().is_some_and(|name| name.to_string_lossy().starts_with("libcrypto.so"))),
            "real OpenSSL library must be opened by the dynamic loader");
    gate.finish("openssl", 1);
}

#[test]
#[ignore = "requires packaged debug SDK; set LANIUS_SDK_TEST_ROOT and run explicitly"]
fn relocated_sdk_source_suite_driver_lists_filters_and_propagates_status() {
    let gate = Gate::new("suite");
    let cases: [(&str, Vec<&str>, i32, &[u8]); 3] = [
        ("suite-pass", vec!["--seed", "7", "--cases", "3"], 0,
         b"lanius-test 1\nseed=7 cases=3\nPASS checked arithmetic\nPASS UTF-8 text\nsummary selected=2 passed=2 failed=0 skipped=0 filtered=0\n"),
        ("suite-list", vec!["--filter", "UTF-8", "--list"], 0,
         b"lanius-test 1\nseed=1 cases=100\nLIST UTF-8 text\nsummary selected=1 passed=0 failed=0 skipped=0 filtered=1\n"),
        ("suite-missing", vec!["--filter", "missing"], 3,
         b"lanius-test 1\nseed=1 cases=100\nsummary selected=0 passed=0 failed=0 skipped=0 filtered=2\n"),
    ];
    for (label, options, status, expected) in cases {
        let source = gate.share("examples/suite/app/main.lani");
        let mut args = vec!["LANIUS_TEST_COMPILE_SECONDS=80".into(), "LANIUS_TEST_RUN_SECONDS=5".into(),
                            gate.bin("lanius-test").into_os_string(), source.clone().into_os_string(), "--".into()];
        args.extend(options.into_iter().map(OsString::from));
        let output = gate.run(label, Path::new("/usr/bin/env"), args, None, 85);
        assert_eq!(output.status.code(), Some(status), "{label}: {output:?}");
        assert_eq!(output.stdout, expected, "{label}");
        assert!(output.stderr.is_empty(), "{label}: {output:?}");
        gate.compiler_witness(label, &[source, gate.share("stdlib/test/suite.lani"), gate.share("tools/lanius-test")]);
        gate.sandbox.assert_trace(label, &[], &[gate.bin("lanius-test"), gate.share("tools/lanius-test")]);
        let temporary = gate.work.join(".isolation/tmp");
        let evidence = gate.sandbox.evidence(label);
        let executed: Vec<_> = evidence.execs.iter().filter(|path| path.starts_with(&temporary) && path.file_name().is_some_and(|name| name == "suite")).collect();
        assert_eq!(executed.len(), 1, "{label}: driver must execute its fresh compiled suite");
        assert!(!executed[0].exists(), "suite driver's normal temporary cleanup");
    }
    // The existing driver removes its ELF before returning. This gate checks
    // actual successful exec and exact reports; other gates retain/check ELF.
    gate.finish("suite", 3);
}

#[test]
#[ignore = "requires packaged debug SDK; set LANIUS_SDK_TEST_ROOT and run explicitly"]
fn relocated_sdk_vendors_and_executes_selective_package() {
    let gate = Gate::new("vendor");
    let initial = gate.work.join("initial source bundle");
    let output = gate.run("vendor-create", &gate.bin("lanius-vendor"), vec![
        "--manifest".into(), gate.share("calculator.package.json").into_os_string(), "--out".into(), initial.clone().into_os_string(),
    ], None, 40);
    common::assert_command_success("installed selective vendor", &output);
    gate.sandbox.assert_trace("vendor-create", &[
        gate.share("tools/vendor_lanius.py"), gate.share("calculator.package.json"), gate.share("LICENSE-MIT"),
        gate.share("data/unicode/17.0.0/LICENSE.txt"), gate.share("examples/calculator/app/main.lani"),
    ], &[gate.bin("lanius-vendor"), gate.bin("laniusc"), gate.sdk.join("libexec/laniusc")]);
    let moved = gate.work.join("relocated source bundle");
    fs::rename(&initial, &moved).unwrap();
    assert!(!initial.exists());
    let sources = lanius_sources(&moved);
    assert!(sources.len() < lanius_sources(&gate.share("stdlib")).len());
    assert!(moved.join("stdlib/core/i64.lani").is_file());
    assert!(!moved.join("stdlib/core/unicode.lani").exists());
    assert!(!moved.join("stdlib/test/suite.lani").exists());
    let manifest = moved.join("lanius.package.json");
    let data: serde_json::Value = serde_json::from_slice(&fs::read(&manifest).unwrap()).unwrap();
    for value in data["roots"].as_array().unwrap().iter().chain([&data["stdlib_root"], &data["entry"]]) {
        let path = Path::new(value.as_str().unwrap());
        assert!(!path.as_os_str().is_empty() && path.components().all(|part| matches!(part, Component::Normal(_))));
    }
    let verified = gate.run("vendor-verify", &gate.bin("lanius-vendor"), vec!["--verify".into(), moved.clone().into_os_string()], None, 10);
    common::assert_command_success("verify relocated package", &verified);
    gate.sandbox.assert_trace("vendor-verify", &[gate.share("tools/vendor_lanius.py"), moved.join("SHA256SUMS")], &[gate.bin("lanius-vendor")]);
    let lock = gate.work.join("fresh relocated.lock.json");
    let locked = gate.run("vendor-lock", &gate.bin("laniusc"), vec!["package".into(), "lock".into(), "--manifest".into(), manifest.into_os_string(), "-o".into(), lock.clone().into_os_string()], None, 15);
    common::assert_command_success("lock relocated selective bundle", &locked);
    gate.sandbox.assert_trace("vendor-lock", &[moved.join("lanius.package.json")], &[gate.bin("laniusc"), gate.sdk.join("libexec/laniusc")]);
    let locked_data: serde_json::Value = serde_json::from_slice(&fs::read(&lock).unwrap()).unwrap();
    assert!(locked_data["inputs"]["files"].as_array().unwrap().iter().all(|file| Path::new(file["path"].as_str().unwrap()).starts_with(&moved)));
    let executable = gate.work.join("vendored calculator");
    let compiled = gate.run("vendor-compile", &gate.bin("laniusc"), vec!["--package-lockfile".into(), lock.into_os_string(), "-o".into(), executable.clone().into_os_string()], None, 80);
    common::assert_command_success("compile relocated selective package", &compiled);
    gate.compiler_witness("vendor-compile", &[moved.join("stdlib/core/i64.lani")]);
    let evidence = gate.sandbox.evidence("vendor-compile");
    let read_sources: Vec<_> = evidence.reads.iter().filter(|path| path.extension().is_some_and(|extension| extension == "lani")).collect();
    assert!(!read_sources.is_empty() && read_sources.iter().all(|path| path.starts_with(&moved)), "package source fallback escaped relocated bundle");
    gate.strict_elf(&executable);
    gate.program("vendor-run", &executable, vec![], CALCULATOR_INPUT, CALCULATOR_OUTPUT);
    gate.finish("vendor", 1);
}
