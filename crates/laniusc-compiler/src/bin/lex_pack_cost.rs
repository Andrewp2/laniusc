//! Measures the cost of lexing a source pack: file reads, upload, lexer GPU
//! time and buffer bytes. Usage: lex_pack_cost <file-list> [reps]
use std::{env, fs, time::Instant};

use laniusc_compiler::{gpu::buffers::tracked_buffer_allocation_stats, lexer::GpuLexer};

thread_local! { static HOST: std::cell::RefCell<Vec<f64>> = const { std::cell::RefCell::new(Vec::new()) }; }

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[v.len() / 2]
}

fn main() {
    let list = env::args().nth(1).expect("file list");
    let reps: usize = env::args().nth(2).map(|r| r.parse().unwrap()).unwrap_or(15);
    let paths: Vec<String> = fs::read_to_string(&list)
        .unwrap()
        .lines()
        .filter(|l| !l.is_empty())
        .map(str::to_owned)
        .collect();
    let mut reads = Vec::new();
    let mut sources = Vec::new();
    for _ in 0..reps {
        let t = Instant::now();
        sources = paths.iter().map(|p| fs::read_to_string(p).unwrap()).collect::<Vec<_>>();
        reads.push(t.elapsed().as_secs_f64() * 1e3);
    }
    let bytes: usize = sources.iter().map(String::len).sum();
    pollster::block_on(async {
        let before = tracked_buffer_allocation_stats().bytes;
        let lexer = GpuLexer::new().await.unwrap();
        let mut lex = Vec::new();
        let mut upload = Vec::new();
        for i in 0..reps + 3 {
            let mut joined = sources.concat().into_bytes();
            joined.resize(joined.len().next_multiple_of(4), 0);
            let t = Instant::now();
            let (ms, up) = lexer
                .with_resident_source_pack_tokens(&sources, |device, queue, _| {
                    let host = t.elapsed().as_secs_f64() * 1e3;
                    device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
                    let ms = t.elapsed().as_secs_f64() * 1e3;
                    HOST.with(|h| h.borrow_mut().push(host));
                    // The upload alone: the same bytes written to one buffer.
                    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some("upload-probe"),
                        size: joined.len() as u64,
                        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    });
                    let t = Instant::now();
                    queue.write_buffer(&buffer, 0, &joined);
                    queue.submit([]);
                    device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
                    (ms, t.elapsed().as_secs_f64() * 1e3)
                })
                .await
                .unwrap();
            if i >= 3 {
                lex.push(ms);
                upload.push(up);
            }
        }
        let after = tracked_buffer_allocation_stats().bytes;
        println!(
            "host_prepare_record_submit_ms={:.3} files={} bytes={} read_ms={:.3} upload_ms={:.3} lex_submit_to_done_ms={:.3} lexer_buffer_bytes={}",
            median(HOST.with(|h| h.borrow()[3..].to_vec())),
            paths.len(),
            bytes,
            median(reads),
            median(upload),
            median(lex),
            after - before
        );
    });
}
