/* Manual physical-wheel acceptance probe. No simulated input.
 * Both normal Windows and RAWINPUT paths are counted independently. */
#include <windows.h>
static LONG legacy,raw,legacyEvents,rawEvents;
static HANDLE logFile=INVALID_HANDLE_VALUE;
static HWND window;
static void report(void) {
    WCHAR title[256];char utf8[1024];DWORD written;
    wsprintfW(title,L"COEditor 滚轮验证 — 普通 %ld / %ld 次；原始 %ld / %ld 次（左键清零，关闭结束）",legacy,legacyEvents,raw,rawEvents);
    SetWindowTextW(window,title);
    int n=WideCharToMultiByte(CP_UTF8,0,title,-1,utf8,sizeof(utf8),0,0);
    if(logFile!=INVALID_HANDLE_VALUE){WriteFile(logFile,utf8,n-1,&written,0);WriteFile(logFile,"\n",1,&written,0);FlushFileBuffers(logFile);}
}
static LRESULT CALLBACK proc(HWND h,UINT message,WPARAM w,LPARAM l) {
    switch(message) {
    case WM_MOUSEWHEEL:legacy+=(SHORT)HIWORD(w);legacyEvents++;report();return 0;
    case WM_INPUT: {
        RAWINPUT input;UINT size=sizeof(input);
        if(GetRawInputData((HRAWINPUT)l,RID_INPUT,&input,&size,sizeof(RAWINPUTHEADER))!=(UINT)-1 && input.header.dwType==RIM_TYPEMOUSE && (input.data.mouse.usButtonFlags&RI_MOUSE_WHEEL)) {
            raw+=(SHORT)input.data.mouse.usButtonData;rawEvents++;report();
        }
        break;
    }
    case WM_LBUTTONDOWN:legacy=raw=legacyEvents=rawEvents=0;report();return 0;
    case WM_TIMER:if(w==1){static unsigned seconds;if(++seconds>=180)DestroyWindow(h);}return 0;
    case WM_DESTROY:PostQuitMessage(0);return 0;
    }
    return DefWindowProcW(h,message,w,l);
}
void mainCRTStartup(void) {
    WNDCLASSW wc={0};MSG m;
    logFile=CreateFileW(L"C:\\.cx-wheel-validation.txt",GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    wc.lpfnWndProc=proc;wc.hInstance=GetModuleHandleW(0);wc.lpszClassName=L"COEditorWheelProbe";
    wc.hCursor=LoadCursorW(0,IDC_ARROW);wc.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);
    if(!RegisterClassW(&wc))ExitProcess(2);
    window=CreateWindowExW(0,wc.lpszClassName,L"COEditor 滚轮验证",WS_OVERLAPPEDWINDOW,100,100,1000,240,0,0,wc.hInstance,0);
    if(!window)ExitProcess(3);
    RAWINPUTDEVICE device={1,2,0,window};
    if(!RegisterRawInputDevices(&device,1,sizeof(device)))ExitProcess(4);
    ShowWindow(window,SW_SHOW);SetForegroundWindow(window);report();SetTimer(window,1,1000,0);
    while(GetMessageW(&m,0,0,0)>0){TranslateMessage(&m);DispatchMessageW(&m);}
    if(logFile!=INVALID_HANDLE_VALUE)CloseHandle(logFile);
    ExitProcess(0);
}
