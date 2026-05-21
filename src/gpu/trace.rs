use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

use log::warn;
use serde::Serialize;

#[derive(Clone, Serialize)]
struct TraceEvent {
    name: String,
    cat: String,
    ph: &'static str,
    ts: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    dur: Option<f64>,
    pid: u32,
    tid: u32,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    args: BTreeMap<String, serde_json::Value>,
}

struct TraceState {
    path: Option<PathBuf>,
    start: Instant,
    events: Vec<TraceEvent>,
    lane_ids: HashMap<String, u32>,
    next_tid: u32,
}

impl TraceState {
    fn new() -> Self {
        let path = std::env::var_os("LANIUS_PERFETTO_TRACE")
            .or_else(|| std::env::var_os("LANIUS_GPU_TRACE_JSON"))
            .map(PathBuf::from);
        Self {
            path,
            start: Instant::now(),
            events: Vec::new(),
            lane_ids: HashMap::new(),
            next_tid: 1,
        }
    }

    fn enabled(&self) -> bool {
        self.path.is_some()
    }

    fn lane_id(&mut self, lane: &str) -> u32 {
        if let Some(id) = self.lane_ids.get(lane) {
            return *id;
        }
        if self.events.is_empty() {
            let mut args = BTreeMap::new();
            args.insert(
                "name".to_string(),
                serde_json::Value::String("laniusc".to_string()),
            );
            self.events.push(TraceEvent {
                name: "process_name".to_string(),
                cat: "__metadata".to_string(),
                ph: "M",
                ts: 0.0,
                dur: None,
                pid: 1,
                tid: 0,
                args,
            });
        }
        let id = self.next_tid;
        self.next_tid = self.next_tid.saturating_add(1);
        self.lane_ids.insert(lane.to_string(), id);

        let mut args = BTreeMap::new();
        args.insert(
            "name".to_string(),
            serde_json::Value::String(lane.to_string()),
        );
        self.events.push(TraceEvent {
            name: "thread_name".to_string(),
            cat: "__metadata".to_string(),
            ph: "M",
            ts: 0.0,
            dur: None,
            pid: 1,
            tid: id,
            args,
        });
        id
    }

    fn instant_us(&self, instant: Instant) -> f64 {
        duration_us(
            instant
                .checked_duration_since(self.start)
                .unwrap_or_default(),
        )
    }
}

pub fn enabled() -> bool {
    match state().lock() {
        Ok(state) => state.enabled(),
        Err(err) => {
            warn!("failed to lock GPU trace state: {err}");
            false
        }
    }
}

pub fn record_host_span(lane: &str, name: &str, start: Instant, end: Instant) {
    record_span_between("host", lane, name, start, end);
}

pub fn record_gpu_span(lane: &str, name: &str, anchor: Instant, start_ms: f64, dur_ms: f64) {
    record_span_at(
        "gpu",
        lane,
        name,
        |state| state.instant_us(anchor) + start_ms * 1000.0,
        dur_ms * 1000.0,
    );
}

pub fn record_instant(lane: &str, name: &str, at: Instant) {
    match state().lock() {
        Ok(mut state) => {
            if !state.enabled() {
                return;
            }
            let tid = state.lane_id(lane);
            let ts = state.instant_us(at);
            let mut args = BTreeMap::new();
            args.insert(
                "lane".to_string(),
                serde_json::Value::String(lane.to_string()),
            );
            state.events.push(TraceEvent {
                name: name.to_string(),
                cat: "host".to_string(),
                ph: "i",
                ts,
                dur: None,
                pid: 1,
                tid,
                args,
            });
        }
        Err(err) => warn!("failed to lock GPU trace state: {err}"),
    }
}

pub fn record_counter(lane: &str, name: &str, at: Instant, value: f64) {
    match state().lock() {
        Ok(mut state) => {
            if !state.enabled() {
                return;
            }
            let tid = state.lane_id(lane);
            let ts = state.instant_us(at);
            let mut args = BTreeMap::new();
            args.insert(name.to_string(), serde_json::json!(value));
            state.events.push(TraceEvent {
                name: name.to_string(),
                cat: "counter".to_string(),
                ph: "C",
                ts,
                dur: None,
                pid: 1,
                tid,
                args,
            });
        }
        Err(err) => warn!("failed to lock GPU trace state: {err}"),
    }
}

pub fn flush() {
    let (path, mut events) = match state().lock() {
        Ok(state) => {
            let Some(path) = state.path.clone() else {
                return;
            };
            (path, state.events.clone())
        }
        Err(err) => {
            warn!("failed to lock GPU trace state for flush: {err}");
            return;
        }
    };
    events.sort_by(|left, right| {
        trace_event_rank(left)
            .cmp(&trace_event_rank(right))
            .then_with(|| left.ts.total_cmp(&right.ts))
            .then_with(|| left.tid.cmp(&right.tid))
            .then_with(|| left.name.cmp(&right.name))
    });

    if let Some(parent) = path.parent()
        && let Err(err) = std::fs::create_dir_all(parent)
    {
        warn!(
            "failed to create GPU trace directory {}: {err}",
            parent.display()
        );
        return;
    }

    let payload = serde_json::json!({
        "displayTimeUnit": "ms",
        "traceEvents": events,
    });
    match serde_json::to_vec_pretty(&payload) {
        Ok(bytes) => {
            if let Err(err) = std::fs::write(&path, bytes) {
                warn!("failed to write GPU trace {}: {err}", path.display());
            }
        }
        Err(err) => warn!("failed to encode GPU trace: {err}"),
    }
}

fn record_span_at(
    cat: &str,
    lane: &str,
    name: &str,
    start_us: impl FnOnce(&TraceState) -> f64,
    dur_us: f64,
) {
    match state().lock() {
        Ok(mut state) => {
            if !state.enabled() {
                return;
            }
            let ts = start_us(&state);
            let tid = state.lane_id(lane);
            let mut args = BTreeMap::new();
            args.insert(
                "lane".to_string(),
                serde_json::Value::String(lane.to_string()),
            );
            state.events.push(TraceEvent {
                name: name.to_string(),
                cat: cat.to_string(),
                ph: "X",
                ts,
                dur: Some(dur_us.max(0.0)),
                pid: 1,
                tid,
                args,
            });
        }
        Err(err) => warn!("failed to lock GPU trace state: {err}"),
    }
}

fn record_span_between(cat: &str, lane: &str, name: &str, start: Instant, end: Instant) {
    match state().lock() {
        Ok(mut state) => {
            if !state.enabled() {
                return;
            }
            let ts = state.instant_us(start);
            let end_ts = state.instant_us(end);
            let tid = state.lane_id(lane);
            let mut args = BTreeMap::new();
            args.insert(
                "lane".to_string(),
                serde_json::Value::String(lane.to_string()),
            );
            state.events.push(TraceEvent {
                name: name.to_string(),
                cat: cat.to_string(),
                ph: "X",
                ts,
                dur: Some((end_ts - ts).max(0.0)),
                pid: 1,
                tid,
                args,
            });
        }
        Err(err) => warn!("failed to lock GPU trace state: {err}"),
    }
}

fn duration_us(duration: Duration) -> f64 {
    duration.as_secs_f64() * 1_000_000.0
}

fn trace_event_rank(event: &TraceEvent) -> u8 {
    if event.ph == "M" { 0 } else { 1 }
}

fn state() -> &'static Mutex<TraceState> {
    static STATE: OnceLock<Mutex<TraceState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(TraceState::new()))
}
