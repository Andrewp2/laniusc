#include <stdio.h>

static int cell_score(int x, int y, int salt) {
    int distance = x > y ? x - y : y - x;
    int mixed = (x * 17 + y * 31 + salt * 13) % 97;
    return distance + mixed;
}

static int grid_checksum(int rows, int salt) {
    int total = 0;
    for (int y = 0; y < rows; ++y) {
        for (int x = 0; x < 251; ++x) {
            total += cell_score(x, y, salt);
            if (total > 100000) total -= 200001;
            if (total < -100000) total += 200001;
        }
    }
    return total;
}

int main(int argc, char **argv) {
    (void)argv;
    printf("%d\n", grid_checksum(32000 + argc, argc));
    return 0;
}
