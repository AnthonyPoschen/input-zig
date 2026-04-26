#include <wayland-client-protocol.h>

// 包装函数，强迫编译器生成 wl_shm_release 的非内联版本
void wl_shm_release_wrapper(struct wl_shm *shm) {
    wl_shm_release(shm);
}
