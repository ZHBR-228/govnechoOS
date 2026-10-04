/* govctl.c — центральная консоль управления govechoOS
 * Единая утилита команд дистрибутива: статус, информация, GNOME-чистота,
 * ряд стартовых программ, лицензии/авторство.
 *
 * Примеры:
 *   govctl status              сводка системы (версия, база, компоненты)
 *   govctl info                govechoOS vs Debian/Ubuntu + автор + лицензия
 *   govctl gnome tidy          применить «чистоту GNOME» (dconf-профиль govechoOS)
 *   govctl apps list|add|remove <app>   управление рядом стартовых программ
 *   govctl license             текст MIT-лицензии
 *   govctl author              данные автора (ZHBR-228)
 *   govctl echo ...            быстрый доступ к фирменному govecho
 *   govctl version
 *
 * Автор: ZHBR-228
 * Лицензия: MIT (см. файл LICENSE)
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

#define VERSION "2.1"
#define AUTHOR  "ZHBR-228"
#define REPO    "https://github.com/ZHBR-228/govnechoOS"

static const char *BANNER =
"   .-------.\n"
"  / o     o \\   govechoOS govctl " VERSION "\n"
" |     ^     |  \"вся система — одна команда\"\n"
"  \\   '-'   /   автор: " AUTHOR "\n"
"   '-------'    лицензия: MIT\n";

static int file_exists(const char *p)
{
	struct stat st;
	return stat(p, &st) == 0;
}

static void print_file(const char *path)
{
	FILE *f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "govctl: нет файла %s\n", path);
		return;
	}
	char buf[4096];
	size_t n;
	while ((n = fread(buf, 1, sizeof buf, f)) > 0)
		fwrite(buf, 1, n, stdout);
	fclose(f);
}

static const char *detect_base(void)
{
	if (file_exists("/etc/os-release")) {
		FILE *f = fopen("/etc/os-release", "r");
		char line[512];
		static char id[64] = "unknown";
		if (f) {
			while (fgets(line, sizeof line, f)) {
				if (strncmp(line, "ID=", 3) == 0) {
					char *v = line + 3;
					v[strcspn(v, "\"\n\r")] = '\0';
					memcpy(id, v, strlen(v) < 63 ? strlen(v) : 63), id[strlen(v) < 63 ? strlen(v) : 63] = 0;
					break;
				}
			}
			fclose(f);
		}
		if (strstr(id, "govechoos") || strstr(id, "debian") ||
		    strstr(id, "ubuntu"))
			return id;
		return id;
	}
	return "standalone";
}

/* ---------------- status ---------------- */
static int cmd_status(int argc, char **argv)
{
	(void)argc; (void)argv;
	printf("%s", BANNER);
	printf("Выпуск:        govechoOS %s (GNOME Edition)\n", VERSION);
	printf("База системы:  %s\n", detect_base());
	printf("Авторы:        %s\n", AUTHOR);
	printf("Лицензия:      MIT\n");
	printf("Репозиторий:   %s\n\n", REPO);

	struct { const char *name; const char *path; } comps[] = {
		{ "govinit       (init PID 1)",   "/sbin/govinit" },
		{ "govecho       (echo+баннер)",  "/usr/local/bin/govecho" },
		{ "govwelcome    (приветствие)",  "/usr/local/bin/govwelcome" },
		{ "govstartapps  (ряд программ)", "/usr/local/bin/govstartapps" },
		{ "govclean      (чистота GNOME)", "/usr/local/bin/govclean" },
		{ "govctl        (эта утилита)",  "/usr/local/bin/govctl" },
	};
	printf("Компоненты:\n");
	for (size_t i = 0; i < sizeof comps / sizeof comps[0]; i++)
		printf("  [%s] %s\n", file_exists(comps[i].path) ? "+" : "-",
		       comps[i].name);

	if (file_exists("/usr/share/gnome-shell"))
		printf("\nGNOME: установлен (gnome-shell присутствует)\n");
	else
		printf("\nGNOME: не найден (базовая/консольная сессия)\n");
	return 0;
}

/* ---------------- info ---------------- */
static int cmd_info(int argc, char **argv)
{
	(void)argc; (void)argv;
	printf("govechoOS — учебный Linux-дистрибутив на базе Debian/Ubuntu\n");
	printf("с собственной оболочкой GNOME и фирменными компонентами.\n\n");
	printf("Автор:      %s\n", AUTHOR);
	printf("Лицензия:   MIT (свободное использование, см. `govctl license`)\n");
	printf("Исходники:  %s\n\n", REPO);
	printf("Чем govechoOS отличается от чистого Debian/Ubuntu:\n");
	printf("  * govinit — собственный init для контейнеров/QEMU-образов\n");
	printf("  * govecho — echo с фирменными баннерами (-s banner|loud)\n");
	printf("  * govwelcome/govstartapps — приветствие и ряд стартовых программ\n");
	printf("  * govclean — профиль «чистоты GNOME» (десктоп, панель, темы)\n");
	printf("  * govctl   — единая консоль управления системой\n");
	printf("  * Live-ISO + установщик: sudo ./live/scripts/build_live.sh\n");
	return 0;
}

/* ---------------- license / author ---------------- */
static int cmd_license(int argc, char **argv)
{
	(void)argc; (void)argv;
	const char *paths[] = { "/usr/share/doc/govechoos/LICENSE",
	                        "/etc/govechoos/LICENSE", "./LICENSE",
	                        "../LICENSE", NULL };
	for (int i = 0; paths[i]; i++)
		if (file_exists(paths[i])) { print_file(paths[i]); return 0; }
	printf("Лицензия MIT (c) %s\n\n", AUTHOR);
	printf("Допускается свободное использование, копирование, модификация,\n");
	printf("слияние, публикация, распространение и продажа при условии\n");
	printf("сохранения уведомления об авторстве. ПО даётся «как есть».\n");
	return 0;
}

static int cmd_author(int argc, char **argv)
{
	(void)argc; (void)argv;
	printf("Автор govechoOS: %s\n", AUTHOR);
	printf("Репозиторий:     %s\n", REPO);
	return 0;
}

/* ---------------- gnome tidy ---------------- */
static int cmd_gnome(int argc, char **argv)
{
	if (argc >= 2 && strcmp(argv[1], "tidy") == 0) {
		printf("Применение профиля чистоты GNOME (govechoOS)...\n");
		if (access("/usr/local/bin/govclean", X_OK) == 0) {
			char *cmd[] = { (char *)"/usr/local/bin/govclean",
			                (char *)"apply", NULL };
			execv(cmd[0], cmd);
			perror("govclean");
			return 1;
		}
		printf("govclean не найден — примените dconf-профиль вручную:\n");
		printf("  dconf load / < /usr/share/govechoos/gnome-clean.dconf\n");
		return 0;
	}
	printf("Использование: govctl gnome tidy   — применить чистоту GNOME\n");
	return argc >= 2 ? 2 : 0;
}

/* ---------------- apps list/add/remove ---------------- */
static const char *autostart_dir(void)
{
	static char dir[4096];
	const char *home = getenv("HOME");
	if (!home || !*home) home = "/root";
	snprintf(dir, sizeof dir, "%s/.config/autostart", home);
	return dir;
}

static int cmd_apps(int argc, char **argv)
{
	const char *adir = autostart_dir();
	if (argc < 2 || strcmp(argv[1], "list") == 0) {
		printf("Ряд стартовых программ (%s):\n", adir);
		DIR *d = opendir(adir);
		int found = 0;
		if (d) {
			struct dirent *e;
			while ((e = readdir(d))) {
				size_t l = strlen(e->d_name);
				if (l > 8 && strcmp(e->d_name + l - 8, ".desktop") == 0) {
					printf("  * %s\n", e->d_name);
					found = 1;
				}
			}
			closedir(d);
		}
		if (!found) {
			/* системный автозапуск как источник по умолчанию */
			DIR *s = opendir("/etc/xdg/autostart");
			if (s) {
				struct dirent *e;
				while ((e = readdir(s))) {
					size_t l = strlen(e->d_name);
					if (l > 8 && strcmp(e->d_name + l - 8, ".desktop") == 0) {
						printf("  [сист.] %s\n", e->d_name);
						found = 1;
					}
				}
				closedir(s);
			}
		}
		if (!found) printf("  (пусто)\n");
		return 0;
	}
	if (strcmp(argv[1], "remove") == 0) {
		if (argc < 3) { fprintf(stderr, "Нужно имя приложения\n"); return 2; }
		char path[4200];
		snprintf(path, sizeof path, "%s/%s.desktop", adir, argv[2]);
		if (unlink(path) == 0) { printf("Убрано из ряда: %s\n", argv[2]); return 0; }
		if (errno == ENOENT) {
			snprintf(path, sizeof path, "%s/%s", adir, argv[2]);
			if (unlink(path) == 0) { printf("Убрано из ряда: %s\n", argv[2]); return 0; }
		}
		fprintf(stderr, "govctl: не найдено в ряду: %s\n", argv[2]);
		return 1;
	}
	if (strcmp(argv[1], "add") == 0) {
		if (argc < 3) { fprintf(stderr, "Нужно имя приложения\n"); return 2; }
		mkdir(adir, 0755);
		char dst[4200], src[4200];
		snprintf(dst, sizeof dst, "%s/%s.desktop", adir, argv[2]);
		if (file_exists(dst)) { printf("Уже в ряду: %s\n", argv[2]); return 0; }
		snprintf(src, sizeof src, "/usr/share/applications/%s.desktop", argv[2]);
		if (!file_exists(src)) {
			fprintf(stderr, "govctl: приложение '%s' не установлено\n", argv[2]);
			return 1;
		}
		FILE *in = fopen(src, "r"), *out = fopen(dst, "w");
		if (!in || !out) { perror("govctl"); fclose(in); fclose(out); return 1; }
		char line[8192];
		while (fgets(line, sizeof line, in)) fputs(line, out);
		fclose(in); fclose(out);
		printf("Добавлено в ряд стартовых: %s\n", argv[2]);
		return 0;
	}
	fprintf(stderr, "Использование: govctl apps [list|add|remove] [app]\n");
	return 2;
}

static int cmd_version(int argc, char **argv)
{
	(void)argc; (void)argv;
	printf("govechoOS govctl %s, база: %s, автор: %s\n",
	       VERSION, detect_base(), AUTHOR);
	return 0;
}

static void usage(void)
{
	printf("%s", BANNER);
	printf("Использование: govctl <команда> [подкоманда]\n\n");
	printf("Команды:\n");
	printf("  status              состояние системы и компонентов\n");
	printf("  info                о выпуске, авторе и отличиях\n");
	printf("  gnome tidy          применить чистоту GNOME\n");
	printf("  apps [list|add|remove <app>]   ряд стартовых программ\n");
	printf("  license             MIT-лицензия\n");
	printf("  author              автор (" AUTHOR ")\n");
	printf("  echo [флаги] текст  фирменный govecho\n");
	printf("  version             версия\n");
}

int main(int argc, char **argv)
{
	if (argc < 2) { usage(); return 0; }
	const char *c = argv[1];
	int (*disp)(int, char**) = NULL;
	if      (!strcmp(c, "status"))  disp = cmd_status;
	else if (!strcmp(c, "info"))    disp = cmd_info;
	else if (!strcmp(c, "gnome"))   disp = cmd_gnome;
	else if (!strcmp(c, "apps"))    disp = cmd_apps;
	else if (!strcmp(c, "license")) disp = cmd_license;
	else if (!strcmp(c, "author"))  disp = cmd_author;
	else if (!strcmp(c, "version") || !strcmp(c, "--version")) disp = cmd_version;
	else if (!strcmp(c, "echo")) {
		/* простой проброс: exec govecho с остатком аргументов */
		char **ga = calloc((size_t)argc, sizeof *ga);
		ga[0] = (char *)"govecho";
		for (int j = 2; j < argc; j++) ga[j - 1] = argv[j];
		ga[argc - 1] = NULL;
		execvp("govecho", ga);
		perror("govecho");
		return 1;
	}
	else if (!strcmp(c, "help") || !strcmp(c, "--help")) { usage(); return 0; }
	else { usage(); return 2; }
	return disp(argc - 1, argv + 1);
}
