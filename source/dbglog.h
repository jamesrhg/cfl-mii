#pragma once

#include <stdbool.h>

void dbglog_open(void);

void dbglog_close(void);

void dbglog(const char* fmt, ...);

void dbglog_err(const char* fmt, ...);

void dbglog_vram_stats(const char* context, bool onScreen);

