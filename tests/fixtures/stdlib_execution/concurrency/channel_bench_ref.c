// C pthread reference for channel_bench.lani: the same ping-pong and fan-in
// over a bounded queue guarded by one pthread mutex with two condition
// variables (the textbook pthread channel).
//   cc -O2 -pthread channel_bench_ref.c -o channel_bench_ref
//   channel_bench_ref pingpong ROUNDS | fanin PRODUCERS ITEMS
// Prints "ms MS check VALUE" like channel_bench.
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t readable, writable;
    int64_t *slots;
    long capacity, head, length, senders;
} queue;

static void queue_init(queue *q, long capacity, long senders) {
    pthread_mutex_init(&q->lock, NULL);
    pthread_cond_init(&q->readable, NULL);
    pthread_cond_init(&q->writable, NULL);
    q->slots = calloc(capacity, sizeof(int64_t));
    q->capacity = capacity; q->head = 0; q->length = 0; q->senders = senders;
}
static void queue_send(queue *q, int64_t value) {
    pthread_mutex_lock(&q->lock);
    while (q->length == q->capacity) pthread_cond_wait(&q->writable, &q->lock);
    q->slots[(q->head + q->length) % q->capacity] = value;
    q->length++;
    pthread_cond_signal(&q->readable);
    pthread_mutex_unlock(&q->lock);
}
// 0 when every sender has closed and the queue is empty.
static int queue_recv(queue *q, int64_t *value) {
    pthread_mutex_lock(&q->lock);
    while (q->length == 0 && q->senders > 0) pthread_cond_wait(&q->readable, &q->lock);
    if (q->length == 0) { pthread_mutex_unlock(&q->lock); return 0; }
    *value = q->slots[q->head];
    q->head = (q->head + 1) % q->capacity;
    q->length--;
    pthread_cond_signal(&q->writable);
    pthread_mutex_unlock(&q->lock);
    return 1;
}
static void queue_close(queue *q) {
    pthread_mutex_lock(&q->lock);
    q->senders--;
    pthread_cond_broadcast(&q->readable);
    pthread_mutex_unlock(&q->lock);
}

static queue there, back, funnel;
static long rounds, items;

static void *echo(void *arg) {
    for (long i = 0; i < rounds; i++) { int64_t v; queue_recv(&there, &v); queue_send(&back, v + 1); }
    return arg;
}
static void *feed(void *arg) {
    for (long i = 0; i < items; i++) queue_send(&funnel, i);
    queue_close(&funnel);
    return arg;
}
static int64_t now_us(void) {
    struct timespec t; clock_gettime(CLOCK_REALTIME, &t);
    return (int64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: channel_bench_ref pingpong N | fanin P ITEMS\n"); return 2; }
    int64_t check = 0, start;
    if (strcmp(argv[1], "pingpong") == 0) {
        rounds = atol(argv[2]);
        queue_init(&there, 2, 1); queue_init(&back, 2, 1);
        start = now_us();
        pthread_t t; pthread_create(&t, NULL, echo, NULL);
        int64_t v = 0;
        for (long i = 0; i < rounds; i++) { queue_send(&there, v); queue_recv(&back, &v); }
        pthread_join(t, NULL); check = v;
    } else {
        long producers = atol(argv[2]); items = atol(argv[3]);
        queue_init(&funnel, 1024, producers);
        start = now_us();
        pthread_t *t = calloc(producers, sizeof(pthread_t));
        for (long w = 0; w < producers; w++) pthread_create(&t[w], NULL, feed, NULL);
        int64_t v;
        while (queue_recv(&funnel, &v)) check += v;
        for (long w = 0; w < producers; w++) pthread_join(t[w], NULL);
    }
    int64_t elapsed = now_us() - start;
    printf("ms %ld.%ld check %ld\n", (long)(elapsed / 1000), (long)((elapsed % 1000) / 100), (long)(check % 1000000007));
    return 0;
}
