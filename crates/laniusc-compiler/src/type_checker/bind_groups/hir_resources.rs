use super::super::*;

/// Registers the compact HIR as the type checker's sole frontend input.
pub(super) fn register_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    input: GpuTypeCheckHirItemBuffers<'a>,
) {
    for (name, buffer) in input.hir.named_buffers() {
        resources.buffer(name, buffer);
    }
}
