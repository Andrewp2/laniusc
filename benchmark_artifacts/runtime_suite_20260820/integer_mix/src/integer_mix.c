#include <stdio.h>

static int integer_mix(int iterations, int salt) {
    int total = 0;
    for (int index = 0; index < iterations; ++index) {
        int lane = (index + salt) % 1021;
        if (lane % 4 < 2) total += lane; else total -= lane;
        if (total > 100000) total -= 200001;
        if (total < -100000) total += 200001;
    }
    return total;
}

int main(int argc, char **argv) {
    (void)argv;
    printf("%d\n", integer_mix(25000000 + argc, argc));
    return 0;
}
