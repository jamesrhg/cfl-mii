#include "dbglog.h"
#include <stdio.h>
#include <stdarg.h>
#include <3ds.h>

static FILE* s_log = NULL;

void dbglog_open(void)
{
	s_log = fopen("sdmc:/3ds/cfl_test.txt", "w");
}

void dbglog_close(void)
{
	if (s_log) {
		fclose(s_log);
		s_log = NULL;
	}
}

void dbglog(const char* fmt, ...)
{
	if (!s_log) return;
	va_list ap;
	va_start(ap, fmt);
	vfprintf(s_log, fmt, ap);
	va_end(ap);
}

void dbglog_err(const char* fmt, ...)
{
	va_list ap;
	if (s_log) {
		va_start(ap, fmt);
		vfprintf(s_log, fmt, ap);
		va_end(ap);
	}
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
}

void dbglog_vram_stats(const char* context, bool onScreen)
{
	u32 free = vramSpaceFree();
	if (onScreen)
		dbglog_err("%s: VRAM free = %lu bytes (%.1f KB)\n", context, (unsigned long)free, free / 1024.0f);
	else
		dbglog("%s: VRAM free = %lu bytes (%.1f KB)\n", context, (unsigned long)free, free / 1024.0f);
}

