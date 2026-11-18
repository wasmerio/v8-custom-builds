// Exercise both instance binding modes through the packaged C API.
#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "wasm-jspi.h"

// (module (import "" "echo" (func (param f32) (result f32)))
//   (import "" "wait" (func (param f32) (result f32)))
//   (func (export "run") (result i32)
//     i32.const 0x7f800123 f32.reinterpret_i32 call 0 i32.reinterpret_f32))
static const uint8_t echo_module[] = {
    0,   97,  115, 109, 1,   0,   0,   0,   1,   10, 2,   96,  1,   125,
    1,   125, 96,  0,   1,   127, 2,   17,  2,   0,  4,   'e', 'c', 'h',
    'o', 0,   0,   0,   4,   'w', 'a', 'i', 't', 0,  0,   3,   2,   1,
    1,   7,   7,   1,   3,   'r', 'u', 'n', 0,   2,  10,  14,  1,   12,
    0,   65,  163, 130, 128, 252, 7,   190, 16,  0,  188, 11};

static int visits;

static wasm_trap_t* echo(const wasm_val_vec_t* args, wasm_val_vec_t* results) {
  ++visits;
  memcpy(&results->data[0], &args->data[0], sizeof(wasm_val_t));
  return NULL;
}

static wasm_trap_t* ready_echo(void* env, const wasm_val_vec_t* args,
                               wasm_val_vec_t* results, bool* pending) {
  (void)env;
  if (pending) *pending = false;
  return echo(args, results);
}

enum binding_mode { NATIVE, EXPLICIT_JSPI, IMPLICIT_JSPI };

static void check_binding(wasm_store_t* store, wasm_module_t* module,
                          const wasm_extern_vec_t* imports,
                          enum binding_mode mode) {
  wasm_instance_t* instance =
      mode == EXPLICIT_JSPI
          ? wasm_instance_new_with_jspi(store, module, imports, NULL)
          : wasm_instance_new(store, module, imports, NULL);
  assert(instance);
  wasm_extern_vec_t exports;
  wasm_instance_exports(instance, &exports);
  wasm_func_t* run = wasm_extern_as_func(exports.data[0]);
  const int32_t snan = 0x7f800123;
  wasm_val_t output = WASM_I32_VAL(0);
  wasm_val_vec_t args = WASM_EMPTY_VEC, results = {1, &output};
  visits = 0;
  wasm_trap_t* trap = wasm_func_call(run, &args, &results);
  assert(!trap && visits == 1);
  if (mode == NATIVE) assert(output.of.i32 == snan);

  wasm_promising_func_t* promising = wasm_func_promising(run, NULL);
  assert(promising);
  wasm_pending_call_t* pending = NULL;
  trap = wasm_promising_func_call(promising, &args, &results, &pending);
  assert(!pending);
  if (mode != NATIVE) {
    assert(!trap && visits == 2);
    assert((output.of.i32 & 0x7fffffff) > 0x7f800000);
  } else {
    assert(trap && visits == 1);
    wasm_trap_delete(trap);
  }
  wasm_promising_func_delete(promising);
  wasm_extern_vec_delete(&exports);
  wasm_instance_delete(instance);
}

int main(void) {
  wasm_engine_t* engine = wasm_engine_new();
  wasm_store_t* store = wasm_store_new(engine);
  wasm_byte_vec_t bytes;
  wasm_byte_vec_new(&bytes, sizeof(echo_module),
                    (const wasm_byte_t*)echo_module);
  wasm_module_t* module = wasm_module_new(store, &bytes);
  assert(module);
  wasm_functype_t* type =
      wasm_functype_new_1_1(wasm_valtype_new_f32(), wasm_valtype_new_f32());
  wasm_func_t* host = wasm_func_new(store, type, echo);
  wasm_extern_t* items[] = {wasm_func_as_extern(host),
                            wasm_func_as_extern(host)};
  wasm_extern_vec_t imports = {2, items};
  check_binding(store, module, &imports, NATIVE);
  check_binding(store, module, &imports, EXPLICIT_JSPI);
  wasm_func_t* suspending =
      wasm_func_new_suspending(store, type, ready_echo, NULL, NULL);
  assert(suspending);
  items[1] = wasm_func_as_extern(suspending);
  check_binding(store, module, &imports, IMPLICIT_JSPI);
  wasm_func_delete(suspending);
  wasm_func_delete(host);
  wasm_functype_delete(type);
  wasm_module_delete(module);
  wasm_byte_vec_delete(&bytes);
  wasm_store_delete(store);
  wasm_engine_delete(engine);
}
