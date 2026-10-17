#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

typedef HRESULT (WINAPI *create_swap_fn)(IDXGIAdapter*,D3D_DRIVER_TYPE,HMODULE,UINT,const D3D_FEATURE_LEVEL*,UINT,UINT,const DXGI_SWAP_CHAIN_DESC*,IDXGISwapChain**,ID3D11Device**,D3D_FEATURE_LEVEL*,ID3D11DeviceContext**);
typedef HRESULT (WINAPI *create_device_fn)(IDXGIAdapter*,D3D_DRIVER_TYPE,HMODULE,UINT,const D3D_FEATURE_LEVEL*,UINT,UINT,ID3D11Device**,D3D_FEATURE_LEVEL*,ID3D11DeviceContext**);
static const GUID device1_iid={0x77db970f,0x6276,0x48ba,{0xba,0x28,0x07,0x01,0x43,0xb4,0x39,0x2c}};
static const GUID factory_iid={0x7b7166ec,0x21c7,0x44ae,{0xb2,0x1a,0xc9,0xae,0x32,0x1a,0xe3,0x69}};
static WNDCLASSW wc;
static DXGI_SWAP_CHAIN_DESC desc;
static const GUID texture_iid = {0x6f15aaf2,0xd208,0x4e89,{0x9a,0xb4,0x48,0x95,0x35,0xd3,0x4f,0x9c}};

void mainCRTStartup(void)
{
    HWND window;
    static WCHAR library[2048];
    HMODULE module;
    create_swap_fn create_swap;
    IDXGISwapChain *swap;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    ID3D11Texture2D *texture;
    ID3D11RenderTargetView *target;
    D3D_FEATURE_LEVEL level;
    MSG msg;
    float color[4] = {0.03f,0.05f,0.08f,1.0f};
    int frame;
    WCHAR interval_env[3];
    UINT sync_interval = 1;
    BOOL resize = GetEnvironmentVariableW(L"CX_PROBE_RESIZE",interval_env,3) && interval_env[0]==L'1';
    if (GetEnvironmentVariableW(L"CX_PROBE_SYNC_INTERVAL",interval_env,3) && interval_env[0]==L'0')
        sync_interval=0;
    if(!GetEnvironmentVariableW(L"CX_PROBE_DLL",library,2048)) ExitProcess(20);
    { static WCHAR value[2048];static char out[4096];DWORD written;
      const WCHAR *names[]={L"CX_GRAPHICS_BACKEND",L"CX_ACTIVE_GRAPHICS_BACKEND",L"CX_ROOT",L"WINEDLLPATH",L"WINEDLLOVERRIDES"};
      for(UINT i=0;i<5;i++){if(GetEnvironmentVariableW(names[i],value,2048)){int n=WideCharToMultiByte(CP_UTF8,0,value,-1,out,sizeof(out),0,0);WriteFile(GetStdHandle(STD_ERROR_HANDLE),out,n-1,&written,0);WriteFile(GetStdHandle(STD_ERROR_HANDLE),"\n",1,&written,0);}}
    }
    module=LoadLibraryW(library); if(!module)ExitProcess(21);
    create_swap=(create_swap_fn)GetProcAddress(module,"D3D11CreateDeviceAndSwapChain"); if(!create_swap)ExitProcess(22);
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(0);
    wc.lpszClassName = L"CXFrameSyncProbe";
    if (!RegisterClassW(&wc)) ExitProcess(2);
    window=CreateWindowExW(0,wc.lpszClassName,L"Metal 同步补丁检查（自动关闭）",
        WS_OVERLAPPEDWINDOW,100,100,400,240,0,0,wc.hInstance,0);
    if (!window) ExitProcess(3);
    desc.BufferDesc.Width=400;desc.BufferDesc.Height=240;
    desc.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count=1;desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount=2;desc.OutputWindow=window;desc.Windowed=TRUE;
    if(GetEnvironmentVariableW(L"CX_PROBE_SEPARATE",interval_env,3) && interval_env[0]==L'1')
    {
        create_device_fn create_device=(create_device_fn)GetProcAddress(module,"D3D11CreateDevice");
        IDXGIDevice1 *dxgi;
        IDXGIAdapter *adapter;
        IDXGIFactory *factory;
        if(!create_device || FAILED(create_device(0,D3D_DRIVER_TYPE_HARDWARE,0,0,0,0,D3D11_SDK_VERSION,&device,&level,&context)))ExitProcess(30);
        if(FAILED(ID3D11Device_QueryInterface(device,&device1_iid,(void**)&dxgi)))ExitProcess(31);
        if(FAILED(IDXGIDevice1_GetAdapter(dxgi,&adapter)))ExitProcess(32);
        if(FAILED(IDXGIAdapter_GetParent(adapter,&factory_iid,(void**)&factory)))ExitProcess(33);
        if(FAILED(IDXGIFactory_CreateSwapChain(factory,(IUnknown*)device,&desc,&swap)))ExitProcess(34);
        IDXGIFactory_Release(factory);IDXGIAdapter_Release(adapter);IDXGIDevice1_Release(dxgi);
    }
    else if (FAILED(create_swap(0,D3D_DRIVER_TYPE_HARDWARE,0,0,0,0,
        D3D11_SDK_VERSION,&desc,&swap,&device,&level,&context))) ExitProcess(4);
    if (FAILED(IDXGISwapChain_GetBuffer(swap,0,&texture_iid,(void**)&texture))) ExitProcess(5);
    if (FAILED(ID3D11Device_CreateRenderTargetView(device,(ID3D11Resource*)texture,0,&target))) ExitProcess(6);
    ShowWindow(window,SW_SHOWNOACTIVATE);
    for(frame=0;frame<240;frame++)
    {
        if (resize && frame==120)
        {
            ID3D11RenderTargetView_Release(target);
            ID3D11Texture2D_Release(texture);
            SetWindowPos(window,0,0,0,480,280,SWP_NOMOVE|SWP_NOACTIVATE|SWP_NOZORDER);
            if (FAILED(IDXGISwapChain_ResizeBuffers(swap,2,480,280,DXGI_FORMAT_R8G8B8A8_UNORM,0))) ExitProcess(8);
            if (FAILED(IDXGISwapChain_GetBuffer(swap,0,&texture_iid,(void**)&texture))) ExitProcess(9);
            if (FAILED(ID3D11Device_CreateRenderTargetView(device,(ID3D11Resource*)texture,0,&target))) ExitProcess(10);
        }
        while(PeekMessageW(&msg,0,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageW(&msg);}
        ID3D11DeviceContext_ClearRenderTargetView(context,target,color);
        if(FAILED(IDXGISwapChain_Present(swap,sync_interval,0))) ExitProcess(7);
    }
    {
        IDXGIDevice1 *dxgi;UINT latency=0;
        if(FAILED(ID3D11Device_QueryInterface(device,&device1_iid,(void**)&dxgi)))ExitProcess(40);
        if(FAILED(IDXGIDevice1_GetMaximumFrameLatency(dxgi,&latency)))ExitProcess(41);
        if(GetEnvironmentVariableW(L"CX_PROBE_EXPECT_QUEUE",interval_env,3)) {
            UINT expected=0;for(WCHAR *at=interval_env;*at;at++)expected=expected*10+(*at-L'0');
            if(latency!=expected)ExitProcess(42);
        }
        IDXGIDevice1_Release(dxgi);
    }
    ID3D11RenderTargetView_Release(target);
    ID3D11Texture2D_Release(texture);
    ID3D11DeviceContext_Release(context);
    IDXGISwapChain_Release(swap);
    ID3D11Device_Release(device);
    DestroyWindow(window);
    ExitProcess(0);
}
