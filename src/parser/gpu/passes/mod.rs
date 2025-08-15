
use anyhow::{Result, anyhow};
use wgpu;

use crate::gpu::passes_core::{
    DispatchDim,
    InputElements,
    PassData,
    bind_group,
};

pub mod llp_pairs;
pub mod pack_varlen;

pub trait Pass {
    const NAME: &'static str = "";

    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self
    where
        Self: Sized;

    fn data(&self) -> &PassData;

    fn create_resource_map<'a>(
        &self,
        buffers: &'a crate::parser::gpu::buffers::ParserBuffers,
    ) -> std::collections::HashMap<String, wgpu::BindingResource<'a>>;

    fn get_dispatch_size_1d(&self, n: u32) -> (u32, u32, u32) {
        let tgs = self.data().thread_group_size[0].max(1);
        (n.div_ceil(tgs), 1, 1)
    }

    fn get_dispatch_size_2d(&self, nx: u32, ny: u32) -> (u32, u32, u32) {
        let tgsx = self.data().thread_group_size[0].max(1);
        let tgsy = self.data().thread_group_size[1].max(1);
        (nx.div_ceil(tgsx), ny.div_ceil(tgsy), 1)
    }

    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &crate::parser::gpu::buffers::ParserBuffers,
        input: InputElements,
    ) -> Result<(), anyhow::Error> {
        let mut dispatch = match (Self::DIM, input) {
            (DispatchDim::D1, InputElements::Elements1D(n)) => self.get_dispatch_size_1d(n),
            (DispatchDim::D2, InputElements::Elements2D(nx, ny)) => {
                self.get_dispatch_size_2d(nx, ny)
            }
            (DispatchDim::D2, InputElements::Elements1D(n)) => self.get_dispatch_size_1d(n),
            _ => unreachable!("dimension/input mismatch"),
        };

        const MAX_PER_DIM: u32 = 65_535;
        if matches!(Self::DIM, DispatchDim::D2) && dispatch.0 > MAX_PER_DIM {
            let gx = MAX_PER_DIM;
            let gy = dispatch.0.div_ceil(MAX_PER_DIM);
            if gy > MAX_PER_DIM {
                return Err(anyhow!("dispatch too large for 2D"));
            }
            dispatch = (gx, gy, 1);
        }
        if dispatch.0 > MAX_PER_DIM || dispatch.1 > MAX_PER_DIM || dispatch.2 > MAX_PER_DIM {
            return Err(anyhow!("dispatch exceeds per-dimension limits"));
        }

        let resources = self.create_resource_map(buffers);
        let data = self.data();
        let mut bgs = Vec::<wgpu::BindGroup>::new();

        for (set_index, bgl) in data.bind_group_layouts.iter().enumerate() {
            let bg = bind_group::create_bind_group_from_reflection(
                device,
                Some(Self::NAME),
                bgl,
                &data.reflection,
                set_index,
                &resources,
            )?;
            bgs.push(bg);
        }

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(Self::NAME),
            timestamp_writes: None,
        });
        pass.set_pipeline(&data.pipeline);
        for (i, bg) in bgs.iter().enumerate() {
            pass.set_bind_group(i as u32, bg, &[]);
        }
        pass.dispatch_workgroups(dispatch.0, dispatch.1, dispatch.2);
        drop(pass);

        Ok(())
    }
}
