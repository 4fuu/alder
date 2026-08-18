/* Portable verifier for the Alder compiler-source inventory v1. */
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Sha256 {
    uint32_t state[8];
    uint64_t length;
    unsigned char block[64];
    size_t used;
};

struct InventoryEntry {
    const unsigned char *path;
    size_t path_length;
    uint64_t length;
    unsigned char digest[32];
};

static uint32_t rotr32(uint32_t value, unsigned int count) {
    return (value >> count) | (value << (32U - count));
}

static void sha256_compress(struct Sha256 *hash, const unsigned char block[64]) {
    static const uint32_t constants[64] = {
        UINT32_C(0x428a2f98), UINT32_C(0x71374491), UINT32_C(0xb5c0fbcf), UINT32_C(0xe9b5dba5),
        UINT32_C(0x3956c25b), UINT32_C(0x59f111f1), UINT32_C(0x923f82a4), UINT32_C(0xab1c5ed5),
        UINT32_C(0xd807aa98), UINT32_C(0x12835b01), UINT32_C(0x243185be), UINT32_C(0x550c7dc3),
        UINT32_C(0x72be5d74), UINT32_C(0x80deb1fe), UINT32_C(0x9bdc06a7), UINT32_C(0xc19bf174),
        UINT32_C(0xe49b69c1), UINT32_C(0xefbe4786), UINT32_C(0x0fc19dc6), UINT32_C(0x240ca1cc),
        UINT32_C(0x2de92c6f), UINT32_C(0x4a7484aa), UINT32_C(0x5cb0a9dc), UINT32_C(0x76f988da),
        UINT32_C(0x983e5152), UINT32_C(0xa831c66d), UINT32_C(0xb00327c8), UINT32_C(0xbf597fc7),
        UINT32_C(0xc6e00bf3), UINT32_C(0xd5a79147), UINT32_C(0x06ca6351), UINT32_C(0x14292967),
        UINT32_C(0x27b70a85), UINT32_C(0x2e1b2138), UINT32_C(0x4d2c6dfc), UINT32_C(0x53380d13),
        UINT32_C(0x650a7354), UINT32_C(0x766a0abb), UINT32_C(0x81c2c92e), UINT32_C(0x92722c85),
        UINT32_C(0xa2bfe8a1), UINT32_C(0xa81a664b), UINT32_C(0xc24b8b70), UINT32_C(0xc76c51a3),
        UINT32_C(0xd192e819), UINT32_C(0xd6990624), UINT32_C(0xf40e3585), UINT32_C(0x106aa070),
        UINT32_C(0x19a4c116), UINT32_C(0x1e376c08), UINT32_C(0x2748774c), UINT32_C(0x34b0bcb5),
        UINT32_C(0x391c0cb3), UINT32_C(0x4ed8aa4a), UINT32_C(0x5b9cca4f), UINT32_C(0x682e6ff3),
        UINT32_C(0x748f82ee), UINT32_C(0x78a5636f), UINT32_C(0x84c87814), UINT32_C(0x8cc70208),
        UINT32_C(0x90befffa), UINT32_C(0xa4506ceb), UINT32_C(0xbef9a3f7), UINT32_C(0xc67178f2)
    };
    uint32_t words[64];
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;
    size_t i;
    for (i = 0; i < (size_t)16; i++) {
        size_t at = i * (size_t)4;
        words[i] = ((uint32_t)block[at] << 24U) |
                   ((uint32_t)block[at + (size_t)1] << 16U) |
                   ((uint32_t)block[at + (size_t)2] << 8U) |
                   (uint32_t)block[at + (size_t)3];
    }
    for (i = 16; i < (size_t)64; i++) {
        uint32_t x = words[i - (size_t)15];
        uint32_t y = words[i - (size_t)2];
        uint32_t s0 = rotr32(x, 7U) ^ rotr32(x, 18U) ^ (x >> 3U);
        uint32_t s1 = rotr32(y, 17U) ^ rotr32(y, 19U) ^ (y >> 10U);
        words[i] = words[i - (size_t)16] + s0 + words[i - (size_t)7] + s1;
    }
    a = hash->state[0];
    b = hash->state[1];
    c = hash->state[2];
    d = hash->state[3];
    e = hash->state[4];
    f = hash->state[5];
    g = hash->state[6];
    h = hash->state[7];
    for (i = 0; i < (size_t)64; i++) {
        uint32_t upper = rotr32(e, 6U) ^ rotr32(e, 11U) ^ rotr32(e, 25U);
        uint32_t choose = (e & f) ^ ((~e) & g);
        uint32_t first = h + upper + choose + constants[i] + words[i];
        uint32_t lower = rotr32(a, 2U) ^ rotr32(a, 13U) ^ rotr32(a, 22U);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t second = lower + majority;
        h = g;
        g = f;
        f = e;
        e = d + first;
        d = c;
        c = b;
        b = a;
        a = first + second;
    }
    hash->state[0] += a;
    hash->state[1] += b;
    hash->state[2] += c;
    hash->state[3] += d;
    hash->state[4] += e;
    hash->state[5] += f;
    hash->state[6] += g;
    hash->state[7] += h;
}

static void sha256_init(struct Sha256 *hash) {
    static const uint32_t initial[8] = {
        UINT32_C(0x6a09e667), UINT32_C(0xbb67ae85), UINT32_C(0x3c6ef372), UINT32_C(0xa54ff53a),
        UINT32_C(0x510e527f), UINT32_C(0x9b05688c), UINT32_C(0x1f83d9ab), UINT32_C(0x5be0cd19)
    };
    (void)memcpy(hash->state, initial, sizeof(initial));
    hash->length = UINT64_C(0);
    hash->used = (size_t)0;
}

static int sha256_update(struct Sha256 *hash, const unsigned char *data, size_t length) {
    size_t at = 0;
#if SIZE_MAX > UINT64_MAX
    if (length > (size_t)UINT64_MAX) {
        return 0;
    }
#endif
    if ((uint64_t)length > (UINT64_MAX - hash->length) / UINT64_C(8)) {
        return 0;
    }
    hash->length += (uint64_t)length * UINT64_C(8);
    while (at < length) {
        size_t available = (size_t)64 - hash->used;
        size_t take = length - at < available ? length - at : available;
        (void)memcpy(hash->block + hash->used, data + at, take);
        hash->used += take;
        at += take;
        if (hash->used == (size_t)64) {
            sha256_compress(hash, hash->block);
            hash->used = (size_t)0;
        }
    }
    return 1;
}

static void sha256_finish(struct Sha256 *hash, unsigned char digest[32]) {
    size_t i;
    hash->block[hash->used++] = (unsigned char)0x80;
    if (hash->used > (size_t)56) {
        while (hash->used < (size_t)64) {
            hash->block[hash->used++] = (unsigned char)0;
        }
        sha256_compress(hash, hash->block);
        hash->used = (size_t)0;
    }
    while (hash->used < (size_t)56) {
        hash->block[hash->used++] = (unsigned char)0;
    }
    for (i = 0; i < (size_t)8; i++) {
        unsigned int shift = (unsigned int)(((size_t)7 - i) * (size_t)8);
        hash->block[(size_t)56 + i] = (unsigned char)(hash->length >> shift);
    }
    sha256_compress(hash, hash->block);
    for (i = 0; i < (size_t)8; i++) {
        digest[i * (size_t)4] = (unsigned char)(hash->state[i] >> 24U);
        digest[i * (size_t)4 + (size_t)1] = (unsigned char)(hash->state[i] >> 16U);
        digest[i * (size_t)4 + (size_t)2] = (unsigned char)(hash->state[i] >> 8U);
        digest[i * (size_t)4 + (size_t)3] = (unsigned char)hash->state[i];
    }
}

static int hex_value(unsigned char byte) {
    if (byte >= (unsigned char)'0' && byte <= (unsigned char)'9') {
        return (int)(byte - (unsigned char)'0');
    }
    if (byte >= (unsigned char)'a' && byte <= (unsigned char)'f') {
        return (int)(byte - (unsigned char)'a') + 10;
    }
    return -1;
}

static int parse_digest(const unsigned char *text, size_t length, unsigned char digest[32]) {
    size_t i;
    if (length != (size_t)64) {
        return 0;
    }
    for (i = 0; i < (size_t)32; i++) {
        int high = hex_value(text[i * (size_t)2]);
        int low = hex_value(text[i * (size_t)2 + (size_t)1]);
        if (high < 0 || low < 0) {
            return 0;
        }
        digest[i] = (unsigned char)((unsigned int)high * 16U + (unsigned int)low);
    }
    return 1;
}

static int sha256_vector(const unsigned char *data, size_t length, const char *expected) {
    struct Sha256 hash;
    unsigned char digest[32];
    unsigned char parsed[32];
    sha256_init(&hash);
    if (!sha256_update(&hash, data, length)) {
        return 0;
    }
    sha256_finish(&hash, digest);
    return parse_digest((const unsigned char *)expected, strlen(expected), parsed) &&
           memcmp(digest, parsed, sizeof(digest)) == 0;
}

static int self_test(void) {
    static const unsigned char long_vector[] =
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    if (!sha256_vector((const unsigned char *)"", (size_t)0,
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") ||
        !sha256_vector((const unsigned char *)"abc", (size_t)3,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") ||
        !sha256_vector(long_vector, sizeof(long_vector) - (size_t)1,
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")) {
        (void)fputs("alder inventory: SHA-256 self-test failed\n", stderr);
        return EXIT_FAILURE;
    }
    (void)fputs("alder inventory: SHA-256 self-test ok\n", stdout);
    return EXIT_SUCCESS;
}

static int read_all(const char *path, unsigned char **out, size_t *out_length) {
    FILE *file = fopen(path, "rb");
    unsigned char *data = NULL;
    size_t length = 0;
    size_t capacity = 0;
    if (file == NULL) {
        return 0;
    }
    for (;;) {
        size_t got;
        if (length == capacity) {
            size_t next = capacity == (size_t)0 ? (size_t)4096 : capacity * (size_t)2;
            unsigned char *grown;
            if (next < capacity) {
                free(data);
                (void)fclose(file);
                return 0;
            }
            grown = (unsigned char *)realloc(data, next);
            if (grown == NULL) {
                free(data);
                (void)fclose(file);
                return 0;
            }
            data = grown;
            capacity = next;
        }
        got = fread(data + length, (size_t)1, capacity - length, file);
        length += got;
        if (got == (size_t)0) {
            if (ferror(file) != 0) {
                free(data);
                (void)fclose(file);
                return 0;
            }
            break;
        }
    }
    if (fclose(file) != 0) {
        free(data);
        return 0;
    }
    *out = data;
    *out_length = length;
    return 1;
}

static int parse_length(const unsigned char *text, size_t length, uint64_t *out) {
    uint64_t value = UINT64_C(0);
    size_t i;
    if (length == (size_t)0 || (length > (size_t)1 && text[0] == (unsigned char)'0')) {
        return 0;
    }
    for (i = 0; i < length; i++) {
        unsigned int digit;
        if (text[i] < (unsigned char)'0' || text[i] > (unsigned char)'9') {
            return 0;
        }
        digit = (unsigned int)(text[i] - (unsigned char)'0');
        if (value > (UINT64_MAX - (uint64_t)digit) / UINT64_C(10)) {
            return 0;
        }
        value = value * UINT64_C(10) + (uint64_t)digit;
    }
    *out = value;
    return 1;
}

static int path_byte_ok(unsigned char byte) {
    return (byte >= (unsigned char)'a' && byte <= (unsigned char)'z') ||
           (byte >= (unsigned char)'A' && byte <= (unsigned char)'Z') ||
           (byte >= (unsigned char)'0' && byte <= (unsigned char)'9') ||
           byte == (unsigned char)'_' || byte == (unsigned char)'-' ||
           byte == (unsigned char)'.';
}

static int canonical_path(const unsigned char *path, size_t length) {
    size_t start = 0;
    size_t i;
    if (length == (size_t)0) {
        return 0;
    }
    for (i = 0; i <= length; i++) {
        if (i == length || path[i] == (unsigned char)'/') {
            size_t component_length = i - start;
            if (component_length == (size_t)0 ||
                (component_length == (size_t)1 && path[start] == (unsigned char)'.') ||
                (component_length == (size_t)2 && path[start] == (unsigned char)'.' &&
                 path[start + (size_t)1] == (unsigned char)'.')) {
                return 0;
            }
            start = i + (size_t)1;
        } else if (!path_byte_ok(path[i])) {
            return 0;
        }
    }
    return 1;
}

static int compare_path(const unsigned char *left, size_t left_length,
                        const unsigned char *right, size_t right_length) {
    size_t common = left_length < right_length ? left_length : right_length;
    int order = memcmp(left, right, common);
    if (order != 0) {
        return order;
    }
    return left_length < right_length ? -1 : left_length > right_length ? 1 : 0;
}

static char *join_path(const char *root, const unsigned char *path, size_t path_length) {
    size_t root_length = strlen(root);
    int separator = root_length > (size_t)0 && root[root_length - (size_t)1] != '/' &&
                    root[root_length - (size_t)1] != '\\';
    size_t total;
    char *joined;
    if (root_length > SIZE_MAX - path_length - (size_t)2) {
        return NULL;
    }
    total = root_length + (separator ? (size_t)1 : (size_t)0) + path_length;
    joined = (char *)malloc(total + (size_t)1);
    if (joined == NULL) {
        return NULL;
    }
    (void)memcpy(joined, root, root_length);
    if (separator) {
        joined[root_length] = '/';
    }
    (void)memcpy(joined + root_length + (separator ? (size_t)1 : (size_t)0), path, path_length);
    joined[total] = '\0';
    return joined;
}

static void print_path(const unsigned char *path, size_t length) {
    (void)fwrite(path, (size_t)1, length, stderr);
}

static int verify_source(const char *root, const unsigned char *path, size_t path_length,
                         uint64_t expected_length, const unsigned char expected_digest[32]) {
    char *joined = join_path(root, path, path_length);
    FILE *file;
    struct Sha256 hash;
    unsigned char digest[32];
    unsigned char buffer[4096];
    uint64_t length = UINT64_C(0);
    if (joined == NULL) {
        (void)fputs("alder inventory: cannot construct source path\n", stderr);
        return 0;
    }
    file = fopen(joined, "rb");
    free(joined);
    if (file == NULL) {
        (void)fputs("alder inventory: missing source: ", stderr);
        print_path(path, path_length);
        (void)fputc('\n', stderr);
        return 0;
    }
    sha256_init(&hash);
    for (;;) {
        size_t got = fread(buffer, (size_t)1, sizeof(buffer), file);
        if (got > (size_t)0) {
            if ((uint64_t)got > UINT64_MAX - length || !sha256_update(&hash, buffer, got)) {
                (void)fputs("alder inventory: source too large: ", stderr);
                print_path(path, path_length);
                (void)fputc('\n', stderr);
                (void)fclose(file);
                return 0;
            }
            length += (uint64_t)got;
        }
        if (got < sizeof(buffer)) {
            int read_failed = ferror(file) != 0;
            int close_failed = fclose(file) != 0;
            if (read_failed || close_failed) {
                (void)fputs("alder inventory: cannot read source: ", stderr);
                print_path(path, path_length);
                (void)fputc('\n', stderr);
                return 0;
            }
            break;
        }
    }
    sha256_finish(&hash, digest);
    if (length != expected_length) {
        (void)fputs("alder inventory: length mismatch: ", stderr);
        print_path(path, path_length);
        (void)fputc('\n', stderr);
        return 0;
    }
    if (memcmp(digest, expected_digest, sizeof(digest)) != 0) {
        (void)fputs("alder inventory: digest mismatch: ", stderr);
        print_path(path, path_length);
        (void)fputc('\n', stderr);
        return 0;
    }
    return 1;
}

static int fail_line(size_t line, const char *message) {
    (void)fprintf(stderr, "alder inventory: line %" PRIuMAX ": %s\n", (uintmax_t)line, message);
    return EXIT_FAILURE;
}

static int verify_inventory(const char *manifest_path, const char *root) {
    static const unsigned char header[] = "ALDER-COMPILER-SOURCES 1";
    unsigned char *manifest = NULL;
    size_t manifest_length = 0;
    size_t at = 0;
    size_t line_number = 1;
    struct InventoryEntry *entries = NULL;
    size_t entry_count = 0;
    size_t entry_capacity = 0;
    int result = EXIT_FAILURE;
    if (!read_all(manifest_path, &manifest, &manifest_length)) {
        (void)fputs("alder inventory: cannot read manifest\n", stderr);
        return EXIT_FAILURE;
    }
    while (at < manifest_length) {
        size_t line_start = at;
        size_t line_end;
        const unsigned char *line;
        size_t line_length;
        while (at < manifest_length && manifest[at] != (unsigned char)'\n') {
            at++;
        }
        if (at == manifest_length) {
            result = fail_line(line_number, "missing final line feed");
            goto done;
        }
        line_end = at;
        at++;
        line = manifest + line_start;
        line_length = line_end - line_start;
        if (line_number == (size_t)1) {
            if (line_length != sizeof(header) - (size_t)1 ||
                memcmp(line, header, sizeof(header) - (size_t)1) != 0) {
                result = fail_line(line_number, "invalid header");
                goto done;
            }
        } else if (line_length > (size_t)7 && memcmp(line, "sha256 ", (size_t)7) == 0) {
            struct Sha256 hash;
            unsigned char actual[32];
            unsigned char expected[32];
            if (at != manifest_length || !parse_digest(line + (size_t)7, line_length - (size_t)7, expected)) {
                result = fail_line(line_number, "invalid manifest digest");
                goto done;
            }
            sha256_init(&hash);
            if (!sha256_update(&hash, manifest, line_start)) {
                (void)fputs("alder inventory: manifest too large\n", stderr);
                goto done;
            }
            sha256_finish(&hash, actual);
            if (memcmp(actual, expected, sizeof(actual)) != 0) {
                (void)fputs("alder inventory: manifest digest mismatch\n", stderr);
                goto done;
            }
            {
                size_t i;
                for (i = 0; i < entry_count; i++) {
                    if (!verify_source(root, entries[i].path, entries[i].path_length,
                                       entries[i].length, entries[i].digest)) {
                        goto done;
                    }
                }
            }
            result = EXIT_SUCCESS;
            goto done;
        } else {
            size_t first = 0;
            size_t second;
            uint64_t expected_length;
            unsigned char expected_digest[32];
            const unsigned char *path;
            size_t path_length;
            while (first < line_length && line[first] != (unsigned char)' ') {
                first++;
            }
            second = first + (size_t)1;
            while (second < line_length && line[second] != (unsigned char)' ') {
                second++;
            }
            if (first == line_length || second == line_length ||
                !parse_length(line, first, &expected_length) ||
                !parse_digest(line + first + (size_t)1, second - first - (size_t)1, expected_digest)) {
                result = fail_line(line_number, "invalid entry");
                goto done;
            }
            path = line + second + (size_t)1;
            path_length = line_length - second - (size_t)1;
            if (!canonical_path(path, path_length)) {
                result = fail_line(line_number, "noncanonical path");
                goto done;
            }
            if (entry_count > (size_t)0) {
                const struct InventoryEntry *previous = &entries[entry_count - (size_t)1];
                int order = compare_path(previous->path, previous->path_length, path, path_length);
                if (order == 0) {
                    result = fail_line(line_number, "duplicate path");
                    goto done;
                }
                if (order > 0) {
                    result = fail_line(line_number, "paths not in lexicographic order");
                    goto done;
                }
            }
            if (entry_count == entry_capacity) {
                size_t next = entry_capacity == (size_t)0 ? (size_t)8 : entry_capacity * (size_t)2;
                struct InventoryEntry *grown;
                if (next < entry_capacity || next > SIZE_MAX / sizeof(*entries)) {
                    (void)fputs("alder inventory: too many entries\n", stderr);
                    goto done;
                }
                grown = (struct InventoryEntry *)realloc(entries, next * sizeof(*entries));
                if (grown == NULL) {
                    (void)fputs("alder inventory: cannot allocate entries\n", stderr);
                    goto done;
                }
                entries = grown;
                entry_capacity = next;
            }
            entries[entry_count].path = path;
            entries[entry_count].path_length = path_length;
            entries[entry_count].length = expected_length;
            (void)memcpy(entries[entry_count].digest, expected_digest, sizeof(expected_digest));
            entry_count++;
        }
        line_number++;
    }
    result = fail_line(line_number, "missing manifest digest");
done:
    free(entries);
    free(manifest);
    if (result == EXIT_SUCCESS) {
        (void)fputs("alder inventory: ok\n", stdout);
    }
    return result;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        return self_test();
    }
    if (argc != 3) {
        (void)fputs("usage: alder-inventory-verify MANIFEST ROOT\n", stderr);
        return 2;
    }
    return verify_inventory(argv[1], argv[2]);
}
