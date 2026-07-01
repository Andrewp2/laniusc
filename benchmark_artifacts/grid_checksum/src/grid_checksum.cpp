#include <cstdio>

static int cell_score(int x, int y, int seed) {
    int distance = x > y ? x - y : y - x;
    int mixed = (x * 17 + y * 31 + seed * 13) % 97;
    if (mixed < 0) {
        return distance - mixed;
    }
    return distance + mixed;
}

static int checksum(int width, int height, int seed) {
    int total = 0;
    int y = 0;
    while (y < height) {
        int x = 0;
        while (x < width) {
            total += cell_score(x, y, seed);
            x += 1;
        }
        y += 1;
    }
    return total;
}

int main(void) {
    std::printf("%d\n", checksum(32, 24, 19));
    return 0;
}
