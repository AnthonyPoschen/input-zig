#include <wayland-client.h>
#include <wayland-client-protocol.h>

// 提供一个显式的 wl_shm_release 非内联实现
void wl_shm_release(struct wl_shm *shm) {
    struct wl_proxy *proxy = (struct wl_proxy *) shm;
    wl_proxy_marshal_flags(proxy, WL_SHM_RELEASE, NULL, wl_proxy_get_version(proxy), 0);
}
