/* govwelcome.c — стартовое приветствие govechoOS (GNOME Edition)
 * Пишет баннер в stdout и создаёт метку сессии ~/.config/govechoos/welcome.stamp
 * Используется как приложение автозапуска (.desktop Autostart).
 *
 * Автор: ZHBR-228
 * Лицензия: MIT (см. файл LICENSE)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define VERSION "2.1"

static const char *BANNER =
"  _______________________________________\n"
" /  govechoOS GNOME Edition              \\    .--.\n"
"| |  Добро пожаловать! Сессия активна.   | |   ( oo)\n"
"\\_| Стартовые программы govechoOS загружены |_/  (_/)\n"
"  ---------------------------------------\n";

static void stamp_file(void)
{
	const char *home = getenv("HOME");
	if (!home || !*home)
		return;
	char dir[4096], path[4200];
	snprintf(dir, sizeof dir, "%s/.config", home);
	(void)mkdir(dir, 0755);              /* уже существует — не страшно */
	snprintf(dir, sizeof dir, "%s/.config/govechoos", home);
	(void)mkdir(dir, 0755);
	snprintf(path, sizeof path, "%s/welcome.stamp", dir);
	FILE *f = fopen(path, "w");
	if (f) {
		fprintf(f, "govechoOS gnome session welcome ok\n");
		fclose(f);
	}
}

int main(int argc, char **argv)
{
	if (argc > 1 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0)) {
		printf("govechoOS govwelcome %s\n", VERSION);
		return 0;
	}
	fputs(BANNER, stdout);
	stamp_file();
	return 0;
}
