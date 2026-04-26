#include <wayland-client.h>
#include <wayland-client-protocol.h>

void wl_shm_release(struct wl_shm *shm) {
    struct wl_proxy *proxy = (struct wl_proxy *) shm;
    wl_proxy_marshal_flags(proxy,
        0,                              // WL_SHM_RELEASE 的 opcode 是 0
        NULL,
        wl_proxy_get_version(proxy),
        0);
}