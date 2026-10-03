/* govecho.c — фирменная команда echo дистрибутива govechoOS.
 *
 * Совместима с POSIX echo (-n, -e/-E) и добавляет «фирменные» флаги:
 *   -s, --style  STYLE   вывод в стиле дистрибутива (banner|plain|loud)
 *   -v, --version       версия govechoOS
 *
 * Автор: ZHBR-228
 * Лицензия: MIT (см. файл LICENSE)
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define GOVECHO_VERSION "1.0"
#define DISTRO_NAME     "govechoOS"

static void usage(FILE *out)
{
    fprintf(out,
        "Использование: govecho [-neE] [-s СТИЛЬ] [-v] [СТРОКА]...\n"
        "  -n            не добавлять перевод строки\n"
        "  -e            включать интерпретацию backslash-escape\n"
        "  -E            выключать интерпретацию backslash-escape (по умолчанию)\n"
        "  -s, --style   стиль вывода: plain|banner|loud\n"
        "  -v, --version версия " DISTRO_NAME "\n");
}

static void emit_escaped(const char *s)
{
    for (; *s; s++) {
        if (*s != '\\') { fputc(*s, stdout); continue; }
        switch (*++s) {
        case '\0': fputs("\\", stdout); return; /* trailing backslash */
        case 'a': fputc('\a', stdout); break;
        case 'b': fputc('\b', stdout); break;
        case 'c': return; /* подавить остаток вывода и newline */
        case 'e': fputc(033, stdout); break;
        case 'f': fputc('\f', stdout); break;
        case 'n': fputc('\n', stdout); break;
        case 'r': fputc('\r', stdout); break;
        case 't': fputc('\t', stdout); break;
        case 'v': fputc('\v', stdout); break;
        case '\\': fputc('\\', stdout); break;
        default: fputs("\\", stdout); fputc(s[-1], stdout); fputc(*s, stdout); break;
        }
    }
}

int main(int argc, char **argv)
{
    int add_newline = 1, escapes = 0;
    const char *style = "plain";
    int i = 1;

    /* разбор ведущих флагов (как у echo: флаги только до первого операнда) */
    for (; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "--") == 0) { i++; break; }
        if (a[0] != '-' || a[1] == '\0' || a[1] == '-') {
            if (a[0] == '-' && a[1] == '\0') break; /* одиночный "-" это операнд */
            break;
        }
        for (const char *p = a + 1; *p; p++) {
            switch (*p) {
            case 'n': add_newline = 0; break;
            case 'e': escapes = 1; break;
            case 'E': escapes = 0; break;
            case 'v':
                printf("%s govecho %s (init govinit-1.0)\n", DISTRO_NAME, GOVECHO_VERSION);
                return 0;
            case 'h': usage(stdout); return 0;
            case 's':
                if (p[1]) { style = p + 1; p += strlen(p) - 1; }
                else if (i + 1 < argc) style = argv[++i];
                else { usage(stderr); return 2; }
                goto flags_done;
            default:
                usage(stderr); return 2;
            }
        }
    }
flags_done:

    if (strcmp(style, "banner") == 0) {
        puts("+==========================================+");
        puts("|            govechoOS banner              |");
        puts("+==========================================+");
    }

    for (int first = 1; i < argc; i++, first = 0) {
        if (!first) fputc(' ', stdout);
        if (escapes) emit_escaped(argv[i]);
        else fputs(argv[i], stdout);
    }

    if (strcmp(style, "loud") == 0 && argc > i)
        fputs(" <<< GOVECHO!", stdout);

    if (add_newline) fputc('\n', stdout);
    fflush(stdout);
    return 0;
}
