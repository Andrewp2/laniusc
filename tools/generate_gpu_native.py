#!/usr/bin/env python3
"""Generate the deliberately bounded Linux LP64 Vulkan ABI from Khronos headers.
No renderer is generated. cc runs only to measure C record layouts/constants.
"""
import argparse, os, pathlib, re, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
STRUCTS = '''
ApplicationInfo pApplicationName applicationVersion pEngineName engineVersion apiVersion
InstanceCreateInfo pApplicationInfo enabledLayerCount ppEnabledLayerNames enabledExtensionCount ppEnabledExtensionNames
PhysicalDeviceProperties apiVersion deviceType deviceName
PhysicalDeviceFeatures2 pNext features
PhysicalDeviceSwapchainMaintenance1FeaturesEXT swapchainMaintenance1
QueueFamilyProperties queueFlags queueCount
DeviceQueueCreateInfo queueFamilyIndex queueCount pQueuePriorities
DeviceCreateInfo pNext queueCreateInfoCount pQueueCreateInfos enabledExtensionCount ppEnabledExtensionNames
PhysicalDeviceMemoryProperties memoryTypeCount memoryTypes
MemoryType propertyFlags heapIndex
BufferCreateInfo size usage sharingMode
MemoryRequirements size alignment memoryTypeBits
MemoryAllocateInfo allocationSize memoryTypeIndex
CommandPoolCreateInfo flags queueFamilyIndex
CommandBufferAllocateInfo commandPool level commandBufferCount
CommandBufferBeginInfo flags
BufferCopy srcOffset dstOffset size
MemoryBarrier srcAccessMask dstAccessMask
FenceCreateInfo flags
SubmitInfo waitSemaphoreCount pWaitSemaphores pWaitDstStageMask commandBufferCount pCommandBuffers signalSemaphoreCount pSignalSemaphores
XlibSurfaceCreateInfoKHR dpy window
SurfaceCapabilitiesKHR minImageCount maxImageCount currentExtent minImageExtent maxImageExtent supportedTransforms currentTransform supportedCompositeAlpha supportedUsageFlags
SurfaceFormatKHR format colorSpace
SwapchainCreateInfoKHR surface minImageCount imageFormat imageColorSpace imageExtent imageArrayLayers imageUsage imageSharingMode preTransform compositeAlpha presentMode clipped oldSwapchain
ImageViewCreateInfo image viewType format components subresourceRange
AttachmentDescription format samples loadOp storeOp stencilLoadOp stencilStoreOp initialLayout finalLayout
AttachmentReference attachment layout
SubpassDescription pipelineBindPoint colorAttachmentCount pColorAttachments
SubpassDependency srcSubpass dstSubpass srcStageMask dstStageMask srcAccessMask dstAccessMask
RenderPassCreateInfo attachmentCount pAttachments subpassCount pSubpasses dependencyCount pDependencies
FramebufferCreateInfo renderPass attachmentCount pAttachments width height layers
ShaderModuleCreateInfo codeSize pCode
PipelineShaderStageCreateInfo stage module pName
PipelineVertexInputStateCreateInfo
PipelineInputAssemblyStateCreateInfo topology
PipelineViewportStateCreateInfo viewportCount scissorCount
PipelineRasterizationStateCreateInfo polygonMode cullMode frontFace lineWidth
PipelineMultisampleStateCreateInfo rasterizationSamples
PipelineColorBlendAttachmentState colorWriteMask
PipelineColorBlendStateCreateInfo attachmentCount pAttachments
PipelineDynamicStateCreateInfo dynamicStateCount pDynamicStates
PipelineLayoutCreateInfo setLayoutCount pSetLayouts
GraphicsPipelineCreateInfo stageCount pStages pVertexInputState pInputAssemblyState pViewportState pRasterizationState pMultisampleState pColorBlendState pDynamicState layout renderPass subpass basePipelineIndex
SemaphoreCreateInfo flags
RenderPassBeginInfo renderPass framebuffer renderArea clearValueCount pClearValues
Viewport x y width height minDepth maxDepth
Rect2D offset extent
ImageMemoryBarrier srcAccessMask dstAccessMask oldLayout newLayout srcQueueFamilyIndex dstQueueFamilyIndex image subresourceRange
BufferImageCopy bufferOffset bufferRowLength bufferImageHeight imageSubresource imageOffset imageExtent
PresentInfoKHR pNext waitSemaphoreCount pWaitSemaphores swapchainCount pSwapchains pImageIndices
SwapchainPresentFenceInfoEXT swapchainCount pFences
'''
STRUCTS += """
ImageCreateInfo imageType format extent mipLevels arrayLayers samples tiling usage sharingMode initialLayout
FormatProperties optimalTilingFeatures
ImageFormatProperties maxExtent maxMipLevels maxArrayLayers sampleCounts maxResourceSize
SamplerCreateInfo magFilter minFilter mipmapMode addressModeU addressModeV addressModeW maxLod
DescriptorSetLayoutBinding binding descriptorType descriptorCount stageFlags
DescriptorSetLayoutCreateInfo bindingCount pBindings
DescriptorPoolSize type descriptorCount
DescriptorPoolCreateInfo maxSets poolSizeCount pPoolSizes
DescriptorSetAllocateInfo descriptorPool descriptorSetCount pSetLayouts
DescriptorBufferInfo buffer offset range
DescriptorImageInfo sampler imageView imageLayout
WriteDescriptorSet dstSet dstBinding descriptorCount descriptorType pImageInfo pBufferInfo
ComputePipelineCreateInfo stage layout basePipelineIndex
"""
FUNCTIONS = '''vkCreateInstance vkDestroyInstance vkEnumeratePhysicalDevices vkGetPhysicalDeviceProperties vkGetPhysicalDeviceFeatures2 vkGetPhysicalDeviceQueueFamilyProperties vkCreateDevice vkDestroyDevice vkGetDeviceQueue vkGetPhysicalDeviceMemoryProperties vkCreateBuffer vkDestroyBuffer vkGetBufferMemoryRequirements vkAllocateMemory vkFreeMemory vkBindBufferMemory vkMapMemory vkUnmapMemory vkCreateCommandPool vkDestroyCommandPool vkAllocateCommandBuffers vkResetCommandPool vkBeginCommandBuffer vkEndCommandBuffer vkCreateFence vkDestroyFence vkWaitForFences vkResetFences vkQueueSubmit vkDeviceWaitIdle vkCmdCopyBuffer vkCmdPipelineBarrier vkCreateXlibSurfaceKHR vkDestroySurfaceKHR vkGetPhysicalDeviceSurfaceSupportKHR vkGetPhysicalDeviceSurfaceCapabilitiesKHR vkGetPhysicalDeviceSurfaceFormatsKHR vkCreateSwapchainKHR vkDestroySwapchainKHR vkGetSwapchainImagesKHR vkCreateImageView vkDestroyImageView vkCreateRenderPass vkDestroyRenderPass vkCreateFramebuffer vkDestroyFramebuffer vkCreateShaderModule vkDestroyShaderModule vkCreatePipelineLayout vkDestroyPipelineLayout vkCreateGraphicsPipelines vkDestroyPipeline vkCreateSemaphore vkDestroySemaphore vkAcquireNextImageKHR vkQueuePresentKHR vkCmdBeginRenderPass vkCmdEndRenderPass vkCmdBindPipeline vkCmdSetViewport vkCmdSetScissor vkCmdDraw vkCmdCopyImageToBuffer'''.split()
CONSTANTS = '''VK_API_VERSION_1_1 VK_STRUCTURE_TYPE_APPLICATION_INFO VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_EXT VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO VK_STRUCTURE_TYPE_FENCE_CREATE_INFO VK_STRUCTURE_TYPE_SUBMIT_INFO VK_STRUCTURE_TYPE_MEMORY_BARRIER VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER VK_STRUCTURE_TYPE_PRESENT_INFO_KHR VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_FENCE_INFO_EXT VK_ERROR_DEVICE_LOST VK_ERROR_OUT_OF_DATE_KHR VK_SUBOPTIMAL_KHR VK_ERROR_SURFACE_LOST_KHR'''.split()

FUNCTIONS += """vkCreateImage vkDestroyImage vkGetImageMemoryRequirements vkBindImageMemory vkGetPhysicalDeviceFormatProperties vkGetPhysicalDeviceImageFormatProperties vkCreateSampler vkDestroySampler vkCreateDescriptorSetLayout vkDestroyDescriptorSetLayout vkCreateDescriptorPool vkDestroyDescriptorPool vkAllocateDescriptorSets vkUpdateDescriptorSets vkCreateComputePipelines vkCmdBindDescriptorSets vkCmdDispatch vkCmdCopyBufferToImage vkCmdClearColorImage vkGetFenceStatus""".split()
CONSTANTS += """VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO""".split()

def generate(include):
    source = ['#define VK_USE_PLATFORM_XLIB_KHR', '#include <vulkan/vulkan.h>', '#include <stdio.h>', '#include <stddef.h>', '_Static_assert(sizeof(void*)==8 && sizeof(long)==8,"LP64 required");', 'int main(void) {']
    for line in STRUCTS.splitlines():
        if not line.strip(): continue
        name,*fields=line.split()
        source.append(f'printf("pub const SIZE_{name}:usize=%zu;\\n",sizeof(Vk{name}));')
        for f in fields:
            source.append(f'printf("pub const {name}_{f}:usize=%zu;\\n",offsetof(Vk{name},{f}));')
    for name in CONSTANTS:
        source.append(f'printf("pub const {name}:i32=%d;\\n",(int){name});')
    source.append('return 0;}')
    with tempfile.TemporaryDirectory(prefix='lanius-vulkan-abi-') as temp:
        c=pathlib.Path(temp)/'abi.c'; exe=pathlib.Path(temp)/'abi'; c.write_text('\n'.join(source))
        subprocess.run([os.getenv('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror','-I',str(include),str(c),'-o',str(exe)],check=True,timeout=30)
        constants=subprocess.check_output([str(exe)],text=True,timeout=10)
    headers='\n'.join((include/'vulkan'/f).read_text() for f in ['vulkan_core.h','vulkan_xlib.h'])
    dispatch={'VkInstance','VkPhysicalDevice','VkDevice','VkQueue','VkCommandBuffer'}
    handles=set(re.findall(r'VK_DEFINE_NON_DISPATCHABLE_HANDLE\((\w+)\)',headers))
    def typ(s):
        s=s.strip()
        if '*' in s or '[' in s: return 'ptr'
        if s in dispatch: return 'ptr'
        if s in handles or s in {'uint64_t','VkDeviceSize'}: return 'u64'
        if s=='size_t': return 'usize'
        if s=='float': return 'f32'
        if s=='void': return ''
        if s in {'uint32_t','VkBool32','VkSampleMask'} or s.endswith('Flags'): return 'u32'
        if s.startswith('Vk'): return 'i32' # enums in this explicit function subset
        raise ValueError(s)
    declarations=[]
    for name in FUNCTIONS:
        match=re.search(r'VKAPI_ATTR\s+(\w+)\s+VKAPI_CALL\s+'+name+r'\((.*?)\);',headers,re.S)
        if not match: raise ValueError(name)
        ret,params=match.groups(); args=[]
        for i,p in enumerate(params.split(',')):
            p=p.strip()
            if p=='void': continue
            part=re.match(r'(.*?)\b\w+\s*(\[[^]]*\])?$',p)
            if not part: raise ValueError(p)
            args.append(f'a{i}:{typ(part[1]+(part[2] or ""))}')
        result=typ(ret)
        declarations.append(f'pub extern "C" fn {name}('+','.join(args)+')'+(' -> '+result if result else '')+';')
    result = '// Generated by tools/generate_gpu_native.py from Khronos Vulkan headers.\n// Linux x86_64 LP64 only; raw unsafe backend support, not a safe graphics API.\nmodule ext::gpu_native;\n'+constants+'\n'+'\n'.join(declarations)+'\n'
    return result.replace('VK_STRUCTURE_TYPE_', 'ST_').replace('PhysicalDeviceSwapchainMaintenance1FeaturesEXT_swapchainMaintenance1', 'Maintenance_enabled')

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--include',type=pathlib.Path,default=pathlib.Path('/usr/include')); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    result=generate(args.include); path=ROOT/'extended/ext/gpu_native.lani'
    if args.check:
        if path.read_text()!=result: raise SystemExit('Vulkan ABI differs; regenerate for the supported LP64 profile')
        print('Vulkan ABI matches installed headers')
    else: path.write_text(result)
