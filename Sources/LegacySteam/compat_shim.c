#define _DARWIN_C_SOURCE
#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <limits.h>
#include "windef.h"
#include "winternl.h"

#include "steam_cef.h"
static void *vendor_handle;
static WCHAR *retained_command;
static void note(const char *prefix,const char *message)
{
    char path[PATH_MAX];FILE *file;
    if(snprintf(path,sizeof(path),"%s/drive_c/ProgramData/CrossOverSteamUI/compat-shim.log",prefix)>=(int)sizeof(path))return;
    if((file=fopen(path,"a"))){fprintf(file,"pid=%d %s\n",getpid(),message);fclose(file);}
}
static int is_helper(const UNICODE_STRING *path)
{
    static const char expected[]="steamwebhelper.exe";
    const WCHAR *base=path->Buffer,*end=base+path->Length/sizeof(WCHAR),*p;size_t i;
    for(p=base;p<end;p++)if(*p=='\\'||*p=='/')base=p+1;
    if(end-base!=sizeof(expected)-1)return 0;
    for(i=0;i<sizeof(expected)-1;i++){WCHAR ch=base[i];if(ch>='A'&&ch<='Z')ch+='a'-'A';if(ch!=(unsigned char)expected[i])return 0;}
    return 1;
}
__attribute__((constructor)) static void compat_entry(void)
{
    Dl_info location;char vendor_path[PATH_MAX],mode_path[PATH_MAX],mode[32]={0};char *slash;const char *prefix=getenv("WINEPREFIX");
    RTL_USER_PROCESS_PARAMETERS *parameters;TEB *teb;FILE *file;size_t chars,bytes;int backend;
    /* Always preserve all vendor rules, including their game-specific hooks. */
    if(!dladdr((void*)compat_entry,&location) || !location.dli_fname)return;
    if(snprintf(vendor_path,sizeof(vendor_path),"%s",location.dli_fname)>=(int)sizeof(vendor_path))return;
    slash=strrchr(vendor_path,'/');if(!slash)return;
    if((size_t)(slash-vendor_path)+sizeof("/cxcompatdb.vendor.so")>sizeof(vendor_path))return;
    strcpy(slash,"/cxcompatdb.vendor.so");vendor_handle=dlopen(vendor_path,RTLD_NOW|RTLD_LOCAL);
    if(!vendor_handle){if(prefix)note(prefix,"vendor-library-load-failed");return;}
    if(!prefix)return;
    if(snprintf(mode_path,sizeof(mode_path),"%s/drive_c/ProgramData/CrossOverSteamUI/mode.txt",prefix)>=(int)sizeof(mode_path))return;
    if(!(file=fopen(mode_path,"r")))return;
    if(!fgets(mode,sizeof(mode),file)){fclose(file);return;}fclose(file);
    mode[strcspn(mode,"\r\n")]=0;
    if(!strcmp(mode,"d3d11"))backend=0;
    else if(!strcmp(mode,"opengl"))backend=1;
    else return;
    teb=NtCurrentTeb();if(!teb || !teb->Peb || !(parameters=teb->Peb->ProcessParameters) || !is_helper(&parameters->ImagePathName))return;
    chars=parameters->CommandLine.Length/sizeof(WCHAR);bytes=(chars+256)*sizeof(WCHAR);
    if(bytes>65534 || !(retained_command=malloc(bytes)))return;
    cx_cef_gpu_command(parameters->CommandLine.Buffer,retained_command,backend);
    chars=0;while(retained_command[chars])chars++;
    if(chars>32765){free(retained_command);retained_command=NULL;return;}
    parameters->CommandLine.Buffer=retained_command;
    parameters->CommandLine.Length=chars*sizeof(WCHAR);
    parameters->CommandLine.MaximumLength=(chars+1)*sizeof(WCHAR);
    note(prefix,backend?"steamwebhelper opengl parameters applied":"steamwebhelper d3d11 parameters applied");
}
