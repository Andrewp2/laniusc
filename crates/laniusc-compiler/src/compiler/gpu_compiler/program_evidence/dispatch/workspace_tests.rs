//! Physical ownership and ordered-transfer regression coverage. Root runs these
//! with one test thread because resource-creation counters are process-wide.

use super::super::abi::{ArenaCopy, ArenaWrite};
use super::{arena::Arena, workspace::EvidenceWorkspacePool};
use crate::gpu::{buffers::buffer_creation_count, device, readback::PagedReadback};

fn contents(
    readback: &PagedReadback,
    gpu: &crate::gpu::device::GpuDevice,
    arena: &Arena,
) -> Vec<u32> {
    readback
        .read_buffer(
            &gpu.device,
            &gpu.queue,
            &arena.buffer,
            0,
            arena.logical_words as usize * 4,
            "workspace test contents",
        )
        .unwrap()
        .chunks_exact(4)
        .map(|v| u32::from_le_bytes(v.try_into().unwrap()))
        .collect()
}

#[test]
fn gpu_evidence_workspace_leases_isolate_live_arenas_and_trim_returns() {
    let gpu = device::global();
    let pool = EvidenceWorkspacePool::new(gpu.device.clone(), gpu.queue.clone());
    let readback = PagedReadback::new(&gpu.device, "workspace ownership readback", 128);
    let first = pool.checkout();
    let a = Arena::from_words(&first, "workspace.case", &[11, 12]).unwrap();
    let a_id = a.buffer.allocation_id();
    let same_label = Arena::from_words(&first, "workspace.case", &[13, 14]).unwrap();
    assert_ne!(
        a_id,
        same_label.buffer.allocation_id(),
        "same-label live roles must not alias"
    );
    drop(first); // The arenas, like independently retained packets, keep the lease.
    let second = pool.checkout();
    let b = Arena::from_words(&second, "workspace.case", &[21, 22]).unwrap();
    assert_ne!(
        a_id,
        b.buffer.allocation_id(),
        "overlapping sessions need separate storage"
    );
    assert_eq!(contents(&readback, gpu, &a), [11, 12]);
    assert_eq!(contents(&readback, gpu, &same_label), [13, 14]);
    assert_eq!(contents(&readback, gpu, &b), [21, 22]);

    pool.release(); // Neither pre-trim lease may refill the cleared pool later.
    drop((a, same_label, b, second));
    let third = pool.checkout();
    let c = Arena::from_words(&third, "workspace.case", &[31, 32]).unwrap();
    let c_id = c.buffer.allocation_id();
    assert_ne!(a_id, c_id);
    assert_eq!(contents(&readback, gpu, &c), [31, 32]);
    drop((c, third));
    let fourth = pool.checkout();
    let d = Arena::from_words(&fourth, "workspace.case", &[41, 42]).unwrap();
    assert_eq!(
        c_id,
        d.buffer.allocation_id(),
        "completed post-trim capacity is reusable"
    );
    assert_eq!(contents(&readback, gpu, &d), [41, 42]);
}

#[test]
fn gpu_evidence_workspace_reuses_capacity_preserving_transfer_order_and_zero_state() {
    let gpu = device::global();
    let pool = EvidenceWorkspacePool::new(gpu.device.clone(), gpu.queue.clone());
    let readback = PagedReadback::new(&gpu.device, "workspace transfer readback", 128);
    for iteration in 0..4u32 {
        let before = buffer_creation_count();
        let lease = pool.checkout();
        let mut arena = Arena::empty(&lease, "workspace.transfer").unwrap();
        let mut commands = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("workspace ordered transfers"),
            });
        arena.prepare(&mut commands, 8, &[]).unwrap();
        let seed = 100 * iteration;
        arena
            .upload(
                &mut commands,
                &[ArenaWrite {
                    first_word: 0,
                    words: (0..8).map(|v| seed + v).collect(),
                }],
            )
            .unwrap();
        arena
            .prepare(
                &mut commands,
                16,
                &[ArenaCopy {
                    from_word: 0,
                    to_word: 4,
                    word_count: 4,
                }],
            )
            .unwrap();
        arena
            .upload(
                &mut commands,
                &[
                    ArenaWrite {
                        first_word: 0,
                        words: vec![seed + 1000],
                    },
                    ArenaWrite {
                        first_word: 4,
                        words: vec![seed + 2000],
                    },
                ],
            )
            .unwrap();
        gpu.queue.submit(Some(commands.finish()));
        let actual = contents(&readback, gpu, &arena);
        assert_eq!(
            &actual[..8],
            &[
                seed + 1000,
                seed + 1,
                seed + 2,
                seed + 3,
                seed + 2000,
                seed + 1,
                seed + 2,
                seed + 3
            ]
        );
        assert_eq!(
            &actual[8..],
            &[0; 8],
            "new logical range must not expose a previous job"
        );
        // Poison the next job's newly exposed suffix. Reuse must clear it before
        // any relocation or upload makes those logical words observable.
        arena.buffer.write(&gpu.queue, 32, &[0x5a; 32]);
        if iteration == 3 {
            assert_eq!(
                buffer_creation_count(),
                before,
                "repeated bounded work must not allocate after growth/relocation priming"
            );
        }
    }
}
