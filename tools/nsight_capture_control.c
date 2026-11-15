/* Built against the installed NVIDIA SDK by run_nsight_gpu_trace.sh.
 * The caller must drain ALL workload queues before begin and end. */
#include "NGFX_GPUTrace_Vulkan.h"

int lanius_ngfx_begin(void)
{
    /* Development profiling only; ngfx has already injected these libraries. */
    NGFX_SetLibraryLoadFn(NGFX_LoadLib_NoVerification);
    NGFX_GPUTrace_InitializeActivity_Vulkan_Params init = {
        .version = NGFX_GPUTrace_InitializeActivity_Vulkan_Params_VER,
    };
    NGFX_Result result = NGFX_GPUTrace_InitializeActivity_Vulkan(&init);
    if (result != NGFX_Result_Success) return result;

    /* Warmup submissions activate the profiler without starting collection. */
    NGFX_GPUTrace_WaitForStatus_Params wait = {
        .version = NGFX_GPUTrace_WaitForStatus_Params_VER,
        .status = NGFX_GPUTrace_Status_Active,
        .timeoutMs = 30000,
    };
    result = NGFX_GPUTrace_WaitForStatus(&wait);
    if (result != NGFX_Result_Success) return result;
    NGFX_GPUTrace_StartTrace_Vulkan_Params start = {
        .version = NGFX_GPUTrace_StartTrace_Vulkan_Params_VER,
    };
    result = NGFX_GPUTrace_StartTrace_Vulkan(&start);
    if (result != NGFX_Result_Success) return result;
    wait.status = NGFX_GPUTrace_Status_Tracing;
    return NGFX_GPUTrace_WaitForStatus(&wait);
}

int lanius_ngfx_end(void)
{
    NGFX_GPUTrace_GetStatus_Params status = {
        .version = NGFX_GPUTrace_GetStatus_Params_VER,
    };
    NGFX_Result result = NGFX_GPUTrace_GetStatus(&status);
    if (result != NGFX_Result_Success) return result;
    /* A duration/buffer limit must never masquerade as a completed capture. */
    if (status.status != NGFX_GPUTrace_Status_Tracing)
        return NGFX_Result_InvalidState;
    NGFX_GPUTrace_StopTrace_Vulkan_Params stop = {
        .version = NGFX_GPUTrace_StopTrace_Vulkan_Params_VER,
        .flags = NGFX_GPUTrace_StopTraceFlag_ImmediateCollection,
        /* Safe only because the caller has waited for every GPU queue. */
        .queue = NULL,
    };
    return NGFX_GPUTrace_StopTrace_Vulkan(&stop);
}
