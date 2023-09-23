#include <stdio.h>

void urlencode(char *dst, const char *src) {
    char c;
    while (c = *src++) {
        if (c == ' ') {
            *dst++ = '+';
        } else if ((c < '0' && c != '-' && c != '.') ||
                   (c < 'A' && c > '9') ||
                   (c > 'Z' && c < 'a' && c != '_') ||
                   (c > 'z')) {
            *dst++ = '%';
            *dst++ = "0123456789ABCDEF"[c >> 4];
            *dst++ = "0123456789ABCDEF"[c & 15];
        } else {
            *dst++ = c;
        }
    }
    *dst = '\0';
}

int main() {
    char ch = 'A';
    char hex[3];
    char encoded[9];  // 3 * sizeof(hex) + 1

    sprintf(hex, "%02X", ch);
    urlencode(encoded, hex);

    printf("URL Encoded string = %s\n", encoded);

    return 0;
}
