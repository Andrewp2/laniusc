// Native test oracle/interposition only. All production GPU logic is Lanius.
#define _GNU_SOURCE
#define VK_USE_PLATFORM_XLIB_KHR
#include <vulkan/vulkan.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <string.h>
#include <assert.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#define REAL(n) PFN_##n real=(PFN_##n)dlsym(RTLD_NEXT,#n); assert(real)
static int fault,hits,live[20],frames,hold,waits;
void probe_hold(int value) { hold=value; }
int probe_waits(void) { return waits; }
static Display *display;
static Window window;
static VkFence last_present_fence;
static int life_mode,life_phase,life_dispatches,life_saved_dispatches,life_uploads;
static void life_controls(void);
static int fail(int id) { if(fault!=id) return 0; fault=0; ++hits; return 1; }
void probe_fault(int id) { assert(!fault); fault=id; }
int probe_live(void) { int n=0; for(int i=0;i<20;++i) n+=live[i]; return n; }
int probe_hits(void) { assert(!fault); return hits; }
void probe_empty(void) { assert(!fault); for(int i=0;i<20;++i) assert(live[i]==0); }
// Explicit signatures keep the observer checked by the official header.
#define DEVICE_CREATE(name,info,handle,slot,id) \
VKAPI_ATTR VkResult VKAPI_CALL name(VkDevice d,const info *i,const VkAllocationCallbacks *a,handle *out) { \
 if(fail(id)) return VK_ERROR_OUT_OF_HOST_MEMORY; \
 REAL(name); VkResult r=real(d,i,a,out); if(r==VK_SUCCESS) ++live[slot]; return r; }
#define DEVICE_DESTROY(name,handle,slot) \
VKAPI_ATTR void VKAPI_CALL name(VkDevice d,handle h,const VkAllocationCallbacks *a) { REAL(name); assert(live[slot]>0); --live[slot]; real(d,h,a); }
DEVICE_CREATE(vkCreateBuffer,VkBufferCreateInfo,VkBuffer,0,1)
DEVICE_DESTROY(vkDestroyBuffer,VkBuffer,0)
DEVICE_CREATE(vkAllocateMemory,VkMemoryAllocateInfo,VkDeviceMemory,1,2)
DEVICE_DESTROY(vkFreeMemory,VkDeviceMemory,1)
VKAPI_ATTR VkResult VKAPI_CALL vkCreateShaderModule(VkDevice d,const VkShaderModuleCreateInfo *i,const VkAllocationCallbacks *a,VkShaderModule *out) { if(fail(5) || (live[2]>0 && fail(18))) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkCreateShaderModule); VkResult r=real(d,i,a,out); if(r==VK_SUCCESS) ++live[2]; return r; }
DEVICE_DESTROY(vkDestroyShaderModule,VkShaderModule,2)
DEVICE_CREATE(vkCreatePipelineLayout,VkPipelineLayoutCreateInfo,VkPipelineLayout,3,6)
DEVICE_DESTROY(vkDestroyPipelineLayout,VkPipelineLayout,3)
DEVICE_CREATE(vkCreateSwapchainKHR,VkSwapchainCreateInfoKHR,VkSwapchainKHR,4,8)
DEVICE_DESTROY(vkDestroySwapchainKHR,VkSwapchainKHR,4)
DEVICE_CREATE(vkCreateImageView,VkImageViewCreateInfo,VkImageView,5,9)
DEVICE_DESTROY(vkDestroyImageView,VkImageView,5)
DEVICE_CREATE(vkCreateFramebuffer,VkFramebufferCreateInfo,VkFramebuffer,6,10)
DEVICE_DESTROY(vkDestroyFramebuffer,VkFramebuffer,6)
DEVICE_CREATE(vkCreateRenderPass,VkRenderPassCreateInfo,VkRenderPass,7,11)
DEVICE_DESTROY(vkDestroyRenderPass,VkRenderPass,7)
DEVICE_CREATE(vkCreateFence,VkFenceCreateInfo,VkFence,8,12)
DEVICE_DESTROY(vkDestroyFence,VkFence,8)
DEVICE_CREATE(vkCreateSemaphore,VkSemaphoreCreateInfo,VkSemaphore,9,13)
DEVICE_DESTROY(vkDestroySemaphore,VkSemaphore,9)
DEVICE_CREATE(vkCreateCommandPool,VkCommandPoolCreateInfo,VkCommandPool,10,14)
DEVICE_DESTROY(vkDestroyCommandPool,VkCommandPool,10)
DEVICE_DESTROY(vkDestroyPipeline,VkPipeline,11)
VKAPI_ATTR VkResult VKAPI_CALL vkCreateGraphicsPipelines(VkDevice d,VkPipelineCache c,uint32_t n,const VkGraphicsPipelineCreateInfo *i,const VkAllocationCallbacks *a,VkPipeline *o) {
 if(fail(7)) { for(uint32_t j=0;j<n;++j) o[j]=VK_NULL_HANDLE; return VK_ERROR_OUT_OF_HOST_MEMORY; }
 int partial=fail(17); REAL(vkCreateGraphicsPipelines); VkResult r=real(d,c,n,i,a,o); for(uint32_t j=0;j<n;++j) if(o[j]) ++live[11]; if(partial && r==VK_SUCCESS) return VK_ERROR_OUT_OF_HOST_MEMORY; return r;
}
VKAPI_ATTR VkResult VKAPI_CALL vkBindBufferMemory(VkDevice d,VkBuffer b,VkDeviceMemory m,VkDeviceSize o) { if(fail(3)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkBindBufferMemory); return real(d,b,m,o); }
VKAPI_ATTR VkResult VKAPI_CALL vkMapMemory(VkDevice d,VkDeviceMemory m,VkDeviceSize o,VkDeviceSize n,VkMemoryMapFlags f,void **p) { if(fail(4)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkMapMemory); return real(d,m,o,n,f,p); }
VKAPI_ATTR VkResult VKAPI_CALL vkCreateXlibSurfaceKHR(VkInstance instance,const VkXlibSurfaceCreateInfoKHR *i,const VkAllocationCallbacks *a,VkSurfaceKHR *s) {
 if(fail(15)) return VK_ERROR_OUT_OF_HOST_MEMORY;
 REAL(vkCreateXlibSurfaceKHR); VkResult r=real(instance,i,a,s); if(r==VK_SUCCESS) { ++live[12]; display=i->dpy; window=i->window; char *title=NULL; if(XFetchName(display,window,&title) && title) { life_mode=getenv("GPU_PROBE_INTERACTIVE") && strstr(title,"Game of Life"); XFree(title); } } return r;
}
VKAPI_ATTR void VKAPI_CALL vkDestroySurfaceKHR(VkInstance i,VkSurfaceKHR s,const VkAllocationCallbacks *a) { REAL(vkDestroySurfaceKHR); assert(live[12]>0); --live[12]; real(i,s,a); }
VKAPI_ATTR VkResult VKAPI_CALL vkCreateDevice(VkPhysicalDevice p,const VkDeviceCreateInfo *i,const VkAllocationCallbacks *a,VkDevice *d) {
 REAL(vkCreateDevice); VkResult r=real(p,i,a,d); if(r==VK_SUCCESS) { ++live[13]; VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(p,&props); if(getenv("LANIUS_GPU_REQUIRE_HARDWARE")) assert(props.deviceType!=VK_PHYSICAL_DEVICE_TYPE_CPU); } return r;
}
VKAPI_ATTR void VKAPI_CALL vkDestroyDevice(VkDevice d,const VkAllocationCallbacks *a) { if(life_mode) { assert(life_phase==5 && life_uploads==2); } REAL(vkDestroyDevice); assert(live[13]>0); --live[13]; real(d,a); }
VKAPI_ATTR VkResult VKAPI_CALL vkCreateInstance(const VkInstanceCreateInfo *i,const VkAllocationCallbacks *a,VkInstance *o) {
 // Make validation mandatory in the observer-backed gates, independent of env.
 const char *layer="VK_LAYER_KHRONOS_validation"; const char *extensions[16]; assert(i->enabledExtensionCount<16);
 for(uint32_t n=0;n<i->enabledExtensionCount;++n) extensions[n]=i->ppEnabledExtensionNames[n];
 extensions[i->enabledExtensionCount]=VK_EXT_VALIDATION_FEATURES_EXTENSION_NAME;
 VkValidationFeatureEnableEXT sync=VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT;
 VkValidationFeaturesEXT validation={.sType=VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,.pNext=i->pNext,.enabledValidationFeatureCount=1,.pEnabledValidationFeatures=&sync};
 VkInstanceCreateInfo with=*i; with.pNext=&validation; with.enabledLayerCount=1; with.ppEnabledLayerNames=&layer; with.enabledExtensionCount=i->enabledExtensionCount+1; with.ppEnabledExtensionNames=extensions;
 REAL(vkCreateInstance); VkResult r=real(&with,a,o); if(r==VK_SUCCESS) ++live[14]; return r;
}
VKAPI_ATTR void VKAPI_CALL vkDestroyInstance(VkInstance i,const VkAllocationCallbacks *a) { REAL(vkDestroyInstance); assert(live[14]>0); --live[14]; real(i,a); }
VKAPI_ATTR VkResult VKAPI_CALL vkAcquireNextImageKHR(VkDevice d,VkSwapchainKHR s,uint64_t t,VkSemaphore sem,VkFence f,uint32_t *index) {
 if(fail(16)) return VK_ERROR_OUT_OF_DATE_KHR;
 REAL(vkAcquireNextImageKHR); return real(d,s,t,sem,f,index);
}
void probe_resize(int width,int height) {
 XResizeWindow(display,window,width,height); XSync(display,False);
 for(int i=0;i<100;++i) { XWindowAttributes a; assert(XGetWindowAttributes(display,window,&a)); if(a.width==width && a.height==height) return; usleep(5000); }
 assert(!"resize failed");
}
static void close_event(void) {
 XEvent e={0}; e.xclient.type=ClientMessage; e.xclient.window=window; e.xclient.message_type=XInternAtom(display,"WM_PROTOCOLS",False); e.xclient.format=32; e.xclient.data.l[0]=XInternAtom(display,"WM_DELETE_WINDOW",False); assert(XSendEvent(display,window,False,NoEventMask,&e)); XSync(display,False);
}
VKAPI_ATTR VkResult VKAPI_CALL vkWaitForFences(VkDevice d,uint32_t n,const VkFence *f,VkBool32 all,uint64_t timeout) {
 if(fail(19) || (n==1 && f[0]==last_present_fence && fail(20))) return VK_TIMEOUT;
 ++waits; if(hold) return VK_TIMEOUT; REAL(vkWaitForFences); return real(d,n,f,all,timeout);
}
VKAPI_ATTR VkResult VKAPI_CALL vkQueuePresentKHR(VkQueue q,const VkPresentInfoKHR *i) {
 const VkSwapchainPresentFenceInfoEXT *pf=i->pNext; assert(pf && pf->sType==VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_FENCE_INFO_EXT); last_present_fence=pf->pFences[0];
 if(fail(33)) return VK_ERROR_OUT_OF_HOST_MEMORY;
 REAL(vkQueuePresentKHR); VkResult r=real(q,i); ++frames;
 if(life_mode) { life_controls(); } else if(getenv("GPU_PROBE_INTERACTIVE")) { if(frames==2) probe_resize(517,293); if(frames==5) close_event(); }
 if(r==VK_SUCCESS && fail(21)) return VK_ERROR_OUT_OF_DATE_KHR;
 return r;
}
void probe_pixels(const unsigned char *bytes,int width,int height,int bgra) {
 int inside=0,outside=0;
 for(int y=0;y<height;++y) for(int x=0;x<width;++x) {
  double nx=2.0*(x+0.5)/width-1, ny=2.0*(y+0.5)/height-1;
  double red=(0.65-ny)/1.3, green=(1-red+nx/0.65)/2, blue=1-red-green;
  const unsigned char *p=bytes+4*(y*width+x); assert(p[3]==255);
  int r=p[bgra?2:0],g=p[1],b=p[bgra?0:2];
  if(red>0.04 && green>0.04 && blue>0.04) { assert(fabs(r-red*255)<2 && fabs(g-green*255)<2 && fabs(b-blue*255)<2); ++inside; }
  else if(red< -0.04 || green< -0.04 || blue< -0.04) { assert(abs(r-5)<=1 && abs(g-8)<=1 && abs(b-15)<=1); ++outside; }
 }
 assert(inside>width*height/10 && outside>width*height/3);
 const char *capture=getenv("GPU_PROBE_CAPTURE");
 if(capture && width==160 && height==120) {
  FILE *out=fopen(capture,"wb"); assert(out); fprintf(out,"P6\n%d %d\n255\n",width,height);
  for(int i=0;i<width*height;++i) { const unsigned char *p=bytes+4*i; unsigned char rgb[3]={p[bgra?2:0],p[1],p[bgra?0:2]}; assert(fwrite(rgb,1,3,out)==3); } assert(!fclose(out));
 }
}
int probe_thread(void *entry,void *argument) { pthread_t t; int r=pthread_create(&t,NULL,(void *(*)(void *))entry,argument); if(r) return r; return pthread_join(t,NULL); }

DEVICE_CREATE(vkCreateImage,VkImageCreateInfo,VkImage,16,22)
DEVICE_DESTROY(vkDestroyImage,VkImage,16)
DEVICE_CREATE(vkCreateSampler,VkSamplerCreateInfo,VkSampler,17,23)
DEVICE_DESTROY(vkDestroySampler,VkSampler,17)
DEVICE_CREATE(vkCreateDescriptorSetLayout,VkDescriptorSetLayoutCreateInfo,VkDescriptorSetLayout,18,24)
DEVICE_DESTROY(vkDestroyDescriptorSetLayout,VkDescriptorSetLayout,18)
DEVICE_CREATE(vkCreateDescriptorPool,VkDescriptorPoolCreateInfo,VkDescriptorPool,19,25)
DEVICE_DESTROY(vkDestroyDescriptorPool,VkDescriptorPool,19)
VKAPI_ATTR VkResult VKAPI_CALL vkBindImageMemory(VkDevice d,VkImage i,VkDeviceMemory m,VkDeviceSize o) { if(fail(32)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkBindImageMemory); return real(d,i,m,o); }
VKAPI_ATTR VkResult VKAPI_CALL vkAllocateDescriptorSets(VkDevice d,const VkDescriptorSetAllocateInfo *i,VkDescriptorSet *out) { if(fail(26)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkAllocateDescriptorSets); return real(d,i,out); }
VKAPI_ATTR VkResult VKAPI_CALL vkCreateComputePipelines(VkDevice d,VkPipelineCache c,uint32_t n,const VkComputePipelineCreateInfo *i,const VkAllocationCallbacks *a,VkPipeline *o) {
 if(fail(27)) { for(uint32_t j=0;j<n;++j) o[j]=VK_NULL_HANDLE; return VK_ERROR_OUT_OF_HOST_MEMORY; }
 int partial=fail(28); REAL(vkCreateComputePipelines); VkResult r=real(d,c,n,i,a,o); for(uint32_t j=0;j<n;++j) if(o[j]) ++live[11]; if(partial && r==VK_SUCCESS) return VK_ERROR_OUT_OF_HOST_MEMORY; return r;
}
VKAPI_ATTR VkResult VKAPI_CALL vkQueueSubmit(VkQueue q,uint32_t n,const VkSubmitInfo *i,VkFence f) { if(fail(29)) return VK_ERROR_OUT_OF_HOST_MEMORY; int unknown=fail(34); REAL(vkQueueSubmit); VkResult status=real(q,n,i,f); if(unknown && status==VK_SUCCESS) { fault=35; return VK_ERROR_UNKNOWN; } return status; }
VKAPI_ATTR VkResult VKAPI_CALL vkEndCommandBuffer(VkCommandBuffer b) { if(fail(30)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkEndCommandBuffer); return real(b); }
VKAPI_ATTR VkResult VKAPI_CALL vkGetFenceStatus(VkDevice d,VkFence f) { if(hold) return VK_NOT_READY; if(fail(31)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkGetFenceStatus); return real(d,f); }

VKAPI_ATTR VkResult VKAPI_CALL vkDeviceWaitIdle(VkDevice d) { if(fail(35)) return VK_ERROR_OUT_OF_HOST_MEMORY; REAL(vkDeviceWaitIdle); return real(d); }

// Test-only Life oracle: scatter neighbors from live cells, independent of the
// shader's per-destination gather. Known patterns additionally check the oracle.
static unsigned char life_cells[1024],life_initial[1024];
static int life_width,life_height,life_generation,life_case;
static void life_set(int x,int y) { life_cells[(y%life_height)*life_width+x%life_width]=1; }
void probe_life_seed(unsigned char *bytes,int width,int height,int scenario) {
 assert(width>0 && height>0 && width*height<=1024);
 life_width=width; life_height=height; life_generation=0; life_case=scenario;
 for(int i=0;i<width*height;++i) life_cells[i]=0;
 if(scenario==0) { unsigned state=0x31415926u; for(int i=0;i<width*height;++i) { state^=state<<13; state^=state>>17; state^=state<<5; life_cells[i]=state%100<37; } }
 if(scenario==1) { life_set(2,2); life_set(3,2); life_set(2,3); life_set(3,3); }
 if(scenario==2) { life_set(2,3); life_set(3,3); life_set(4,3); }
 if(scenario==3) { int x=width-2,y=height-2; life_set(x+1,y); life_set(x+2,y+1); life_set(x,y+2); life_set(x+1,y+2); life_set(x+2,y+2); }
 if(scenario==4) for(int i=0;i<width*height;++i) life_cells[i]=1;
 if(scenario==6) life_set(0,0);
 for(int i=0;i<width*height;++i) { life_initial[i]=life_cells[i]; bytes[i*4]=life_cells[i]?255:0; bytes[i*4+1]=bytes[i*4+2]=0; bytes[i*4+3]=255; }
}
static void life_tick(void) {
 unsigned char count[1024]={0}; const int dx[8]={-1,0,1,-1,1,-1,0,1},dy[8]={-1,-1,-1,0,0,1,1,1};
 for(int y=0;y<life_height;++y) for(int x=0;x<life_width;++x) if(life_cells[y*life_width+x]) {
  for(int j=0;j<8;++j) { int nx=x+dx[j],ny=y+dy[j]; if(nx<0) nx+=life_width; if(nx==life_width) nx=0; if(ny<0) ny+=life_height; if(ny==life_height) ny=0; ++count[ny*life_width+nx]; }
 }
 for(int i=0;i<life_width*life_height;++i) { switch(count[i]) { case 3: life_cells[i]=1; break; case 2: break; default: life_cells[i]=0; } }
 ++life_generation;
}
void probe_life_compare(const unsigned char *bytes,int generation) {
 assert(generation>life_generation); while(life_generation<generation) life_tick();
 for(int y=0;y<life_height;++y) for(int x=0;x<life_width;++x) {
  int i=y*life_width+x; const unsigned char *p=bytes+i*4;
  if(p[0]!=(life_cells[i]?255:0) || p[1]!=0 || p[2]!=0 || p[3]!=255) { fprintf(stderr,"Life case %d generation %d at %d,%d: got %u,%u,%u,%u, expected alive=%u\n",life_case,generation,x,y,p[0],p[1],p[2],p[3],life_cells[i]); abort(); }
  if(life_case==1 || (life_case==2 && generation%2==0)) assert(life_cells[i]==life_initial[i]);
  if(life_case==2 && generation%2==1) assert(life_cells[i]==(x==3 && y>=2 && y<=4));
  if(life_case==3 && generation%4==0) { int dx=(generation/4)%life_width,dy=(generation/4)%life_height; assert(life_cells[i]==life_initial[((y-dy+life_height)%life_height)*life_width+(x-dx+life_width)%life_width]); }
 }
}

VKAPI_ATTR void VKAPI_CALL vkCmdDispatch(VkCommandBuffer c,uint32_t x,uint32_t y,uint32_t z) { ++life_dispatches; REAL(vkCmdDispatch); real(c,x,y,z); }
VKAPI_ATTR void VKAPI_CALL vkCmdCopyBufferToImage(VkCommandBuffer c,VkBuffer b,VkImage i,VkImageLayout l,uint32_t n,const VkBufferImageCopy *r) { ++life_uploads; REAL(vkCmdCopyBufferToImage); real(c,b,i,l,n,r); }
static void life_key(KeySym key) {
 XEvent e={0}; e.xkey.type=KeyPress; e.xkey.display=display; e.xkey.window=window; e.xkey.root=DefaultRootWindow(display); e.xkey.keycode=XKeysymToKeycode(display,key); e.xkey.same_screen=True;
 assert(e.xkey.keycode); assert(XSendEvent(display,window,False,KeyPressMask,&e)); e.xkey.type=KeyRelease; assert(XSendEvent(display,window,False,KeyReleaseMask,&e)); XSync(display,False);
}
static void life_controls(void) {
 if(frames==2) { life_saved_dispatches=life_dispatches; life_key(XK_space); life_phase=1; }
 if(frames==4) { assert(life_phase==1 && life_dispatches==life_saved_dispatches); life_key(XK_Right); life_phase=2; }
 if(frames==6) { assert(life_phase==2 && life_dispatches==life_saved_dispatches+1); life_key(XK_r); life_phase=3; }
 if(frames==8) { assert(life_phase==3 && life_dispatches==life_saved_dispatches+1 && life_uploads==2); life_saved_dispatches=life_dispatches; life_key(XK_space); life_phase=4; }
 if(frames>8 && life_phase==4 && life_dispatches>life_saved_dispatches) { probe_resize(517,293); life_phase=5; }
 else if(frames>8 && life_phase==5) { close_event(); }
 assert(frames<400);
}
