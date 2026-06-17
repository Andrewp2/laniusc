use anyhow::Result;

use super::super::support::{UniformBindingArray, reflected_bind_group};
use crate::gpu::passes_core::PassData;

pub(super) struct StepNames {
    pub(super) first_in: &'static str,
    pub(super) second_in: &'static str,
    pub(super) first_out: &'static str,
    pub(super) second_out: &'static str,
}

pub(super) struct StepPairs<'a> {
    pub(super) first_a: &'a wgpu::Buffer,
    pub(super) first_b: &'a wgpu::Buffer,
    pub(super) second_a: &'a wgpu::Buffer,
    pub(super) second_b: &'a wgpu::Buffer,
}

pub(super) struct StepOneNames {
    pub(super) in_name: &'static str,
    pub(super) out_name: &'static str,
}

pub(super) struct StepOne<'a> {
    pub(super) a: &'a wgpu::Buffer,
    pub(super) b: &'a wgpu::Buffer,
}

pub(super) fn step_pair_groups(
    device: &wgpu::Device,
    label: &'static str,
    pass: &PassData,
    steps: &[u32],
    params_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    extra_buffers: &[(&'static str, &wgpu::Buffer)],
    names: StepNames,
    pairs: StepPairs<'_>,
) -> Result<Vec<wgpu::BindGroup>> {
    steps
        .iter()
        .enumerate()
        .map(|(step_i, _step)| {
            let (first_in, second_in, first_out, second_out) = if step_i % 2 == 0 {
                (pairs.first_a, pairs.second_a, pairs.first_b, pairs.second_b)
            } else {
                (pairs.first_b, pairs.second_b, pairs.first_a, pairs.second_a)
            };
            let mut bindings = Vec::with_capacity(2 + extra_buffers.len() + 4);
            bindings.push(("gParams", params_buf.as_entire_binding()));
            bindings.push(("hir_status", hir_status_buf.as_entire_binding()));
            bindings.extend(
                extra_buffers
                    .iter()
                    .map(|(name, buffer)| (*name, buffer.as_entire_binding())),
            );
            bindings.extend([
                (names.first_in, first_in.as_entire_binding()),
                (names.second_in, second_in.as_entire_binding()),
                (names.first_out, first_out.as_entire_binding()),
                (names.second_out, second_out.as_entire_binding()),
            ]);
            reflected_bind_group(device, Some(label), pass, 0, &bindings)
        })
        .collect()
}

pub(super) fn step_one_groups(
    device: &wgpu::Device,
    label: &'static str,
    pass: &PassData,
    steps: &[u32],
    params_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    names: StepOneNames,
    pair: StepOne<'_>,
) -> Result<Vec<wgpu::BindGroup>> {
    steps
        .iter()
        .enumerate()
        .map(|(step_i, _step)| {
            let (record_in, record_out) = if step_i % 2 == 0 {
                (pair.a, pair.b)
            } else {
                (pair.b, pair.a)
            };
            reflected_bind_group(
                device,
                Some(label),
                pass,
                0,
                &[
                    ("gParams", params_buf.as_entire_binding()),
                    ("hir_status", hir_status_buf.as_entire_binding()),
                    (names.in_name, record_in.as_entire_binding()),
                    (names.out_name, record_out.as_entire_binding()),
                ],
            )
        })
        .collect()
}

pub(super) fn scan_block_groups(
    device: &wgpu::Device,
    labels: [&'static str; 2],
    pass: &PassData,
    params: &UniformBindingArray,
    scan_params_name: &'static str,
    sum_name: &'static str,
    prefix_in_name: &'static str,
    prefix_out_name: &'static str,
    block_sum: &wgpu::Buffer,
    prefix_a: &wgpu::Buffer,
    prefix_b: &wgpu::Buffer,
) -> Result<Vec<wgpu::BindGroup>> {
    (0..2)
        .map(|step_i| {
            let (prefix_in, prefix_out) = if step_i == 0 {
                (prefix_b, prefix_a)
            } else {
                (prefix_a, prefix_b)
            };
            reflected_bind_group(
                device,
                Some(labels[step_i]),
                pass,
                0,
                &[
                    (scan_params_name, params.binding(0)),
                    (sum_name, block_sum.as_entire_binding()),
                    (prefix_in_name, prefix_in.as_entire_binding()),
                    (prefix_out_name, prefix_out.as_entire_binding()),
                ],
            )
        })
        .collect()
}
