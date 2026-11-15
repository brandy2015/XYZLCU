// xyzlcu 的轻量客户端：把命令转发给守护进程（~/.xyzlcu/sock）并打印回复。
// 没有 AppKit / ScreenCaptureKit，启动只要 1～2 毫秒；守护进程不在、版本不一致、或者是不该转发的命令时，
// 直接 execv 同目录下的 xyzlcu-core（同一个进程号，权限归属不变）。
// 协议见 Sources/xyzlcu/main.swift 的「守护进程」一节。
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define VERSION "0.8.1"
// 和 main.swift 里的 forwardedEnv 保持一致
static const char *FORWARDED_ENV[] = {"XYZLCU_EVENTS_HEALTH", "XYZLCU_TAP_THRESHOLD_MS", "XYZLCU_TYPE_VIA", "XYZLCU_KEY_VIA",
                                      "XYZLCU_PROBE", "XYZLCU_PNG", "XYZLCU_PNG_LEVEL", "XYZLCU_BACKGROUND", "XYZLCU_CLICK_HOLD", NULL};

static char **g_argv;

static void exec_core(void) {
    char core[PATH_MAX];
    // Only the adjacent installed core can enforce this client's contract.
    // Environment overrides are intentionally retired, including daemon=0.
    char exe[PATH_MAX], real[PATH_MAX];
    uint32_t n = sizeof exe;
    if (_NSGetExecutablePath(exe, &n) != 0 || !realpath(exe, real)) { fprintf(stderr, "error: 找不到自身路径\n"); exit(1); }
    snprintf(core, sizeof core, "%s/xyzlcu-core", dirname(real));
    g_argv[0] = core;
    execv(core, g_argv);
    fprintf(stderr, "error: 无法执行 %s: %s\n", core, strerror(errno));
    exit(127);
}

// ---------- 小缓冲 ----------
typedef struct { char *p; size_t n, cap; } buf_t;
static void bput(buf_t *b, const void *d, size_t n) {
    if (b->n + n + 1 > b->cap) {
        size_t c = b->cap ? b->cap : 4096;
        while (c < b->n + n + 1) c *= 2;
        b->p = realloc(b->p, c); if (!b->p) { perror("realloc"); exit(1); }
        b->cap = c;
    }
    memcpy(b->p + b->n, d, n); b->n += n; b->p[b->n] = 0;
}
static void bstr(buf_t *b, const char *s) { bput(b, s, strlen(s)); }
static void bjson(buf_t *b, const char *s) {   // JSON 字符串（UTF-8 原样，转义引号、反斜杠和控制字符）
    bput(b, "\"", 1);
    for (const unsigned char *c = (const unsigned char *)s; *c; c++) {
        char e[8];
        switch (*c) {
        case '"': bput(b, "\\\"", 2); break;
        case '\\': bput(b, "\\\\", 2); break;
        case '\n': bput(b, "\\n", 2); break;
        case '\r': bput(b, "\\r", 2); break;
        case '\t': bput(b, "\\t", 2); break;
        default:
            if (*c < 0x20) { snprintf(e, sizeof e, "\\u%04x", *c); bput(b, e, 6); }
            else bput(b, c, 1);
        }
    }
    bput(b, "\"", 1);
}

// ---------- 连接（守护进程正在启动时等它） ----------
static int connect_once(const char *path) {
    struct sockaddr_un a; memset(&a, 0, sizeof a); a.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof a.sun_path) return -1;
    strcpy(a.sun_path, path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) { close(fd); return -1; }
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    return fd;
}
static int lock_held(const char *path) {
    char lp[PATH_MAX]; snprintf(lp, sizeof lp, "%s.lock", path);
    int fd = open(lp, O_RDONLY); if (fd < 0) return 0;
    struct flock fl; memset(&fl, 0, sizeof fl); fl.l_type = F_WRLCK; fl.l_whence = SEEK_SET;
    int held = fcntl(fd, F_GETLK, &fl) == 0 && fl.l_type != F_UNLCK;
    close(fd); return held;
}
static int connect_waiting(const char *path) {
    int fd = connect_once(path); if (fd >= 0) return fd;
    if (!lock_held(path)) return -1;
    const char *w = getenv("XYZLCU_CONNECT_WAIT_MS");
    long ms = w && *w ? atol(w) : 3000;
    struct timespec t0; clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        usleep(5000);
        if ((fd = connect_once(path)) >= 0) return fd;
        if (!lock_held(path)) return -1;
        struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
        if ((t.tv_sec - t0.tv_sec) * 1000 + (t.tv_nsec - t0.tv_nsec) / 1000000 > ms) return -1;
    }
}

static int write_all(int fd, const char *p, size_t n) {
    while (n) { ssize_t k = write(fd, p, n); if (k <= 0) return -1; p += k; n -= (size_t)k; }
    return 0;
}
static uint32_t be32(const unsigned char *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

int main(int argc, char **argv) {
    g_argv = argv;
    // Proof/session descriptors are process local. Protocol 2 cannot transfer
    // or authenticate them. Never forward them, retry, or consult an override.
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--assurance") == 0 || strcmp(argv[i], "--consumer") == 0 || strcmp(argv[i], "--request-fd") == 0 ||
            strcmp(argv[i], "--proof-protocol") == 0 || strcmp(argv[i], "--hmac-key-fd") == 0) {
            unsetenv("XYZLCU_CORE"); exec_core();
        }
    }
    const char *d = getenv("XYZLCU_DAEMON");
    if (argc < 2 || (d && strcmp(d, "0") == 0)) exec_core();
    const char *cmd = argv[1];
    // 帮助、长时间运行的录制 / 回放、守护进程本身和 MCP 服务器总是由主程序执行
    static const char *local[] = {"help", "-h", "--help", "record", "replay", "serve", "mcp", "selftest", "capabilities", "identity-observe", "open-app", "bind-window", "screenshot", "observe", "ax", "find", "value", "wait", "wait-text", "taps", "click", "click-el", "move", "drag", "scroll", "type", "key", "insert", "settext", "set-text", "menu", "press", "select", "scroll-to", "activate", "open", "hide", "movewin", "request", "__ax-press", "lock", "batch", "run", NULL};
    for (int i = 0; local[i]; i++) if (strcmp(cmd, local[i]) == 0) { unsetenv("XYZLCU_CORE"); exec_core(); }
    if (strcmp(cmd, "windows") == 0) {
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--thumbnails") == 0 || strcmp(argv[i], "--show-all") == 0) {
                unsetenv("XYZLCU_CORE"); exec_core();
            }
        }
    }

    char path[PATH_MAX];
    const char *sp = getenv("XYZLCU_SOCKET");
    if (sp && *sp) snprintf(path, sizeof path, "%s", sp);
    else { const char *h = getenv("HOME"); if (!h) exec_core(); snprintf(path, sizeof path, "%s/.xyzlcu/sock", h); }

    int fd = connect_waiting(path);
    if (fd < 0) {
        if (d && strcmp(d, "1") == 0) { fprintf(stderr, "error: 守护进程没有运行（先执行 xyzlcu serve --background）\n"); return 5; }
        exec_core();
    }

    buf_t req = {0};
    bstr(&req, "{\"v\":\"" VERSION "\",\"proto\":2,\"argv\":[");
    for (int i = 1; i < argc; i++) { if (i > 1) bstr(&req, ","); bjson(&req, argv[i]); }
    bstr(&req, "],\"cwd\":");
    char cwd[PATH_MAX]; bjson(&req, getcwd(cwd, sizeof cwd) ? cwd : "/");
    const char *dl = getenv("XYZLCU_DELAY");
    if (dl && *dl) { char *end; long v = strtol(dl, &end, 10); if (!*end) { char t[32]; snprintf(t, sizeof t, ",\"delay\":%ld", v); bstr(&req, t); } }
    bstr(&req, ",\"env\":{");
    int first = 1;
    for (int i = 0; FORWARDED_ENV[i]; i++) {
        const char *v = getenv(FORWARDED_ENV[i]); if (!v) continue;
        if (!first) bstr(&req, ","); first = 0;
        bjson(&req, FORWARDED_ENV[i]); bstr(&req, ":"); bjson(&req, v);
    }
    bstr(&req, "}");
    buf_t in = {0};
    if (strcmp(cmd, "batch") == 0) {   // batch 没给脚本文件时从标准输入读
        int hasFile = 0;
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--continue-on-error") == 0) continue;
            if (strcmp(argv[i], "--delay") == 0) { i++; continue; }
            hasFile = 1;
        }
        if (!hasFile) {
            char tmp[65536]; ssize_t k;
            while ((k = read(0, tmp, sizeof tmp)) > 0) bput(&in, tmp, (size_t)k);
            bstr(&req, ",\"stdin\":"); bjson(&req, in.p ? in.p : "");
        }
    }
    bstr(&req, "}");
    if (write_all(fd, req.p, req.n) != 0) { fprintf(stderr, "error: 发送请求失败\n"); return 1; }
    shutdown(fd, SHUT_WR);

    buf_t r = {0};
    char tmp[262144]; ssize_t k;
    while ((k = read(fd, tmp, sizeof tmp)) > 0) bput(&r, tmp, (size_t)k);
    close(fd);
    const unsigned char *p = (const unsigned char *)r.p;
    if (r.n >= 20 && memcmp(p, "XYZ2", 4) == 0) {
        int32_t code = (int32_t)be32(p + 4);
        size_t off = 8, len[3]; const unsigned char *seg[3];
        for (int i = 0; i < 3; i++) {
            if (off + 4 > r.n) goto bad;
            len[i] = be32(p + off); off += 4;
            if (off + len[i] > r.n) goto bad;
            seg[i] = p + off; off += len[i];
        }
        fwrite(seg[0], 1, len[0], stdout);
        fwrite(seg[2], 1, len[2], stdout);
        fflush(stdout);
        fwrite(seg[1], 1, len[1], stderr);
        return code;
    }
    // JSON：98 = 版本不一致，自己执行（批处理的标准输入已经读掉了，转给主程序）
    if (r.n && strstr(r.p, "\"code\":98")) {
        if (in.p) {
            int pfd[2];
            if (pipe(pfd) == 0) {
                if (fork() == 0) { close(pfd[0]); write_all(pfd[1], in.p, in.n); _exit(0); }
                close(pfd[1]); dup2(pfd[0], 0); close(pfd[0]);
            }
        }
        exec_core();
    }
bad:
    fprintf(stderr, "error: 守护进程回复无法解析%s\n", r.n ? "" : "（没有回复，可能在执行中退出了）");
    return 1;
}
