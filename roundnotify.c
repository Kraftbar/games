/* roundnotify.c
 * Version: v1.2.0 (2026-01-04)
 *
 * Purpose:
 * - Listen on 127.0.0.1:3000 for CS2/CS:GO GSI HTTP POST JSON.
 * - Detect "new round starts" by watching round.phase transition -> "freezetime".
 *   (This is the earliest moment of the new round: spawn + buy time.)
 *
 * Build (MSVC):  cl /O2 /W3 roundnotify.c /link ws2_32.lib user32.lib
 * Build (MinGW): gcc -O2 -Wall roundnotify.c -o roundnotify.exe -lws2_32 -luser32
 */

#define _CRT_SECURE_NO_WARNINGS
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>

#pragma comment(lib, "Ws2_32.lib")

static void flash_cs_window(void) {
    const char* candidates[] = {
        "Counter-Strike 2",
        "Counter-Strike: Global Offensive",
        "Counter-Strike"
    };

    HWND h = NULL;
    for (int i = 0; i < (int)(sizeof(candidates)/sizeof(candidates[0])); i++) {
        h = FindWindowA(NULL, candidates[i]);
        if (h) break;
    }
    if (!h) h = GetForegroundWindow();

    if (h) {
        FLASHWINFO fw = {0};
        fw.cbSize = sizeof(fw);
        fw.hwnd = h;
        fw.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
        fw.uCount = 6;
        fw.dwTimeout = 0;
        FlashWindowEx(&fw);
    }
}

static void notify_user(void) {
    // Guaranteed attempt via speaker/audio device
    if (!Beep(880, 200)) {
        printf("Beep() failed, GetLastError=%lu\n", GetLastError());
    }
    flash_cs_window();
}


static int find_header_end(const char* buf, int len) {
    for (int i = 0; i + 3 < len; i++) {
        if (buf[i] == '\r' && buf[i+1] == '\n' && buf[i+2] == '\r' && buf[i+3] == '\n')
            return i + 4;
    }
    return -1;
}

static int parse_content_length(const char* headers) {
    // Very small/forgiving parser for "Content-Length: N"
    const char* p = headers;
    while (*p) {
        const char* line_end = strstr(p, "\r\n");
        if (!line_end) break;

        if (_strnicmp(p, "Content-Length:", 15) == 0) {
            p += 15;
            while (*p && isspace((unsigned char)*p)) p++;
            return atoi(p);
        }
        p = line_end + 2;
    }
    return -1;
}

static int extract_round_phase(const char* json, char* out, size_t out_sz) {
    // Find the "round" object first, then find "phase" within it.
    const char* r = strstr(json, "\"round\"");
    if (!r) return 0;

    // Find the opening brace of round object
    r = strchr(r, '{');
    if (!r) return 0;

    // Search for "phase" after that
    const char* p = strstr(r, "\"phase\"");
    if (!p) return 0;

    p = strchr(p, ':');
    if (!p) return 0;
    p++;

    while (*p && isspace((unsigned char)*p)) p++;
    if (*p != '"') return 0;
    p++;

    size_t i = 0;
    while (*p && *p != '"' && i + 1 < out_sz) out[i++] = *p++;
    out[i] = '\0';

    return (*p == '"') ? 1 : 0;
}

int main(void) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2,2), &wsa) != 0) {
        fprintf(stderr, "WSAStartup failed\n");
        return 1;
    }

    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) {
        fprintf(stderr, "socket() failed\n");
        WSACleanup();
        return 1;
    }

    int opt = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(3000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) {
        fprintf(stderr, "bind() failed (port 3000 in use?)\n");
        closesocket(s);
        WSACleanup();
        return 1;
    }

    if (listen(s, 16) == SOCKET_ERROR) {
        fprintf(stderr, "listen() failed\n");
        closesocket(s);
        WSACleanup();
        return 1;
    }

    printf("RoundNotify listening on http://127.0.0.1:3000\n");

    char last_phase[32] = {0};

    for (;;) {
        SOCKET c = accept(s, NULL, NULL);
        if (c == INVALID_SOCKET) continue;

        // Read headers first (up to a reasonable cap)
        char buf[131072];
        int total = 0;

        while (total < (int)sizeof(buf) - 1) {
            int r = recv(c, buf + total, (int)sizeof(buf) - 1 - total, 0);
            if (r <= 0) break;
            total += r;
            buf[total] = '\0';

            int hdr_end = find_header_end(buf, total);
            if (hdr_end >= 0) {
                int content_len = parse_content_length(buf);
                if (content_len < 0) content_len = 0;

                // Ensure we have full body
                int have_body = total - hdr_end;
                while (have_body < content_len && total < (int)sizeof(buf) - 1) {
                    int rr = recv(c, buf + total, (int)sizeof(buf) - 1 - total, 0);
                    if (rr <= 0) break;
                    total += rr;
                    buf[total] = '\0';
                    have_body = total - hdr_end;
                }
                break;
            }
        }

        // Respond OK so CS keeps sending
        const char* resp =
            "HTTP/1.1 200 OK\r\n"
            "Content-Length: 2\r\n"
            "Connection: close\r\n"
            "\r\n"
            "OK";
        send(c, resp, (int)strlen(resp), 0);
        closesocket(c);

        int hdr_end = find_header_end(buf, total);
        if (hdr_end < 0) continue;

        const char* body = buf + hdr_end;

        char phase[32] = {0};
        if (!extract_round_phase(body, phase, sizeof(phase))) {
            // No round.phase in this packet; ignore (warmup/map-only packets etc.)
            continue;
        }

        printf("round.phase=%s\n", phase);

        // NEW ROUND STARTS: transition into freezetime
        if (strcmp(phase, "freezetime") == 0 && strcmp(last_phase, "freezetime") != 0) {
            notify_user();
            printf(">>> NOTIFY (new round started: freezetime)\n");
        }

        strncpy(last_phase, phase, sizeof(last_phase)-1);
        last_phase[sizeof(last_phase)-1] = '\0';
    }
}
