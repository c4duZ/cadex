/* The Windows SDK the app uses, translated to the Zig module "sdk" by
 * ../../build.zig. The headers are mingw-w64's, shipped with Zig
 * (docs/adr/0012-windows-zig-win32-d3d11.md). CINTERFACE gives the COM
 * vtables in their exact order. Add a header here before using its API. */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#define UNICODE
#include <windows.h>
#include <windowsx.h>
#include <imm.h>
#include <dwmapi.h>
#include <shellscalingapi.h>
#include <d3d11.h>
#include <dxgi1_3.h>
#include <d2d1_1.h>
#include <dwrite_3.h>
