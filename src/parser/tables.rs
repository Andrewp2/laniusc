use crate::parser::gpu::buffers::ActionHeader;

pub fn build_dummy_action_table(n_kinds: u32) -> Vec<u8> {
    let n = (n_kinds as usize) * (n_kinds as usize);
    let v = vec![0; n * std::mem::size_of::<ActionHeader>()];
    v
}
