#include <assert.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
static const char *test_process="cs2.exe";
#define getprogname() test_process
#include "cx_tuner_config.h"
static void check_fresh_process(const char *executable, const char *profile, const char *expected) {
 pid_t child=fork();assert(child>=0);
 if (!child) {execl(executable,executable,"--read",profile,expected,(char*)0);_exit(127);}
 int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status) && WEXITSTATUS(status)==0);
}
static void save_atomic(const char *path,const char *text) {
 char temp[4096];snprintf(temp,sizeof(temp),"%s.new",path);
 FILE *f=fopen(temp,"w");assert(f);assert(fputs(text,f)>=0);assert(!fclose(f));assert(!rename(temp,path));
}
int main(int argc,char **argv) {
 if(argc==4 && !strcmp(argv[1],"--read")) {
  test_process=argv[2];struct cx_tuner_settings t=cx_tuner_read();char actual[128];
  snprintf(actual,sizeof(actual),"%d,%d,%d,%d,%d,%d,%d,%d",t.mouse,t.wheel,t.sync,t.drawables,t.queue,t.fps,t.pacing,t.stats);
  if(!t.loaded || strcmp(actual,argv[3])) {fprintf(stderr,"profile %s: expected %s, got %s\n",test_process,argv[3],actual);return 1;}
  return 0;
 }
 char dir[]="/private/tmp/cx-tuner-config-XXXXXX",path[4096],drive[4096];
 assert(mkdtemp(dir));snprintf(drive,sizeof(drive),"%s/drive_c",dir);assert(!mkdir(drive,0700));
 snprintf(path,sizeof(path),"%s/.cx-tuner.ini",drive);setenv("WINEPREFIX",dir,1);
 struct cx_tuner_settings t=cx_tuner_read();assert(!t.loaded);
 FILE *f=fopen(path,"w");assert(f);fputs("[CS2.EXE]\nqueue=1\nfps=90\npacing=2\ndrawables=2\nsync=1\n[global]\nmouse=1\nwheel=0\nqueue=16\nfps=120\nstats=1\npacing=1\nsync=0\ndrawables=3\n[other.exe]\nmouse=0\nwheel=1\nqueue=0\ndrawables=9\n",f);fclose(f);
 t=cx_tuner_read();assert(t.loaded && t.mouse==1 && t.wheel==0 && t.queue==1 && t.drawables==2 && t.sync==1 && t.fps==90 && t.pacing==2 && t.stats==1);
 test_process="other.exe";t=cx_tuner_read();assert(t.mouse==0 && t.wheel==1 && t.queue==0 && t.drawables==3 && t.sync==0 && t.fps==120 && t.stats==1 && t.pacing==1);
 test_process="steamwebhelper.exe";t=cx_tuner_read();assert(t.sync==-1 && t.drawables==0 && t.queue==0 && t.wheel==0 && t.fps==0 && t.stats==0 && t.pacing==0);
 // Keep this launcher process alive while two newly exec'd game readers see atomic saves.
 pid_t launcher=getpid();
 save_atomic(path,"[global]\nmouse=1\nwheel=1\nsync=-1\ndrawables=0\nqueue=0\nfps=0\npacing=0\nstats=0\n[CS2.EXE]\nmouse=0\nwheel=0\nsync=0\ndrawables=2\nqueue=5\nfps=75\npacing=1\nstats=1\n");
 check_fresh_process(argv[0],"cs2.exe","0,0,0,2,5,75,1,1");
 save_atomic(path,"[cs2.exe]\nmouse=1\nwheel=1\nsync=1\ndrawables=3\nqueue=16\nfps=144\npacing=2\nstats=0\n[global]\nmouse=0\nwheel=0\nsync=0\ndrawables=2\nqueue=1\nfps=60\npacing=1\nstats=1\n");
 check_fresh_process(argv[0],"CS2.EXE","1,1,1,3,16,144,2,0");
 check_fresh_process(argv[0],"unlisted.exe","0,0,0,2,1,60,1,1");
 check_fresh_process(argv[0],"steam.exe","0,0,-1,0,0,0,0,0");
 assert(getpid()==launcher);
 puts("PASS: all eight parameters reloaded by fresh game processes after atomic saves, without restarting launcher");
 unlink(path);rmdir(drive);rmdir(dir);puts("PASS: native configuration, inheritance, input switches, invalid values and Steam graphics bypass");return 0;
}
