/* Local D3D11 forwarding shim. Uses DXGI's device queue limit, not Metal's pool size. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

typedef HRESULT (WINAPI *create_device_fn)(IDXGIAdapter*,D3D_DRIVER_TYPE,HMODULE,UINT,
    const D3D_FEATURE_LEVEL*,UINT,UINT,ID3D11Device**,D3D_FEATURE_LEVEL*,ID3D11DeviceContext**);
typedef HRESULT (WINAPI *create_swap_fn)(IDXGIAdapter*,D3D_DRIVER_TYPE,HMODULE,UINT,
    const D3D_FEATURE_LEVEL*,UINT,UINT,const DXGI_SWAP_CHAIN_DESC*,IDXGISwapChain**,
    ID3D11Device**,D3D_FEATURE_LEVEL*,ID3D11DeviceContext**);
static const GUID device1_iid={0x77db970f,0x6276,0x48ba,{0xba,0x28,0x07,0x01,0x43,0xb4,0x39,0x2c}};
static INIT_ONCE once=INIT_ONCE_STATIC_INIT;
static HMODULE real_module;
static create_device_fn real_create;
static create_swap_fn real_swap;
extern IMAGE_DOS_HEADER __ImageBase;
static UINT queue_limit;

static void log_text(const char *text)
{
    DWORD length=0,written;
    HANDLE file;
    while(text[length])length++;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE),text,length,&written,0);
    /* Steam can detach the Windows stderr handle. Keep a tiny per-bottle log
     * so that game-side application of the API can still be checked. */
    file=CreateFileW(L"C:\\cx-queue.log",FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,
        0,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    if(file!=INVALID_HANDLE_VALUE){WriteFile(file,text,length,&written,0);CloseHandle(file);}
}

static BOOL CALLBACK initialize(PINIT_ONCE init,void *parameter,void **context)
{
    static WCHAR path[2048];
    DWORD n=GetEnvironmentVariableW(L"CX_D3D11_REAL_DLL",path,2048);
    if(!n || n>=2048){log_text("[CXQueue] missing real D3D11 path\n");return FALSE;}
    if(GetFileAttributesW(L"C:\\.cx-tuner.ini")!=INVALID_FILE_ATTRIBUTES)
    {
        static char exe[1024];static WCHAR full[1024];
        GetModuleFileNameW(0,full,1024);
        WCHAR *base=full;for(WCHAR *p=full;*p;p++)if(*p==L'\\' || *p==L'/')base=p+1;
        WideCharToMultiByte(CP_UTF8,0,base,-1,exe,sizeof(exe),0,0);
        int global=GetPrivateProfileIntA("global","queue",0,"C:\\.cx-tuner.ini");
        int selected=GetPrivateProfileIntA(exe,"queue",global,"C:\\.cx-tuner.ini");
        if(lstrcmpiA(exe,"steam.exe") && lstrcmpiA(exe,"steamwebhelper.exe") && lstrcmpiA(exe,"steamservice.exe"))
            queue_limit=selected>0 && selected<=16 ? selected : 0;
    }
    else
    {
        WCHAR value[8];DWORD length=GetEnvironmentVariableW(L"CX_D3D11_QUEUE_LIMIT",value,8);
        if(length && length<8 && value[0]>=L'1' && value[0]<=L'9' && !value[1])queue_limit=value[0]-L'0';
    }
    real_module=LoadLibraryW(path);
    if(!real_module){log_text("[CXQueue] real D3D11 load failed\n");return FALSE;}
    real_create=(create_device_fn)GetProcAddress(real_module,"D3D11CreateDevice");
    real_swap=(create_swap_fn)GetProcAddress(real_module,"D3D11CreateDeviceAndSwapChain");
    if(!real_create || !real_swap){log_text("[CXQueue] real exports missing\n");return FALSE;}
    log_text("[CXQueue] forwarding D3D11 to original D3DMetal\n");
    return TRUE;
}

static void limit_queue(ID3D11Device *device)
{
    IDXGIDevice1 *dxgi;
    UINT before=0,after=0;
    if(!device || !queue_limit)return;
    if(FAILED(ID3D11Device_QueryInterface(device,&device1_iid,(void**)&dxgi)))
    {log_text("[CXQueue] IDXGIDevice1 unavailable\n");return;}
    IDXGIDevice1_GetMaximumFrameLatency(dxgi,&before);
    if(SUCCEEDED(IDXGIDevice1_SetMaximumFrameLatency(dxgi,queue_limit)) &&
       SUCCEEDED(IDXGIDevice1_GetMaximumFrameLatency(dxgi,&after)) && after==queue_limit)
        { char line[]="[CXQueue] selected queue 00 verified\n";line[25]=(char)('0'+queue_limit/10);line[26]=(char)('0'+queue_limit%10);log_text(line); }
    else log_text("[CXQueue] device queue limit failed\n");
    IDXGIDevice1_Release(dxgi);
}

__declspec(dllexport) HRESULT WINAPI D3D11CreateDevice(IDXGIAdapter *adapter,D3D_DRIVER_TYPE type,
    HMODULE swrast,UINT flags,const D3D_FEATURE_LEVEL *levels,UINT count,UINT sdk,
    ID3D11Device **device,D3D_FEATURE_LEVEL *level,ID3D11DeviceContext **context)
{
    HRESULT hr;
    if(!InitOnceExecuteOnce(&once,initialize,0,0))return E_FAIL;
    hr=real_create(adapter,type,swrast,flags,levels,count,sdk,device,level,context);
    if(SUCCEEDED(hr)&&device)limit_queue(*device);
    return hr;
}

__declspec(dllexport) HRESULT WINAPI D3D11CreateDeviceAndSwapChain(IDXGIAdapter *adapter,
    D3D_DRIVER_TYPE type,HMODULE swrast,UINT flags,const D3D_FEATURE_LEVEL *levels,UINT count,
    UINT sdk,const DXGI_SWAP_CHAIN_DESC *desc,IDXGISwapChain **swap,ID3D11Device **device,
    D3D_FEATURE_LEVEL *level,ID3D11DeviceContext **context)
{
    HRESULT hr;
    if(!InitOnceExecuteOnce(&once,initialize,0,0))return E_FAIL;
    hr=real_swap(adapter,type,swrast,flags,levels,count,sdk,desc,swap,device,level,context);
    if(SUCCEEDED(hr)&&device)limit_queue(*device);
    return hr;
}

__declspec(dllexport) HRESULT WINAPI D3D11On12CreateDevice(IUnknown *device,UINT flags,
    const D3D_FEATURE_LEVEL *levels,UINT count,IUnknown *const *queues,UINT queue_count,
    UINT node_mask,ID3D11Device **result,ID3D11DeviceContext **context,D3D_FEATURE_LEVEL *level)
{
    typedef HRESULT (WINAPI *on12_fn)(IUnknown*,UINT,const D3D_FEATURE_LEVEL*,UINT,
        IUnknown *const*,UINT,UINT,ID3D11Device**,ID3D11DeviceContext**,D3D_FEATURE_LEVEL*);
    on12_fn fn;
    if(!InitOnceExecuteOnce(&once,initialize,0,0))return E_FAIL;
    fn=(on12_fn)GetProcAddress(real_module,"D3D11On12CreateDevice");
    return fn ? fn(device,flags,levels,count,queues,queue_count,node_mask,result,context,level) : E_NOTIMPL;
}
