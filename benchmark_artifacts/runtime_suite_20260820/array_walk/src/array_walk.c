#include <stdio.h>

static int array_walk(int rounds, int salt) {
    int values[64] = {3, 20, 37, 54, 71, 88, 105, 122, 139, 156, 173, 190, 207, 224, 241, 258, 275, 292, 309, 326, 343, 360, 377, 394, 411, 428, 445, 462, 479, 496, 513, 530, 547, 564, 581, 598, 615, 632, 649, 666, 683, 700, 717, 734, 751, 768, 785, 802, 819, 836, 853, 870, 887, 904, 921, 938, 955, 972, 989, 1006, 1023, 1040, 1057, 1074};
    int checksum = 0;
    for (int round = 0; round < rounds; ++round) {
        for (int index = 0; index < 64; ++index) {
            int value = (values[index] * 33 + round + index + salt) % 10007;
            values[index] = value;
            checksum = (checksum + value) % 1000003;
        }
    }
    return checksum;
}

int main(int argc, char **argv) {
    (void)argv;
    printf("%d\n", array_walk(100000 + argc, argc));
    return 0;
}
