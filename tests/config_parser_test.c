#include <assert.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
static const char *test_process="cs2.exe";
#define getprogname() test_process
#include "cx_tuner_config.h"
int main(void) {
 char dir[]="/private/tmp/cx-tuner-config-XXXXXX",path[4096],drive[4096];
 assert(mkdtemp(dir));snprintf(drive,sizeof(drive),"%s/drive_c",dir);assert(!mkdir(drive,0700));
 snprintf(path,sizeof(path),"%s/.cx-tuner.ini",drive);setenv("WINEPREFIX",dir,1);
 struct cx_tuner_settings t=cx_tuner_read();assert(!t.loaded);
 FILE *f=fopen(path,"w");assert(f);fputs("[CS2.EXE]\nqueue=1\ndrawables=2\nsync=1\n[global]\nmouse=1\nwheel=0\nqueue=3\nsync=0\ndrawables=3\n[other.exe]\nmouse=0\nwheel=1\nqueue=0\ndrawables=9\n",f);fclose(f);
 t=cx_tuner_read();assert(t.loaded && t.mouse==1 && t.wheel==0 && t.queue==1 && t.drawables==2 && t.sync==1);
 test_process="other.exe";t=cx_tuner_read();assert(t.mouse==0 && t.wheel==1 && t.queue==0 && t.drawables==3 && t.sync==0);
 test_process="steamwebhelper.exe";t=cx_tuner_read();assert(t.sync==-1 && t.drawables==0 && t.queue==0 && t.wheel==0);
 unlink(path);rmdir(drive);rmdir(dir);puts("PASS: native configuration, inheritance, input switches, invalid values and Steam graphics bypass");return 0;
}
