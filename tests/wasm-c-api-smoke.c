#include <assert.h>

#include "wasm.h"

int wasm_c_api_smoke(void) {
  // (module (func (export "f") (result i32) i32.const 42))
  wasm_byte_t bytes[] = {
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
      0x03, 0x02, 0x01, 0x00,
      0x07, 0x05, 0x01, 0x01, 0x66, 0x00, 0x00,
      0x0a, 0x06, 0x01, 0x04, 0x00, 0x41, 0x2a, 0x0b,
  };
  wasm_byte_vec_t binary = WASM_ARRAY_VEC(bytes);
  wasm_engine_t *engine = wasm_engine_new();
  assert(engine);
  wasm_store_t *store = wasm_store_new(engine);
  assert(store);
  wasm_module_t *module = wasm_module_new(store, &binary);
  assert(module);

  wasm_extern_vec_t imports = WASM_EMPTY_VEC;
  wasm_instance_t *instance = wasm_instance_new(store, module, &imports, NULL);
  assert(instance);
  wasm_extern_vec_t exports;
  wasm_instance_exports(instance, &exports);
  assert(exports.size == 1);
  wasm_func_t *func = wasm_extern_as_func(exports.data[0]);
  assert(func);

  wasm_val_vec_t args = WASM_EMPTY_VEC;
  wasm_val_t result[] = {WASM_INIT_VAL};
  wasm_val_vec_t results = WASM_ARRAY_VEC(result);
  wasm_trap_t *trap = wasm_func_call(func, &args, &results);
  assert(!trap);
  assert(result[0].kind == WASM_I32 && result[0].of.i32 == 42);

  wasm_extern_vec_delete(&exports);
  wasm_instance_delete(instance);
  wasm_module_delete(module);
  wasm_store_delete(store);
  wasm_engine_delete(engine);
  return 0;
}
