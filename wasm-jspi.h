#ifndef WEE8_WASM_JSPI_H
#define WEE8_WASM_JSPI_H

#ifndef WASM_H
#include "wasm.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

// JS Promise Integration. All operations run on the store's owning thread.
// Keep the store alive until every call is completed or deleted.
// Each pending call owns its suspended stack independently.
typedef struct wasm_pending_call_t wasm_pending_call_t;
// Tests for V8's WebAssembly.SuspendError at a synchronous JSPI boundary.
WASM_API_EXTERN bool wasm_trap_is_suspend_error(const wasm_trap_t *);

// Bind plain scalar C imports as JS callbacks for calls from promising exports.
// wasm_instance_new selects this mode automatically for a suspending import.
// Other instances use the native C ABI by default.
WASM_API_EXTERN wasm_instance_t *
wasm_instance_new_with_jspi(wasm_store_t *, const wasm_module_t *,
                            const wasm_extern_vec_t *, wasm_trap_t **);

// A typed callback can set *pending to suspend. When pending is NULL the
// caller is synchronous and the callback must complete before returning.
typedef wasm_trap_t *(*wasm_async_callback_t)(const wasm_val_vec_t *args,
                                              wasm_val_vec_t *results,
                                              bool *pending);
typedef wasm_trap_t *(*wasm_async_callback_with_env_t)(
    void *env, const wasm_val_vec_t *args, wasm_val_vec_t *results,
    bool *pending);
// Returns NULL if JSPI is unavailable or a parameter or result is v128. On
// failure the caller retains env.
WASM_API_EXTERN wasm_func_t *wasm_func_new_suspending(wasm_store_t *,
                                                      const wasm_functype_t *,
                                                      wasm_async_callback_t);
WASM_API_EXTERN wasm_func_t *
wasm_func_new_suspending_with_env(wasm_store_t *, const wasm_functype_t *,
                                  wasm_async_callback_with_env_t, void *env,
                                  void (*finalizer)(void *));

// WebAssembly.promising(func). The reusable callable and each outstanding
// invocation own their handles independently. The store must outlive both.
typedef struct wasm_promising_func_t wasm_promising_func_t;
// A v128 parameter or result is rejected. Floating-point values crossing the
// JavaScript boundary follow JS Number conversions, including NaN handling.
// Synchronous guest re-entry into a suspending import traps before the
// callback. A synchronous C import with v128 parameters or results traps if
// entered from a secondary Wasm stack, before the host callback runs.
WASM_API_EXTERN wasm_promising_func_t *wasm_func_promising(const wasm_func_t *,
                                                           wasm_trap_t **error);
WASM_API_EXTERN void wasm_promising_func_delete(wasm_promising_func_t *);

// Vectors are borrowed for this turn. The caller provides one initialized
// result slot per export result. A pending turn leaves those slots untouched.
// A non-null call on success means suspension. NULL means completion.
// Resume accepts the suspended import's results or a borrowed trap. Invalid
// inputs and a suppressed checkpoint preserve the pending handle for retry.
// The call output is required. Resume requires a live pending call.
WASM_API_EXTERN wasm_trap_t *
wasm_promising_func_call(const wasm_promising_func_t *,
                         const wasm_val_vec_t *args, wasm_val_vec_t *results,
                         wasm_pending_call_t **);
WASM_API_EXTERN wasm_trap_t *
wasm_pending_call_resume(wasm_pending_call_t **,
                         const wasm_val_vec_t *host_results,
                         const wasm_trap_t *error, wasm_val_vec_t *results);
// Cancel a pending call. Its stack unwinds at the next allowed checkpoint.
WASM_API_EXTERN void wasm_pending_call_delete(wasm_pending_call_t *);

#ifdef __cplusplus
}
#endif
#endif
