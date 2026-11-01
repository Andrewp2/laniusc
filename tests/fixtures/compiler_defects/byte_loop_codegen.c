#include <stdlib.h>
#include <string.h>
static unsigned count_nl(const unsigned char *d, int base, int n) { unsigned c = 0; for (int i = 0; i < n; i++) if (d[base + i] == 10) c++; return c; }
int main(void) { int n = 16000000; unsigned char *v = malloc(n); memset(v, 1, n); unsigned t = 0; for (int k = 0; k < 10; k++) t += count_nl(v, 0, n); return t & 1; }
