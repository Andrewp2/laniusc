//! Run-time options of the compiler.
//!
//! This module is the only place in the library that reads a `LANIUS_*`
//! variable. [`Options::from_env`] reads every one of them once, and [`get`]
//! hands the result to the rest of the crate. Code elsewhere asks
//! `options::get()` and never calls `std::env::var` for one.
//!
//! Other environment reads are not options of the compiler: the NVIDIA
//! driver's shader cache variables in `gpu/device.rs`, `SLANGC` in
//! `laniusc doctor`, and the inputs of the development binaries in `bin/`.
//!
//! The variables, by who sets them:
//!
//! A person running the compiler:
//! - `LANIUS_BACKEND`: `auto`, `vulkan`, `dx12`, `metal` or `gl`.
//! - `LANIUS_ALLOW_SOFTWARE_ADAPTER=1`: accept a software adapter.
//! - `LANIUS_PIPELINE_CACHE_DIR`: where the pipeline cache files live.
//! - `LANIUS_DRIVER_SHADER_CACHE=0`: turn NVIDIA's own shader cache off.
//! - `LANIUS_READBACK_TIMEOUT_MS`: how long a readback may take.
//! - `LANIUS_SHADER_ARTIFACT_ROOT`: load kernels from another directory.
//! - `LANIUS_DAEMON=0`: a one-shot compile never uses the shared daemon.
//! - `LANIUS_GPU_PROCESS_SLOTS`: read by `gpu/process_slot.rs`, the one
//!   exception to the rule above.
//!
//! A shared daemon has its own environment. The variables of a person above
//! configure the device and its caches: a daemon is started with the ones
//! its first client has, and clients that have other values use another
//! daemon. See [`device_environment`]. The variables of a developer below ask
//! for output from one compile, so a compile with one of them set runs in
//! its own process. See [`environment_asks_for_diagnostics`].
//!
//! A developer diagnosing the compiler. Each takes a comma-separated list:
//! - `LANIUS_TRACE`: lines on stderr. See [`Trace`].
//! - `LANIUS_REPORT`: timing and memory reports. See [`Report`].
//! - `LANIUS_CHECK`: extra validation that costs time. See [`Check`].
//! - `LANIUS_EXPERIMENT`: unfinished features. See [`Experiment`].
//! - `LANIUS_PERFETTO_TRACE=<path>`: write a Perfetto trace.
//! - `LANIUS_CAPTURE=<pass>[,index=N][,dir=PATH][,per-job]`: save one
//!   dispatch for replay. See [`Capture`].
//! - `LANIUS_DUMP=<buffer>[,<buffer>...][,words=N][,dir=PATH]`: dump bound
//!   buffers after a compile. See [`Dump`].
//! - `LANIUS_OPERATION_LIMIT=N`: drop every operation from the N-th onward,
//!   to find the operation behind a hang.
//!
//! An unknown word in a list prints one warning that names the known words.

use std::{
    ffi::OsString,
    path::PathBuf,
    sync::OnceLock,
    time::Duration,
};

/// Every run-time option, read once per process.
#[derive(Clone, Debug)]
pub struct Options {
    /// `LANIUS_BACKEND`.
    pub backend: Backend,
    /// `LANIUS_ALLOW_SOFTWARE_ADAPTER`.
    pub allow_software_adapter: bool,
    /// `LANIUS_PIPELINE_CACHE_DIR`, when set.
    pub pipeline_cache_dir: Option<PathBuf>,
    /// False when `LANIUS_DRIVER_SHADER_CACHE=0`.
    pub driver_shader_cache: bool,
    /// `LANIUS_READBACK_TIMEOUT_MS`, 120 seconds by default.
    pub readback_timeout: Duration,
    /// `LANIUS_SHADER_ARTIFACT_ROOT`, when set and not empty.
    pub shader_artifact_root: Option<PathBuf>,
    /// `LANIUS_TRACE`.
    pub trace: Trace,
    /// `LANIUS_REPORT`.
    pub report: Report,
    /// `LANIUS_CHECK`.
    pub check: Check,
    /// `LANIUS_EXPERIMENT`.
    pub experiment: Experiment,
    /// `LANIUS_PERFETTO_TRACE`.
    pub perfetto_trace: Option<PathBuf>,
    /// `LANIUS_CAPTURE`.
    pub capture: Option<Capture>,
    /// `LANIUS_DUMP`.
    pub dump: Option<Dump>,
    /// `LANIUS_OPERATION_LIMIT`.
    pub operation_limit: Option<u64>,
    /// False when `LANIUS_DAEMON=0`.
    pub shared_daemon: bool,
}

/// The variables that configure the device, its kernels and its caches.
/// `LANIUS_CHECK` is here for `indirect-dispatch`, which is a setting of the
/// device. Its other words keep a compile in its own process: see
/// [`environment_asks_for_diagnostics`].
const DEVICE_VARIABLES: &[&str] = &[
    "LANIUS_BACKEND",
    "LANIUS_CHECK",
    "LANIUS_ALLOW_SOFTWARE_ADAPTER",
    "LANIUS_PIPELINE_CACHE_DIR",
    "LANIUS_DRIVER_SHADER_CACHE",
    "LANIUS_READBACK_TIMEOUT_MS",
    "LANIUS_SHADER_ARTIFACT_ROOT",
];

/// The variables that ask one compile for traces, reports or dumps.
const DIAGNOSTIC_VARIABLES: &[&str] = &[
    "LANIUS_TRACE",
    "LANIUS_REPORT",
    "LANIUS_EXPERIMENT",
    "LANIUS_PERFETTO_TRACE",
    "LANIUS_CAPTURE",
    "LANIUS_DUMP",
    "LANIUS_OPERATION_LIMIT",
];

/// Whether this process has a variable set that asks its compile for output
/// a compile in another process would not give. Such a compile cannot be
/// handed to the shared daemon.
pub fn environment_asks_for_diagnostics() -> bool {
    DIAGNOSTIC_VARIABLES
        .iter()
        .any(|name| std::env::var_os(name).is_some_and(|value| !value.is_empty()))
        || !get().check.only_configures_the_device()
}

/// The device configuration of this process, as `NAME=value` lines. A shared
/// daemon serves the processes whose configuration equals its own.
pub fn device_environment() -> Vec<u8> {
    let mut configuration = Vec::new();
    for name in DEVICE_VARIABLES {
        if let Some(value) = std::env::var_os(name).filter(|value| !value.is_empty()) {
            configuration.extend_from_slice(name.as_bytes());
            configuration.push(b'=');
            configuration.extend_from_slice(value.as_encoded_bytes());
            configuration.push(b'\n');
        }
    }
    configuration
}

/// The wgpu backend to request.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Backend {
    /// Every backend wgpu supports on this platform.
    #[default]
    Auto,
    /// Vulkan.
    Vulkan,
    /// Direct3D 12.
    Dx12,
    /// Metal.
    Metal,
    /// OpenGL.
    Gl,
}

/// `LANIUS_TRACE`: lines on stderr. None of these changes what is compiled.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Trace {
    /// `stage-errors`: the internal error behind a stage diagnostic.
    pub stage_errors: bool,
    /// `call-inference`: each call inference round.
    pub call_inference: bool,
    /// `canonical`: the canonical type stage counters and capacity retries.
    /// The counters are read after every batch while this is on.
    pub canonical: bool,
    /// `instance-table`: the rows of the instance table.
    pub instance_table: bool,
    /// `wasm`: Wasm codegen and link steps.
    pub wasm: bool,
    /// `operations`: each GPU operation in recording order.
    pub operations: bool,
    /// `gpu-labels`: label GPU objects for an external profiler.
    pub gpu_labels: bool,
}

/// `LANIUS_REPORT`: timing and memory reports.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Report {
    /// `host-timing`: host-side phase times.
    pub host_timing: bool,
    /// `gpu-timing`: GPU pass times from timestamp queries.
    pub gpu_timing: bool,
    /// `graph`: per-graph resource totals and the compute schedule.
    pub graph: bool,
    /// `passes`: compute pass counts per label.
    pub passes: bool,
    /// `buffers`: live buffer bytes per label.
    pub buffers: bool,
    /// `resources` or `resources=N`: resource creation per daemon job, for
    /// jobs that create at most N resources (32 by default).
    pub resources: Option<u64>,
    /// `memory`: GPU memory after each daemon job.
    pub memory: bool,
}

/// `LANIUS_CHECK`: extra validation that costs time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Check {
    /// `validation-scopes`: wrap passes in wgpu error scopes, to find the
    /// pass behind a validation error.
    pub validation_scopes: bool,
    /// `indirect-dispatch`: wgpu's indirect dispatch argument check. Debug
    /// builds always run it.
    pub indirect_dispatch: bool,
    /// `canonical`: record the canonical identity validation kernels.
    pub canonical: bool,
    /// `canonical-retry=N`: divide the canonical capacities by `2^N` (at most
    /// 16), so that a small program overflows and takes the retry path.
    pub canonical_retry: u32,
    /// `instance-closure`: fail when a replay round finds a body the closure
    /// missed.
    pub instance_closure: bool,
    /// `instance-table`: read the instance table back and compare it with
    /// each copy run.
    pub instance_table: bool,
    /// `library-instance-cache`: replay every cache hit and compare.
    pub library_instance_cache: bool,
    /// `lir-replays`: record the optimizer validation dispatches for copy
    /// replays as well.
    pub lir_replays: bool,
}

impl Default for Check {
    fn default() -> Self {
        Self {
            validation_scopes: false,
            indirect_dispatch: cfg!(debug_assertions),
            canonical: false,
            canonical_retry: 0,
            instance_closure: false,
            instance_table: false,
            library_instance_cache: false,
            lir_replays: false,
        }
    }
}

/// `LANIUS_EXPERIMENT`: features that are not finished.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Experiment {
    /// `instance-table`: build the instance table in original jobs.
    pub instance_table: bool,
}

/// `LANIUS_CAPTURE`: one dispatch saved for offline replay
/// (docs/cpu-kernel-replay.md).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Capture {
    /// The operation label or kernel key whose dispatches are counted.
    pub pass: String,
    /// `index=N`: which of those dispatches to save. 0 by default.
    pub index: u64,
    /// `dir=PATH`: where the capture is written. `lanius-capture` by default.
    pub dir: PathBuf,
    /// `per-job`: restart the count at each job of a resident compiler.
    pub per_job: bool,
}

/// `LANIUS_DUMP`: buffers dumped after a compile.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Dump {
    /// The reflected binding names to dump. `*` selects every binding.
    pub buffers: Vec<String>,
    /// `words=N`: how many `u32` words of each buffer. 64 by default.
    pub words: u64,
    /// `dir=PATH`: write `<stage>.<name>.bin` files instead of printing.
    pub dir: Option<PathBuf>,
}

/// The process's options. The first call reads the environment unless
/// [`install`] ran earlier.
pub fn get() -> &'static Options {
    OPTIONS.get_or_init(Options::from_env)
}

/// Sets the process's options before anything asks for them. Returns the
/// options back when [`get`] or `install` already ran.
pub fn install(options: Options) -> Result<(), Box<Options>> {
    OPTIONS.set(options).map_err(Box::new)
}

static OPTIONS: OnceLock<Options> = OnceLock::new();

impl Default for Options {
    fn default() -> Self {
        Self::from_lookup(|_| None)
    }
}

impl Options {
    /// Reads every option from the process environment.
    pub fn from_env() -> Self {
        Self::from_lookup(|name| std::env::var_os(name))
    }

    /// Builds the options from `lookup`, which stands for the environment.
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<OsString>) -> Self {
        let text = |name: &str| {
            lookup(name)
                .map(|value| value.to_string_lossy().trim().to_owned())
                .filter(|value| !value.is_empty())
        };
        let path = |name: &str| lookup(name).filter(|value| !value.is_empty()).map(PathBuf::from);
        Self {
            backend: backend(text("LANIUS_BACKEND")),
            allow_software_adapter: switch("LANIUS_ALLOW_SOFTWARE_ADAPTER", text("LANIUS_ALLOW_SOFTWARE_ADAPTER"), false),
            pipeline_cache_dir: path("LANIUS_PIPELINE_CACHE_DIR"),
            driver_shader_cache: switch("LANIUS_DRIVER_SHADER_CACHE", text("LANIUS_DRIVER_SHADER_CACHE"), true),
            readback_timeout: Duration::from_millis(
                number("LANIUS_READBACK_TIMEOUT_MS", text("LANIUS_READBACK_TIMEOUT_MS"))
                    .filter(|&ms| ms > 0)
                    .unwrap_or(120_000),
            ),
            shader_artifact_root: path("LANIUS_SHADER_ARTIFACT_ROOT"),
            trace: Trace::parse(text("LANIUS_TRACE")),
            report: Report::parse(text("LANIUS_REPORT")),
            check: Check::parse(text("LANIUS_CHECK")),
            experiment: Experiment::parse(text("LANIUS_EXPERIMENT")),
            perfetto_trace: path("LANIUS_PERFETTO_TRACE"),
            capture: text("LANIUS_CAPTURE").and_then(Capture::parse),
            dump: text("LANIUS_DUMP").and_then(Dump::parse),
            operation_limit: number("LANIUS_OPERATION_LIMIT", text("LANIUS_OPERATION_LIMIT")),
            shared_daemon: switch("LANIUS_DAEMON", text("LANIUS_DAEMON"), true),
        }
    }
}

fn warn(message: std::fmt::Arguments<'_>) {
    eprintln!("laniusc: warning: {message}");
}

fn backend(value: Option<String>) -> Backend {
    match value.as_deref().map(str::to_ascii_lowercase).as_deref() {
        None | Some("auto") => Backend::Auto,
        Some("vulkan" | "vk") => Backend::Vulkan,
        Some("dx12") => Backend::Dx12,
        Some("metal" | "mtl") => Backend::Metal,
        Some("gl") => Backend::Gl,
        Some(other) => {
            warn(format_args!(
                "LANIUS_BACKEND={other:?} is not auto, vulkan, dx12, metal or gl; using auto"
            ));
            Backend::Auto
        }
    }
}

fn switch(name: &str, value: Option<String>, default: bool) -> bool {
    match value.as_deref().map(str::to_ascii_lowercase).as_deref() {
        None => default,
        Some("1" | "true") => true,
        Some("0" | "false") => false,
        Some(other) => {
            warn(format_args!("{name}={other:?} is not 0 or 1; using {}", u8::from(default)));
            default
        }
    }
}

fn number(name: &str, value: Option<String>) -> Option<u64> {
    let value = value?;
    match value.parse() {
        Ok(number) => Some(number),
        Err(_) => {
            warn(format_args!("{name}={value:?} is not an unsigned integer; ignoring it"));
            None
        }
    }
}

/// Splits `a,b=1,c` into `("a", None)`, `("b", Some("1"))`, `("c", None)` and
/// passes each to `set`. An entry `set` refuses is reported with `known`.
fn words(name: &str, value: Option<String>, known: &[&str], mut set: impl FnMut(&str, Option<&str>) -> bool) {
    let Some(value) = value else { return };
    for entry in value.split(',').map(str::trim).filter(|entry| !entry.is_empty()) {
        let (word, argument) = match entry.split_once('=') {
            Some((word, argument)) => (word, Some(argument)),
            None => (entry, None),
        };
        if !set(word, argument) {
            warn(format_args!("{name}: unknown entry {entry:?}; known entries: {}", known.join(", ")));
        }
    }
}

fn flag(target: &mut bool, argument: Option<&str>) -> bool {
    if argument.is_some() {
        return false;
    }
    *target = true;
    true
}

impl Trace {
    /// The words `LANIUS_TRACE` accepts.
    pub const WORDS: &'static [&'static str] =
        &["stage-errors", "call-inference", "canonical", "instance-table", "wasm", "operations", "gpu-labels"];

    fn parse(value: Option<String>) -> Self {
        let mut trace = Self::default();
        words("LANIUS_TRACE", value, Self::WORDS, |word, argument| match word {
            "stage-errors" => flag(&mut trace.stage_errors, argument),
            "call-inference" => flag(&mut trace.call_inference, argument),
            "canonical" => flag(&mut trace.canonical, argument),
            "instance-table" => flag(&mut trace.instance_table, argument),
            "wasm" => flag(&mut trace.wasm, argument),
            "operations" => flag(&mut trace.operations, argument),
            "gpu-labels" => flag(&mut trace.gpu_labels, argument),
            _ => false,
        });
        trace
    }
}

impl Report {
    /// The words `LANIUS_REPORT` accepts.
    pub const WORDS: &'static [&'static str] =
        &["host-timing", "gpu-timing", "graph", "passes", "buffers", "resources[=N]", "memory"];
    /// The `resources` report covers jobs that create at most this many
    /// resources unless the word carries its own limit.
    pub const DEFAULT_RESOURCES_LIMIT: u64 = 32;

    fn parse(value: Option<String>) -> Self {
        let mut report = Self::default();
        words("LANIUS_REPORT", value, Self::WORDS, |word, argument| match word {
            "host-timing" => flag(&mut report.host_timing, argument),
            "gpu-timing" => flag(&mut report.gpu_timing, argument),
            "graph" => flag(&mut report.graph, argument),
            "passes" => flag(&mut report.passes, argument),
            "buffers" => flag(&mut report.buffers, argument),
            "memory" => flag(&mut report.memory, argument),
            "resources" => match argument.map(str::parse) {
                None => {
                    report.resources = Some(Self::DEFAULT_RESOURCES_LIMIT);
                    true
                }
                Some(Ok(limit)) => {
                    report.resources = Some(limit);
                    true
                }
                Some(Err(_)) => false,
            },
            _ => false,
        });
        report
    }
}

impl Check {
    /// True when no check is on except `indirect-dispatch`. The other checks
    /// validate one compile and report on the stderr of its process.
    fn only_configures_the_device(&self) -> bool {
        *self
            == Self {
                indirect_dispatch: self.indirect_dispatch,
                ..Self::default()
            }
    }

    /// The words `LANIUS_CHECK` accepts.
    pub const WORDS: &'static [&'static str] = &[
        "validation-scopes",
        "indirect-dispatch",
        "canonical",
        "canonical-retry=N",
        "instance-closure",
        "instance-table",
        "library-instance-cache",
        "lir-replays",
    ];

    fn parse(value: Option<String>) -> Self {
        let mut check = Self::default();
        words("LANIUS_CHECK", value, Self::WORDS, |word, argument| match word {
            "validation-scopes" => flag(&mut check.validation_scopes, argument),
            "indirect-dispatch" => flag(&mut check.indirect_dispatch, argument),
            "canonical" => flag(&mut check.canonical, argument),
            "instance-closure" => flag(&mut check.instance_closure, argument),
            "instance-table" => flag(&mut check.instance_table, argument),
            "library-instance-cache" => flag(&mut check.library_instance_cache, argument),
            "lir-replays" => flag(&mut check.lir_replays, argument),
            "canonical-retry" => match argument.map(str::parse::<u32>) {
                Some(Ok(shift)) => {
                    check.canonical_retry = shift.min(16);
                    true
                }
                _ => false,
            },
            _ => false,
        });
        check
    }
}

impl Experiment {
    /// The words `LANIUS_EXPERIMENT` accepts.
    pub const WORDS: &'static [&'static str] = &["instance-table"];

    fn parse(value: Option<String>) -> Self {
        let mut experiment = Self::default();
        words("LANIUS_EXPERIMENT", value, Self::WORDS, |word, argument| match word {
            "instance-table" => flag(&mut experiment.instance_table, argument),
            _ => false,
        });
        experiment
    }
}

impl Capture {
    fn parse(value: String) -> Option<Self> {
        let mut capture = Self {
            pass: String::new(),
            index: 0,
            dir: PathBuf::from("lanius-capture"),
            per_job: false,
        };
        words("LANIUS_CAPTURE", Some(value), &["<pass>", "index=N", "dir=PATH", "per-job"], |word, argument| {
            match (word, argument) {
                ("index", Some(index)) => index.parse().map(|index| capture.index = index).is_ok(),
                ("dir", Some(dir)) => {
                    capture.dir = PathBuf::from(dir);
                    true
                }
                ("per-job", None) => {
                    capture.per_job = true;
                    true
                }
                (pass, None) if capture.pass.is_empty() => {
                    capture.pass = pass.to_owned();
                    true
                }
                _ => false,
            }
        });
        if capture.pass.is_empty() {
            warn(format_args!("LANIUS_CAPTURE names no pass; ignoring it"));
            return None;
        }
        Some(capture)
    }
}

impl Dump {
    fn parse(value: String) -> Option<Self> {
        let mut dump = Self { buffers: Vec::new(), words: 64, dir: None };
        words("LANIUS_DUMP", Some(value), &["<buffer>", "words=N", "dir=PATH"], |word, argument| {
            match (word, argument) {
                ("words", Some(count)) => count.parse::<u64>().map(|count| dump.words = count.max(1)).is_ok(),
                ("dir", Some(dir)) => {
                    dump.dir = Some(PathBuf::from(dir));
                    true
                }
                (buffer, None) => {
                    dump.buffers.push(buffer.to_owned());
                    true
                }
                _ => false,
            }
        });
        if dump.buffers.is_empty() {
            warn(format_args!("LANIUS_DUMP names no buffer; ignoring it"));
            return None;
        }
        Some(dump)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn options(pairs: &[(&str, &str)]) -> Options {
        Options::from_lookup(|name| {
            pairs.iter().find(|(key, _)| *key == name).map(|(_, value)| OsString::from(value))
        })
    }

    #[test]
    fn an_empty_environment_gives_the_defaults() {
        let options = options(&[]);
        assert_eq!(options.backend, Backend::Auto);
        assert!(!options.allow_software_adapter);
        assert!(options.driver_shader_cache);
        assert_eq!(options.readback_timeout, Duration::from_secs(120));
        assert_eq!(options.trace, Trace::default());
        assert_eq!(options.report, Report::default());
        assert_eq!(options.check, Check::default());
        assert_eq!(options.experiment, Experiment::default());
        assert!(options.capture.is_none() && options.dump.is_none());
        assert!(options.operation_limit.is_none());
    }

    #[test]
    fn word_lists_set_their_fields() {
        let options = options(&[
            ("LANIUS_TRACE", "stage-errors, wasm"),
            ("LANIUS_REPORT", "host-timing,resources=4096"),
            ("LANIUS_CHECK", "canonical-retry=40,lir-replays"),
            ("LANIUS_EXPERIMENT", "instance-table"),
        ]);
        assert!(options.trace.stage_errors && options.trace.wasm && !options.trace.canonical);
        assert!(options.report.host_timing && !options.report.gpu_timing);
        assert_eq!(options.report.resources, Some(4096));
        assert_eq!(options.check.canonical_retry, 16);
        assert!(options.check.lir_replays && !options.check.validation_scopes);
        assert!(options.experiment.instance_table);
    }

    #[test]
    fn an_unknown_word_leaves_the_others_set() {
        let options = options(&[("LANIUS_REPORT", "nothing,buffers,resources")]);
        assert!(options.report.buffers);
        assert_eq!(options.report.resources, Some(Report::DEFAULT_RESOURCES_LIMIT));
    }

    #[test]
    fn a_capture_names_one_pass_and_its_parameters() {
        let capture = options(&[("LANIUS_CAPTURE", "parser/tokens/to/kinds,index=3,dir=out,per-job")])
            .capture
            .expect("capture");
        assert_eq!(
            capture,
            Capture { pass: "parser/tokens/to/kinds".into(), index: 3, dir: "out".into(), per_job: true }
        );
        assert!(options(&[("LANIUS_CAPTURE", "index=3")]).capture.is_none());
    }

    #[test]
    fn a_dump_names_buffers_and_its_parameters() {
        let dump = options(&[("LANIUS_DUMP", "token_kind,*,words=8,dir=dumps")]).dump.expect("dump");
        assert_eq!(dump.buffers, ["token_kind", "*"]);
        assert_eq!(dump.words, 8);
        assert_eq!(dump.dir, Some(PathBuf::from("dumps")));
    }

    #[test]
    fn switches_accept_only_zero_and_one() {
        assert!(options(&[("LANIUS_ALLOW_SOFTWARE_ADAPTER", "1")]).allow_software_adapter);
        assert!(!options(&[("LANIUS_DRIVER_SHADER_CACHE", "0")]).driver_shader_cache);
        assert!(options(&[("LANIUS_DRIVER_SHADER_CACHE", "maybe")]).driver_shader_cache);
        assert_eq!(options(&[("LANIUS_BACKEND", "VK")]).backend, Backend::Vulkan);
    }
}
