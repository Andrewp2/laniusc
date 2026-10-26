/* Test instrumentation only. TLS, records and successful I/O use libssl.
 * A forced WANT/fatal is a separately labelled negative/rare-state control. */
#define _GNU_SOURCE
#include "observer.h"
#include <assert.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OWNERS 128
struct context_owner { SSL_CTX *pointer; int refs; };
struct session_owner {
    SSL *pointer;
    int live, fault, forced, last, last_forced, strict_reads;
    int64_t stats[11];
    const void *read_buffer, *write_buffer;
    size_t read_length, write_length;
    size_t *read_count, *write_count;
    unsigned char *write_copy;
};
static struct context_owner contexts[OWNERS];
static struct session_owner sessions[OWNERS];
static int session_count, inside_session, up_ref_failure, next_fault;
static int64_t global[7];

static void *resolve(const char *name) {
    void *function = dlsym(RTLD_NEXT, name);
    if (!function) { fprintf(stderr,"duplex observer missing %s\n",name); _Exit(98); }
    return function;
}
static struct context_owner *context(SSL_CTX *pointer) {
    for (int i=0;i<OWNERS;i++) if (contexts[i].pointer==pointer) return &contexts[i];
    assert(!"unknown SSL_CTX owner"); return NULL;
}
static struct session_owner *session(const SSL *pointer) {
    for (int i=0;i<session_count;i++) if (sessions[i].pointer==pointer && sessions[i].live) return &sessions[i];
    assert(!"unknown/live SSL owner"); return NULL;
}
static struct session_owner *ordinal(int index) {
    assert(index>=0 && index<session_count); return &sessions[index];
}
SSL_CTX *SSL_CTX_new(const SSL_METHOD *method) {
    SSL_CTX *(*native)(const SSL_METHOD *)=resolve("SSL_CTX_new");
    SSL_CTX *result=native(method);
    if (result) {
        int i=0; while (i<OWNERS && contexts[i].refs) i++; assert(i<OWNERS);
        contexts[i]=(struct context_owner){result,1}; global[0]++;
    }
    return result;
}
int SSL_CTX_up_ref(SSL_CTX *pointer) {
    int (*native)(SSL_CTX *)=resolve("SSL_CTX_up_ref");
    if (inside_session) return native(pointer);
    global[4]++;
    if (up_ref_failure) { up_ref_failure=0; global[5]++; ERR_raise(ERR_LIB_USER,901); return 0; }
    int result=native(pointer);
    if (result==1) { context(pointer)->refs++; global[0]++; }
    return result;
}
void SSL_CTX_free(SSL_CTX *pointer) {
    void (*native)(SSL_CTX *)=resolve("SSL_CTX_free");
    if (pointer && !inside_session) {
        struct context_owner *owner=context(pointer);
        if (owner->refs<=0) { global[2]++; return; }
        owner->refs--; global[0]--;
    }
    native(pointer);
}
SSL *SSL_new(SSL_CTX *pointer) {
    SSL *(*native)(SSL_CTX *)=resolve("SSL_new");
    inside_session++; SSL *result=native(pointer); inside_session--;
    if (result) {
        assert(session_count<OWNERS);
        sessions[session_count++]=(struct session_owner){.pointer=result,.live=1,.fault=next_fault}; next_fault=0; global[1]++;
    }
    return result;
}
void SSL_free(SSL *pointer) {
    void (*native)(SSL *)=resolve("SSL_free");
    if (pointer) {
        struct session_owner *owner=session(pointer);
        owner->live=0; global[1]--; free(owner->write_copy); owner->write_copy=NULL;
    }
    inside_session++; native(pointer); inside_session--;
}
static int forced(struct session_owner *owner,int kind) {
    owner->last_forced=0;
    int fault=owner->fault;
    int applies=(kind==1 && (fault==2 || fault==3 || fault==9)) ||
        (kind==2 && (fault==1 || fault==4)) || (kind==3 && fault>=5 && fault<=7) || (kind==4 && fault==8);
    if (!applies) return 0;
    owner->fault=0; owner->stats[5]++; owner->last_forced=1;
    owner->forced=(fault==1 || fault==5 || fault==9) ? SSL_ERROR_WANT_READ :
        ((fault==2 || fault==6) ? SSL_ERROR_WANT_WRITE : SSL_ERROR_SSL);
    if (owner->forced==SSL_ERROR_SSL) ERR_raise(ERR_LIB_USER,910+fault);
    return 1;
}
int SSL_do_handshake(SSL *pointer) {
    int (*native)(SSL *)=resolve("SSL_do_handshake"); struct session_owner *owner=session(pointer);
    global[3]++; owner->stats[3]++; owner->last=4;
    return forced(owner,4) ? -1 : native(pointer);
}
int SSL_read_ex(SSL *pointer,void *buffer,size_t length,size_t *count) {
    int (*native)(SSL *,void *,size_t,size_t *)=resolve("SSL_read_ex");
    struct session_owner *owner=session(pointer); global[3]++; owner->stats[0]++; owner->last=1;
    if (owner->read_buffer && owner->strict_reads) {
        assert(buffer==owner->read_buffer && length==owner->read_length && count==owner->read_count); owner->stats[7]++;
    } else { owner->read_buffer=buffer; owner->read_length=length; owner->read_count=count; }
    if (owner->write_count) { assert(count!=owner->write_count); owner->stats[8]++; }
    if (forced(owner,1)) { assert(*count==0); return 0; }
    int result=native(pointer,buffer,length,count);
    if (result==1) { assert(*count>0 && *count<=length); owner->read_buffer=NULL; }
    return result;
}
int SSL_write_ex(SSL *pointer,const void *buffer,size_t length,size_t *count) {
    int (*native)(SSL *,const void *,size_t,size_t *)=resolve("SSL_write_ex");
    struct session_owner *owner=session(pointer); global[3]++; owner->stats[1]++; owner->last=2;
    if (owner->write_buffer) {
        assert(buffer==owner->write_buffer && length==owner->write_length && count==owner->write_count);
        assert(memcmp(buffer,owner->write_copy,length)==0); owner->stats[6]++;
    } else {
        owner->write_buffer=buffer; owner->write_length=length; owner->write_count=count;
        owner->write_copy=malloc(length); assert(owner->write_copy); memcpy(owner->write_copy,buffer,length);
    }
    if (owner->read_count) { assert(count!=owner->read_count); owner->stats[8]++; }
    if (forced(owner,2)) { assert(*count==0); return 0; }
    int result=native(pointer,buffer,length,count);
    if (result==1) {
        assert(*count>0 && *count<=length); owner->write_buffer=NULL;
        free(owner->write_copy); owner->write_copy=NULL;
    }
    return result;
}
int SSL_shutdown(SSL *pointer) {
    int (*native)(SSL *)=resolve("SSL_shutdown"); struct session_owner *owner=session(pointer);
    global[3]++; global[6]++; owner->stats[2]++; owner->last=3;
    return forced(owner,3) ? -1 : native(pointer);
}
int SSL_get_error(const SSL *pointer,int result) {
    int (*native)(const SSL *,int)=resolve("SSL_get_error"); struct session_owner *owner=session(pointer);
    owner->stats[4]++; int error;
    if (owner->forced) { error=owner->forced; owner->forced=0; } else { error=native(pointer,result); }
    if (owner->last==2 && error==SSL_ERROR_WANT_WRITE && !owner->last_forced) owner->stats[10]++;
    if (owner->last==1 && error==SSL_ERROR_ZERO_RETURN) owner->read_buffer=NULL;
    return error;
}
void duplex_test_arm(int index,int fault) {
    struct session_owner *owner=ordinal(index); assert(owner->live && !owner->fault && fault>=1 && fault<=9); owner->fault=fault;
}
void duplex_test_arm_next(int fault) { assert(!next_fault && fault>=1 && fault<=9); next_fault=fault; }
void duplex_test_fail_up_ref(void) { assert(!up_ref_failure); up_ref_failure=1; }
void duplex_test_forget_read(int index) { ordinal(index)->read_buffer=NULL; }
void duplex_test_strict_reads(int index,int enabled) { assert(enabled==0 || enabled==1); ordinal(index)->strict_reads=enabled; }
int duplex_test_pending(int index) { struct session_owner *owner=ordinal(index); assert(owner->live); return SSL_pending(owner->pointer); }
int duplex_test_fd_open(int fd) { return fcntl(fd,F_GETFD)>=0; }
int64_t duplex_test_stat(int index,int field) {
    if (index<0) { assert(field>=0 && field<7); return global[field]; }
    struct session_owner *owner=ordinal(index); assert(field>=0 && field<11);
    return field==9 ? owner->live : owner->stats[field];
}
