/* govinit.c — собственный init (PID 1) для govechoOS
 *
 * Запускается ядром как init=/sbin/govinit. Делает:
 *   1. Монтирует виртуальные ФС (/proc, /sys, /dev, devtmpfs, /tmp, /run)
 *   2. Устанавливает hostname и выводит баннер /etc/issue
 *   3. Открывает /dev/console и поднимает интерактивный шелл на консоли
 *   4. Собирает зомби-процессы (reap) и реагирует на Ctrl-Alt-Del (ребут)
 *
 * Автор: ZHBR-228
 * Лицензия: MIT (см. файл LICENSE)
 */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/reboot.h>
#include <sys/klog.h>

#define CONSOLE "/dev/console"

static volatile sig_atomic_t got_reboot = 0;   /* Ctrl-Alt-Del -> SIGINT */

static void on_sigchld(int sig) { (void)sig; }  /* прерывает waitpid(EINTR) */
static void on_sigint(int sig)  { (void)sig; got_reboot = 1; }

static void mount_vfs(const char *src, const char *tgt, const char *type,
                      unsigned long flags, const void *data)
{
    mkdir(tgt, 0755);
    if (mount(src, tgt, type, flags, data) != 0)
        fprintf(stderr, "govinit: mount %s (%s) failed: %s\n",
                tgt, type, strerror(errno));
}

static void print_issue(void)
{
    FILE *f = fopen("/etc/issue", "r");
    char buf[256];
    if (!f) {
        printf("govechoOS ready.\n");
        return;
    }
    while (fgets(buf, sizeof buf, f)) fputs(buf, stdout);
    fclose(f);
}

/* Привязать стандартные потоки потомка к консоли и запустить шелл. */
static pid_t spawn_shell(void)
{
    pid_t pid = fork();
    if (pid != 0)
        return pid;

    setsid();
    int fd = open(CONSOLE, O_RDWR);
    if (fd >= 0) {
        dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
        if (fd > 2) close(fd);
    }
    execl("/bin/sh", "-sh", (char *)NULL);
    write(STDERR_FILENO, "govinit: /bin/sh not found\n", 27);
    _exit(127);
}

int main(void)
{
    /* PID 1 игнорирует случайные сигналы, кроме обрабатываемых */
    struct sigaction sa_chld = { .sa_handler = on_sigchld, .sa_flags = 0 };
    sigemptyset(&sa_chld.sa_mask);
    sigaction(SIGCHLD, &sa_chld, NULL);

    struct sigaction sa_int = { .sa_handler = on_sigint, .sa_flags = 0 };
    sigemptyset(&sa_int.sa_mask);
    sigaction(SIGINT,  &sa_int, NULL);   /* Ctrl-Alt-Del в консоли */
    sigaction(SIGTERM, &sa_int, NULL);

    signal(SIGHUP, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);

    klogctl(8, NULL, 0); /* KLOG_LEVEL_8: тише сообщения ядра */

    mount_vfs("devtmpfs", "/dev",    "devtmpfs", 0, NULL);
    mount_vfs("proc",     "/proc",   "proc",     0, NULL);
    mount_vfs("sysfs",    "/sys",    "sysfs",    0, NULL);
    mount_vfs("tmpfs",    "/dev/shm","tmpfs",    0, NULL);
    mount_vfs("tmpfs",    "/run",    "tmpfs",    0, NULL);
    mount_vfs("tmpfs",    "/tmp",    "tmpfs",    0, NULL);

    sethostname("govecho", 6);

    int fd = open(CONSOLE, O_RDWR);
    if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }

    printf("\n");
    print_issue();
    fflush(stdout);

    /* Главный цикл init: держим шелл живым, собираем детей, ждём ребута */
    for (;;) {
        pid_t shell_pid = spawn_shell();

        while (shell_pid > 0 && !got_reboot) {
            int status;
            pid_t w = waitpid(-1, &status, 0);
            if (w > 0) {
                if (w == shell_pid) { shell_pid = -1; break; }
                continue;              /* собран посторонний ребёнок (reap зомби) */
            }
            if (w < 0 && errno == EINTR) continue;
            break;                     /* непредвиденная ошибка ожидания */
        }

        /* собрать оставшихся зомби без блокировки */
        while (waitpid(-1, NULL, WNOHANG) > 0)
            ;

        if (got_reboot) {
            printf("govinit: rebooting...\n");
            sync();
            umount("/tmp"); umount("/run"); umount("/dev/shm");
            umount("/sys"); umount("/proc"); umount("/dev");
            reboot(RB_AUTOBOOT);
            for (;;) pause();
        }

        /* шелл завершился — короткая пауза и новый запуск сессии */
        sleep(1);
    }
    return 0;
}
