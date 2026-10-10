#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum { CONTROL = 0x00, STATUS = 0x04, PC = 0x08, IR = 0x0c,
       ID = 0x14, PROG_ADDR = 0x18, PROG_DATA = 0x1c,
       PROG_LENGTH = 0x20, LOAD_STATUS = 0x24, SPAN = 64, MAX_WORDS = 256 };

static uint32_t read_reg(volatile uint32_t *regs, unsigned offset)
{
    __sync_synchronize();
    uint32_t value = regs[offset / 4];
    __sync_synchronize();
    return value;
}

static void write_reg(volatile uint32_t *regs, unsigned offset, uint32_t value)
{
    __sync_synchronize();
    regs[offset / 4] = value;
    __sync_synchronize();
}

static int parse_number(const char *text, uint64_t *value)
{
    char *end;
    if (!*text || *text == '-' || isspace((unsigned char)*text)) return -1;
    errno = 0;
    unsigned long long parsed = strtoull(text, &end, 0);
    if (errno || *end) return -1;
    *value = parsed;
    return 0;
}

static int read_program(const char *path, uint32_t words[MAX_WORDS], unsigned *count)
{
    FILE *file = fopen(path, "r");
    char line[1024];
    unsigned line_number = 0;
    int result = -1;
    if (!file) { perror(path); return -1; }
    *count = 0;
    while (fgets(line, sizeof line, file)) {
        char *cursor = line;
        ++line_number;
        if (!strchr(line, '\n') && !feof(file)) {
            fprintf(stderr, "%s:%u: linha longa demais\n", path, line_number);
            goto done;
        }
        while (isspace((unsigned char)*cursor)) ++cursor;
        if (!*cursor || *cursor == '#' || !strncmp(cursor, "//", 2)) continue;
        uint32_t word = 0;
        unsigned digits = 0;
        while (isxdigit((unsigned char)*cursor)) {
            unsigned digit = isdigit((unsigned char)*cursor) ?
                (unsigned)(*cursor - '0') : (unsigned)(tolower((unsigned char)*cursor) - 'a' + 10);
            if (++digits > 8) break;
            word = (word << 4) | digit;
            ++cursor;
        }
        while (isspace((unsigned char)*cursor)) ++cursor;
        if (digits != 8 || (*cursor && *cursor != '#' && strncmp(cursor, "//", 2))) {
            fprintf(stderr, "%s:%u: esperado um word de oito digitos HEX por linha\n", path, line_number);
            goto done;
        }
        if (*count == MAX_WORDS) {
            fprintf(stderr, "%s: limite de %d instrucoes excedido\n", path, MAX_WORDS);
            goto done;
        }
        words[(*count)++] = word;
    }
    if (ferror(file)) { perror(path); goto done; }
    if (!*count) { fprintf(stderr, "%s: programa vazio\n", path); goto done; }
    result = 0;
done:
    fclose(file);
    return result;
}

static uint64_t milliseconds(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

static int wait_ready(volatile uint32_t *regs, uint64_t timeout, int loading)
{
    uint64_t started = milliseconds();
    const struct timespec delay = { .tv_sec = 0, .tv_nsec = 1000000 };
    do {
        uint32_t status = read_reg(regs, loading ? LOAD_STATUS : STATUS);
        if (status & (loading ? 2u : 8u)) {
            fprintf(stderr, "Erro FPGA: status=%08" PRIx32 " PC=%" PRIu32 " IR=%08" PRIx32 "\n",
                    status, read_reg(regs, PC), read_reg(regs, IR));
            return -1;
        }
        if (loading ? (status & 1u) : ((status & 6u) == 4u)) return 0;
        nanosleep(&delay, NULL);
    } while (milliseconds() - started < timeout);
    fprintf(stderr, "Timeout aguardando %s; PC=%" PRIu32 " IR=%08" PRIx32 "\n",
            loading ? "LOAD_READY" : "HALT", read_reg(regs, PC), read_reg(regs, IR));
    return -1;
}

static void usage(const char *name)
{
    fprintf(stderr, "Uso: %s --check arquivo.hex\n"
            "     %s --base ENDERECO_FISICO --program arquivo.hex [--timeout-ms 10000]\n"
            "A base deve vir do mapa real Platform Designer + configuracao HPS/Linux.\n",
            name, name);
}

int main(int argc, char **argv)
{
    const char *program = NULL;
    uint64_t base = 0, timeout = 10000;
    int have_base = 0, check = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--check") && i + 1 < argc) { check = 1; program = argv[++i]; }
        else if (!strcmp(argv[i], "--program") && i + 1 < argc) program = argv[++i];
        else if (!strcmp(argv[i], "--base") && i + 1 < argc) {
            if (parse_number(argv[++i], &base)) { usage(argv[0]); return 2; }
            have_base = 1;
        } else if (!strcmp(argv[i], "--timeout-ms") && i + 1 < argc) {
            if (parse_number(argv[++i], &timeout) || !timeout || timeout > 3600000) {
                usage(argv[0]); return 2;
            }
        } else { usage(argv[0]); return 2; }
    }
    if (!program || (!check && (!have_base || (base & 3u) || base > INT64_MAX - SPAN))) {
        usage(argv[0]); return 2;
    }
    uint32_t words[MAX_WORDS];
    unsigned count;
    if (read_program(program, words, &count)) return 1;
    if (check) { printf("HEX valido: %u instrucoes\n", count); return 0; }

    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) { fprintf(stderr, "Tamanho de pagina invalido\n"); return 1; }
    uint64_t page_base = base - base % (uint64_t)page_size;
    size_t offset = (size_t)(base - page_base);
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("/dev/mem"); return 1; }
    size_t map_length = offset + SPAN;
    void *mapping = mmap(NULL, map_length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)page_base);
    close(fd);
    if (mapping == MAP_FAILED) { perror("mmap"); return 1; }
    volatile uint32_t *regs = (volatile uint32_t *)((unsigned char *)mapping + offset);
    int result = 1;
    if (read_reg(regs, ID) != UINT32_C(0x50424c32)) {
        fprintf(stderr, "ID diferente de PBL2: confira ponte habilitada e endereco real\n");
        goto done;
    }
    unsigned capacity = read_reg(regs, LOAD_STATUS) >> 16;
    if (!capacity || capacity > MAX_WORDS || count > capacity) {
        fprintf(stderr, "Capacidade FPGA=%u, programa=%u palavras\n", capacity, count);
        goto done;
    }
    write_reg(regs, CONTROL, 12); // Entrar/manter carga e limpar erro de tentativa anterior.
    if (wait_ready(regs, timeout, 1)) goto done;
    write_reg(regs, PROG_ADDR, 0);
    for (unsigned i = 0; i < count; ++i) write_reg(regs, PROG_DATA, words[i]);
    write_reg(regs, PROG_LENGTH, count);
    if (read_reg(regs, LOAD_STATUS) & 2u) { fprintf(stderr, "Carga recusada pelo FPGA\n"); goto done; }
    if (read_reg(regs, PROG_LENGTH) != count) { fprintf(stderr, "Comprimento nao confirmado\n"); goto done; }
    for (unsigned i = 0; i < count; ++i) {
        write_reg(regs, PROG_ADDR, i);
        uint32_t received = read_reg(regs, PROG_DATA); // Avalon espera a leitura sincrona.
        if (received != words[i]) {
            fprintf(stderr, "Readback[%u]=%08" PRIx32 ", esperado=%08" PRIx32 "\n", i, received, words[i]);
            goto done;
        }
    }
    printf("%u instrucoes carregadas e conferidas\n", count);
    write_reg(regs, CONTROL, 2); // Sair da carga e executar a partir de PC0.
    if (wait_ready(regs, timeout, 0)) goto done;
    printf("HALT confirmado: PC=%" PRIu32 " STATUS=%08" PRIx32 "\n",
           read_reg(regs, PC), read_reg(regs, STATUS));
    result = 0;
done:
    munmap(mapping, map_length);
    return result;
}
