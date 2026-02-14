#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>
#include <cmath>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kBackendWindowBoundsRegKey[] =
    L"Software\\ATLAS-Backend\\ATLAS-Backend-Flutter";
constexpr wchar_t kWindowBoundsRegValue[] = L"WindowBounds";
// Runner window position is persisted by Win32Window in win32_window.cpp.
// Keep this in sync so our first-launch sizing picks the same monitor that the
// runner will choose for DPI scaling.
constexpr wchar_t kRunnerWindowPlacementRegKey[] = L"Software\\ATLAS";
constexpr wchar_t kRunnerWindowPositionRegValue[] = L"WindowPosition";
constexpr wchar_t kRunnerLegacyWindowPlacementRegValue[] = L"WindowPlacement";

struct SavedWindowBounds {
  LONG x;
  LONG y;
  LONG width;
  LONG height;
};

Win32Window::Size DefaultWindowSizeForMonitor(HMONITOR monitor);

double GetScaleFactorForMonitor(HMONITOR monitor) {
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi == 0) {
    return 1.0;
  }
  return dpi / 96.0;
}

bool GetWorkAreaForMonitor(HMONITOR monitor, RECT* work_area) {
  if (work_area == nullptr) {
    return false;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return false;
  }

  *work_area = monitor_info.rcWork;
  return true;
}

int PhysicalToLogical(LONG physical, double scale_factor) {
  if (scale_factor <= 0.0) {
    return static_cast<int>(physical);
  }
  return static_cast<int>(std::lround(physical / scale_factor));
}

unsigned int PhysicalToLogicalUnsigned(LONG physical, double scale_factor) {
  if (scale_factor <= 0.0) {
    return static_cast<unsigned int>(std::max<LONG>(1, physical));
  }
  const auto logical = static_cast<long>(
      std::lround(static_cast<double>(physical) / scale_factor));
  return static_cast<unsigned int>(std::max<long>(1, logical));
}

void ClampPhysicalBoundsToWorkArea(const RECT& work_area,
                                  SavedWindowBounds* bounds) {
  if (bounds == nullptr) {
    return;
  }

  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) {
    return;
  }

  bounds->width = std::max<LONG>(1, bounds->width);
  bounds->height = std::max<LONG>(1, bounds->height);

  if (bounds->width > work_width) {
    bounds->width = work_width;
  }
  if (bounds->height > work_height) {
    bounds->height = work_height;
  }

  if (bounds->x < work_area.left) {
    bounds->x = work_area.left;
  }
  if (bounds->y < work_area.top) {
    bounds->y = work_area.top;
  }

  if (bounds->x + bounds->width > work_area.right) {
    bounds->x = work_area.right - bounds->width;
  }
  if (bounds->y + bounds->height > work_area.bottom) {
    bounds->y = work_area.bottom - bounds->height;
  }
}

bool LoadWindowBoundsFromKey(const wchar_t* reg_key, SavedWindowBounds* bounds) {
  if (reg_key == nullptr || bounds == nullptr) {
    return false;
  }

  SavedWindowBounds loaded{};
  DWORD loaded_size = sizeof(loaded);
  const LSTATUS status =
      RegGetValueW(HKEY_CURRENT_USER, reg_key, kWindowBoundsRegValue,
                   RRF_RT_REG_BINARY, nullptr, &loaded, &loaded_size);
  if (status != ERROR_SUCCESS || loaded_size != sizeof(loaded)) {
    return false;
  }
  if (loaded.width < 640 || loaded.height < 480) {
    return false;
  }

  *bounds = loaded;
  return true;
}

bool LoadWindowBounds(SavedWindowBounds* bounds) {
  // Only restore this application's own window bounds. Pulling bounds from
  // other apps makes the first-launch size depend on whether another ATLAS app
  // was installed and how it was last resized.
  return LoadWindowBoundsFromKey(kBackendWindowBoundsRegKey, bounds);
}

void ClearWindowBounds() {
  HKEY key = nullptr;
  const LSTATUS open_status = RegOpenKeyExW(
      HKEY_CURRENT_USER, kBackendWindowBoundsRegKey, 0, KEY_SET_VALUE, &key);
  if (open_status != ERROR_SUCCESS || key == nullptr) {
    return;
  }
  RegDeleteValueW(key, kWindowBoundsRegValue);
  RegCloseKey(key);
}

bool LoadRunnerPersistedWindowPosition(POINT* position_out) {
  if (!position_out) {
    return false;
  }

  POINT position{};
  DWORD data_size = sizeof(position);
  const LSTATUS result =
      RegGetValueW(HKEY_CURRENT_USER, kRunnerWindowPlacementRegKey,
                   kRunnerWindowPositionRegValue, RRF_RT_REG_BINARY, nullptr,
                   &position, &data_size);
  if (result != ERROR_SUCCESS || data_size != sizeof(position)) {
    WINDOWPLACEMENT legacy{};
    DWORD legacy_size = sizeof(legacy);
    const LSTATUS legacy_result =
        RegGetValueW(HKEY_CURRENT_USER, kRunnerWindowPlacementRegKey,
                     kRunnerLegacyWindowPlacementRegValue, RRF_RT_REG_BINARY,
                     nullptr, &legacy, &legacy_size);
    if (legacy_result != ERROR_SUCCESS || legacy_size != sizeof(legacy)) {
      return false;
    }
    position = POINT{legacy.rcNormalPosition.left, legacy.rcNormalPosition.top};
  }

  if (MonitorFromPoint(position, MONITOR_DEFAULTTONULL) == nullptr) {
    return false;
  }

  *position_out = position;
  return true;
}

bool ShouldDiscardWindowBounds(HMONITOR monitor,
                               const RECT& work_area,
                               const SavedWindowBounds& loaded_bounds,
                               const SavedWindowBounds& clamped_bounds) {
  if (monitor == nullptr) {
    return true;
  }

  // If the saved origin no longer points to a valid monitor (e.g. monitor
  // configuration changed), prefer resetting to defaults.
  const POINT restore_point{loaded_bounds.x, loaded_bounds.y};
  if (MonitorFromPoint(restore_point, MONITOR_DEFAULTTONULL) == nullptr) {
    return true;
  }

  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) {
    return true;
  }

  const auto abs_long = [](LONG value) -> LONG {
    return value < 0 ? -value : value;
  };

  // If we had to clamp the bounds heavily (meaning they no longer fit on the
  // current work area), treat them as stale/corrupt and reset.
  const LONG dx = abs_long(loaded_bounds.x - clamped_bounds.x);
  const LONG dy = abs_long(loaded_bounds.y - clamped_bounds.y);
  const LONG dw = abs_long(loaded_bounds.width - clamped_bounds.width);
  const LONG dh = abs_long(loaded_bounds.height - clamped_bounds.height);
  if (dx > work_width / 2 || dy > work_height / 2 || dw > work_width / 3 ||
      dh > work_height / 3) {
    return true;
  }

  // Guard against extreme aspect ratios that can happen with corrupted data.
  const LONG safe_height = std::max<LONG>(1, clamped_bounds.height);
  const double aspect =
      static_cast<double>(clamped_bounds.width) / static_cast<double>(safe_height);
  if (aspect < 0.45 || aspect > 3.2) {
    return true;
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const unsigned int logical_width =
      PhysicalToLogicalUnsigned(clamped_bounds.width, scale_factor);
  const unsigned int logical_height =
      PhysicalToLogicalUnsigned(clamped_bounds.height, scale_factor);

  // If the bounds look like the legacy first-launch default size, clear them so
  // updates can migrate users to the new adaptive default sizing.
  constexpr unsigned int kLegacyDefaultWidth = 1250;
  constexpr unsigned int kLegacyDefaultHeight = 1080;
  constexpr unsigned int kLegacyTolerance = 10;
  if (logical_width + kLegacyTolerance >= kLegacyDefaultWidth &&
      logical_width <= kLegacyDefaultWidth + kLegacyTolerance &&
      logical_height + kLegacyTolerance >= kLegacyDefaultHeight &&
      logical_height <= kLegacyDefaultHeight + kLegacyTolerance) {
    return true;
  }

  // Discard bounds that are dramatically smaller than what the monitor can
  // comfortably show. This catches "weird tiny window" cases from stale/corrupt
  // registry data without fighting normal user resizing.
  const Win32Window::Size default_size = DefaultWindowSizeForMonitor(monitor);
  constexpr double kMinFractionOfDefault = 0.50;
  if (logical_width <
          static_cast<unsigned int>(std::floor(default_size.width *
                                               kMinFractionOfDefault)) ||
      logical_height <
          static_cast<unsigned int>(std::floor(default_size.height *
                                               kMinFractionOfDefault))) {
    return true;
  }

  return false;
}

void SaveWindowBounds(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);

  RECT normal_rect{};
  if (GetWindowPlacement(hwnd, &placement)) {
    normal_rect = placement.rcNormalPosition;
  } else if (!GetWindowRect(hwnd, &normal_rect)) {
    return;
  }

  SavedWindowBounds bounds{
      normal_rect.left,
      normal_rect.top,
      normal_rect.right - normal_rect.left,
      normal_rect.bottom - normal_rect.top,
  };
  if (bounds.width < 100 || bounds.height < 100) {
    return;
  }

  HKEY key = nullptr;
  const LSTATUS open_status = RegCreateKeyExW(
      HKEY_CURRENT_USER, kBackendWindowBoundsRegKey, 0, nullptr, 0,
      KEY_SET_VALUE, nullptr, &key, nullptr);
  if (open_status != ERROR_SUCCESS || key == nullptr) {
    return;
  }

  RegSetValueExW(key, kWindowBoundsRegValue, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&bounds), sizeof(bounds));
  RegCloseKey(key);
}

Win32Window::Size DefaultWindowSizeForMonitor(HMONITOR monitor) {
  RECT work_area{};
  if (!GetWorkAreaForMonitor(monitor, &work_area)) {
    return Win32Window::Size(1250, 800);
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const double available_width =
      (work_area.right - work_area.left) / scale_factor;
  const double available_height =
      (work_area.bottom - work_area.top) / scale_factor;

  // Keep a small margin so the window doesn't exactly hug the work area.
  constexpr double kPadding = 32.0;
  const double max_width =
      std::max(1.0, std::floor(available_width - kPadding));
  const double max_height =
      std::max(1.0, std::floor(available_height - kPadding));

  // Choose a consistent first-launch size across machines by scaling from the
  // monitor work area rather than hardcoding a fixed pixel size.
  constexpr double kFillWidth = 0.92;
  constexpr double kFillHeight = 0.88;
  constexpr double kComfortMinWidth = 1200.0;
  constexpr double kComfortMinHeight = 740.0;

  double width = std::floor(max_width * kFillWidth);
  double height = std::floor(max_height * kFillHeight);

  const double min_width = std::min(kComfortMinWidth, max_width);
  const double min_height = std::min(kComfortMinHeight, max_height);
  if (width < min_width) width = min_width;
  if (height < min_height) height = min_height;

  unsigned int width_u =
      static_cast<unsigned int>(std::max(1.0, std::min(width, max_width)));
  unsigned int height_u =
      static_cast<unsigned int>(std::max(1.0, std::min(height, max_height)));

  if (width_u < 640 && max_width >= 640) {
    width_u = 640;
  }
  if (height_u < 480 && max_height >= 480) {
    height_u = 480;
  }

  return Win32Window::Size(width_u, height_u);
}

Win32Window::Size FitSizeToWorkArea(HMONITOR monitor,
                                    const Win32Window::Size& requested) {
  RECT work_area{};
  if (!GetWorkAreaForMonitor(monitor, &work_area)) {
    return requested;
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const double available_width =
      (work_area.right - work_area.left) / scale_factor;
  const double available_height =
      (work_area.bottom - work_area.top) / scale_factor;

  // Keep a small margin so the window doesn't exactly hug the work area.
  constexpr double kPadding = 32.0;
  const double max_width =
      std::max(1.0, std::floor(available_width - kPadding));
  const double max_height =
      std::max(1.0, std::floor(available_height - kPadding));

  unsigned int width =
      static_cast<unsigned int>(std::min<double>(requested.width, max_width));
  unsigned int height =
      static_cast<unsigned int>(std::min<double>(requested.height, max_height));

  if (width < 640 && max_width >= 640) {
    width = 640;
  }
  if (height < 480 && max_height >= 480) {
    height = 480;
  }

  return Win32Window::Size(width, height);
}

Win32Window::Point CenteredOrigin(HMONITOR monitor,
                                  const Win32Window::Size& logical_size) {
  RECT work_area{};
  if (!GetWorkAreaForMonitor(monitor, &work_area)) {
    return Win32Window::Point(50, 50);
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const double work_left = work_area.left / scale_factor;
  const double work_top = work_area.top / scale_factor;
  const double work_width =
      (work_area.right - work_area.left) / scale_factor;
  const double work_height =
      (work_area.bottom - work_area.top) / scale_factor;

  const double centered_x =
      work_left + (work_width - logical_size.width) / 2.0;
  const double centered_y =
      work_top + (work_height - logical_size.height) / 2.0;

  return Win32Window::Point(
      static_cast<int>(std::lround(centered_x)),
      static_cast<int>(std::lround(centered_y)));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Match Win32Window's monitor selection so the default logical size is
  // scaled for the same display the runner will use.
  POINT target_point{0, 0};
  if (!LoadRunnerPersistedWindowPosition(&target_point)) {
    POINT cursor_position{};
    if (GetCursorPos(&cursor_position)) {
      target_point = cursor_position;
    }
  }
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);

  const HMONITOR initial_monitor = monitor;
  Win32Window::Size size = DefaultWindowSizeForMonitor(initial_monitor);
  Win32Window::Point origin = CenteredOrigin(initial_monitor, size);
  SavedWindowBounds restored_bounds{};
  if (LoadWindowBounds(&restored_bounds)) {
    POINT restore_point{restored_bounds.x, restored_bounds.y};
    const SavedWindowBounds loaded_bounds = restored_bounds;
    const HMONITOR restored_monitor =
        MonitorFromPoint(restore_point, MONITOR_DEFAULTTONEAREST);

    RECT work_area{};
    if (GetWorkAreaForMonitor(restored_monitor, &work_area)) {
      ClampPhysicalBoundsToWorkArea(work_area, &restored_bounds);
      if (ShouldDiscardWindowBounds(restored_monitor, work_area, loaded_bounds,
                                   restored_bounds)) {
        ClearWindowBounds();
      } else {
        monitor = restored_monitor;
        const double scale_factor = GetScaleFactorForMonitor(monitor);
        origin = Win32Window::Point(
            PhysicalToLogical(restored_bounds.x, scale_factor),
            PhysicalToLogical(restored_bounds.y, scale_factor));
        size = Win32Window::Size(
            PhysicalToLogicalUnsigned(restored_bounds.width, scale_factor),
            PhysicalToLogicalUnsigned(restored_bounds.height, scale_factor));
        size = FitSizeToWorkArea(monitor, size);
      }
    }
  }

  if (!window.Create(L"ATLAS Backend", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  bool bounds_saved = false;
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    if (!bounds_saved && msg.message == WM_CLOSE &&
        msg.hwnd == window.GetHandle()) {
      SaveWindowBounds(window.GetHandle());
      bounds_saved = true;
    }
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (!bounds_saved) {
    SaveWindowBounds(window.GetHandle());
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
