// Test-only native oracle and reached-failure injection. No production shim.
#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#undef XDestroyImage
#define OFFSET(t, f, n) _Static_assert(offsetof(t, f) == n, #t "." #f)
_Static_assert(sizeof(void *) == 8 && sizeof(long) == 8, "LP64");
_Static_assert(sizeof(XEvent) == 192 && sizeof(XSizeHints) == 80, "native records");
OFFSET(Visual, class, 16); OFFSET(Visual, red_mask, 24); OFFSET(Visual, green_mask, 32); OFFSET(Visual, blue_mask, 40);
OFFSET(XImage, data, 16); OFFSET(XImage, byte_order, 24); OFFSET(XImage, bytes_per_line, 44); OFFSET(XImage, bits_per_pixel, 48);
OFFSET(XImage, red_mask, 56); OFFSET(XImage, green_mask, 64); OFFSET(XImage, blue_mask, 72);
OFFSET(XAnyEvent, window, 32); OFFSET(XConfigureEvent, window, 40); OFFSET(XConfigureEvent, width, 56); OFFSET(XConfigureEvent, height, 60);
OFFSET(XClientMessageEvent, message_type, 40); OFFSET(XClientMessageEvent, format, 48); OFFSET(XClientMessageEvent, data, 56);
OFFSET(XKeyEvent, state, 80); OFFSET(XKeyEvent, keycode, 84);
OFFSET(XMotionEvent, x, 64); OFFSET(XMotionEvent, y, 68); OFFSET(XMotionEvent, state, 80);
OFFSET(XButtonEvent, x, 64); OFFSET(XButtonEvent, y, 68); OFFSET(XButtonEvent, button, 84);
OFFSET(XSizeHints, min_width, 24); OFFSET(XSizeHints, min_height, 28); OFFSET(XSizeHints, max_width, 32); OFFSET(XSizeHints, max_height, 36);
_Static_assert((KeyPressMask|KeyReleaseMask|ButtonPressMask|ButtonReleaseMask|PointerMotionMask|ExposureMask|StructureNotifyMask|FocusChangeMask)==2261071, "event selection");
_Static_assert(sizeof(struct pollfd)==8 && offsetof(struct pollfd, revents)==6, "poll record");
#define REAL(name) __typeof__(&name) real = (__typeof__(&name))dlsym(RTLD_NEXT, #name); assert(real)
static int fault, hits, displays, windows, gcs, images, freed, frames;
static Display *current;
static XImage *tracked[32];
static void *failed_payload;
static int fail(int stage) { if(fault!=stage) return 0; fault=0; ++hits; return 1; }
void probe_fault(int stage) { assert(!fault); fault=stage; }
int probe_hits(void) { assert(!fault); return hits; }
int probe_frames(void) { return frames; }
int probe_freed(void) { return freed; }
void probe_empty(void) { assert(!fault && !displays && !windows && !gcs && !images && !failed_payload); }
// Observe the malloc-owned payload on XCreateImage's null-return path.
extern void __libc_free(void *);
void free(void *p) { if(p && p==failed_payload) { failed_payload=NULL; ++freed; } __libc_free(p); }
Display *XOpenDisplay(const char *name) { if(fail(1)) return NULL; REAL(XOpenDisplay); Display *d=real(name); if(d) { ++displays; current=d; } return d; }
int XCloseDisplay(Display *d) { REAL(XCloseDisplay); assert(displays>0); --displays; return real(d); }
int XDefaultDepth(Display *d,int s) { if(fail(2)) return 16; REAL(XDefaultDepth); return real(d,s); }
Atom XInternAtom(Display *d,const char *n,Bool only) { if(fail(3)) return None; REAL(XInternAtom); return real(d,n,only); }
XImage *XCreateImage(Display *d,Visual *v,unsigned depth,int format,int offset,char *data,unsigned w,unsigned h,int pad,int pitch) {
    if(fail(4)) { assert(!failed_payload); failed_payload=data; return NULL; }
    REAL(XCreateImage); XImage *im=real(d,v,depth,format,offset,data,w,h,pad,pitch);
    if(im) { int i=0; while(i<32 && tracked[i]) ++i; assert(i<32); tracked[i]=im; ++images; if(fail(5)) im->byte_order=MSBFirst; } return im;
}
int XDestroyImage(XImage *im) { REAL(XDestroyImage); for(int i=0;i<32;++i) if(tracked[i]==im) { tracked[i]=NULL; --images; break; } return real(im); }
Window XCreateSimpleWindow(Display *d,Window p,int x,int y,unsigned w,unsigned h,unsigned border,unsigned long bp,unsigned long bg) {
    if(fail(6)) { return None; } REAL(XCreateSimpleWindow); Window out=real(d,p,x,y,w,h,border,bp,bg); if(out) ++windows; return out;
}
int XDestroyWindow(Display *d,Window w) { REAL(XDestroyWindow); assert(windows>0); --windows; return real(d,w); }
GC XCreateGC(Display *d,Drawable w,unsigned long mask,XGCValues *values) { if(fail(7)) return NULL; REAL(XCreateGC); GC gc=real(d,w,mask,values); if(gc) ++gcs; return gc; }
int XFreeGC(Display *d,GC gc) { REAL(XFreeGC); assert(gcs>0); --gcs; return real(d,gc); }
Status XSetWMProtocols(Display *d,Window w,Atom *a,int n) { if(fail(8)) return 0; REAL(XSetWMProtocols); return real(d,w,a,n); }
Status XGetGeometry(Display *d,Drawable w,Window *r,int *x,int *y,unsigned *width,unsigned *height,unsigned *b,unsigned *depth) {
    if(fail(9)) { return 0; } REAL(XGetGeometry); return real(d,w,r,x,y,width,height,b,depth);
}
int poll(struct pollfd *fds,nfds_t n,int timeout) {
    if(fail(10)) { errno=EIO; return -1; }
    if(fail(11)) { assert(n==1); fds[0].revents=POLLHUP; return 1; }
    REAL(poll); return real(fds,n,timeout);
}
static void send_close(Display *d,Window w) {
    XEvent e={0}; e.xclient.type=ClientMessage; e.xclient.window=w; e.xclient.message_type=XInternAtom(d,"WM_PROTOCOLS",False);
    e.xclient.format=32; e.xclient.data.l[0]=(long)XInternAtom(d,"WM_DELETE_WINDOW",False);
    assert(XSendEvent(d,w,False,NoEventMask,&e)); XSync(d,False);
}
int XPutImage(Display *d,Drawable w,GC gc,XImage *im,int sx,int sy,int dx,int dy,unsigned width,unsigned height) {
    REAL(XPutImage); int result=real(d,w,gc,im,sx,sy,dx,dy,width,height); ++frames;
    if(frames==2 && getenv("WINDOW_PROBE_CLOSE")) send_close(d,w);
    return result;
}
void probe_drain(void) { XSync(current,True); }
void probe_metadata(unsigned long w,int resizable) {
    int viewable=0;
    for(int i=0;i<100;++i) { XWindowAttributes a; assert(XGetWindowAttributes(current,w,&a)); if(a.map_state==IsViewable) { viewable=1; break; } usleep(5000); }
    assert(viewable);
    XSizeHints hints={0}; long flags=0; assert(XGetWMNormalHints(current,w,&hints,&flags));
    assert((hints.flags&(PMinSize|PMaxSize))==(PMinSize|PMaxSize));
    assert(hints.min_width==(resizable?1:8) && hints.min_height==(resizable?1:8));
    assert(hints.max_width==(resizable?16384:8) && hints.max_height==(resizable?16384:8));
    Atom *protocols=NULL; int n=0; assert(XGetWMProtocols(current,w,&protocols,&n) && n==1);
    assert(protocols[0]==XInternAtom(current,"WM_DELETE_WINDOW",False)); XFree(protocols);
    Atom type; int format; unsigned long count,remaining; unsigned char *name=NULL;
    assert(XGetWindowProperty(current,w,XInternAtom(current,"_NET_WM_NAME",False),0,4096,False,AnyPropertyType,&type,&format,&count,&remaining,&name)==Success);
    assert(type==XInternAtom(current,"UTF8_STRING",False) && format==8 && count==6 && !remaining);
    assert(memcmp(name,"caf\xc3\xa9!",6)==0); XFree(name);
}
void probe_resize(unsigned long w,int width,int height) {
    XResizeWindow(current,w,width,height); XSync(current,False);
    for(int i=0;i<100;++i) { XWindowAttributes a; assert(XGetWindowAttributes(current,w,&a)); if(a.width==width && a.height==height) return; usleep(5000); }
    assert(!"window resize did not complete");
}
void probe_pixels(unsigned long w,int width,int height) {
    XSync(current,False); XImage *im=XGetImage(current,w,0,0,width,height,AllPlanes,ZPixmap); assert(im);
    for(int y=0;y<height;++y) for(int x=0;x<width;++x) {
        unsigned i=(unsigned)((y*8/height)*8+x*8/width+1);
        unsigned long expected=(((i*17)%256)<<16)|(((i*7)%256)<<8)|((i*3)%256);
        assert((XGetPixel(im,x,y)&0xffffff)==expected);
    }
    XDestroyImage(im);
}
void probe_events(unsigned long one,unsigned long two) {
    XSync(current,True); XEvent e[12]={0};
    e[0].xexpose=(XExposeEvent){.type=Expose,.display=current,.window=one};
    e[1].xconfigure=(XConfigureEvent){.type=ConfigureNotify,.display=current,.event=two,.window=one,.width=27,.height=19};
    unsigned code=XKeysymToKeycode(current,XK_Escape); assert(code);
    e[2].xkey=(XKeyEvent){.type=KeyPress,.display=current,.window=two,.keycode=code,.state=ShiftMask};
    e[3]=e[2]; e[3].type=KeyRelease;
    e[4].xmotion=(XMotionEvent){.type=MotionNotify,.display=current,.window=one,.x=-4,.y=23,.state=Button1Mask};
    e[5].xbutton=(XButtonEvent){.type=ButtonPress,.display=current,.window=two,.button=3,.x=7,.y=-2};
    e[6]=e[5]; e[6].type=ButtonRelease;
    e[7].xfocus=(XFocusChangeEvent){.type=FocusIn,.display=current,.window=one};
    e[8]=e[7]; e[8].type=FocusOut;
    e[9].xclient=(XClientMessageEvent){.type=ClientMessage,.display=current,.window=two,.message_type=XInternAtom(current,"WM_PROTOCOLS",False),.format=8};
    e[9].xclient.data.l[0]=(long)XInternAtom(current,"WM_DELETE_WINDOW",False);
    e[10]=e[9]; e[10].xclient.format=32; e[10].xclient.message_type=None;
    e[11].type=MappingNotify;
    for(int i=11;i>=0;--i) XPutBackEvent(current,&e[i]);
}
void probe_close(unsigned long w) { probe_drain(); send_close(current,w); }
int probe_thread(void *entry,void *argument) { pthread_t t; int rc=pthread_create(&t,NULL,(void *(*)(void *))entry,argument); if(rc) return rc; return pthread_join(t,NULL); }
