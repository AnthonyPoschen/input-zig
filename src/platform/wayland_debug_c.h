#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <xkbcommon/xkbcommon.h>
#include <xdg-shell-client-protocol.h>

static inline void input_zig_wl_shm_release(struct wl_shm *shm) {
#ifdef WL_SHM_RELEASE_SINCE_VERSION
    wl_shm_release(shm);
#else
    wl_proxy_destroy((struct wl_proxy *)shm);
#endif
}
