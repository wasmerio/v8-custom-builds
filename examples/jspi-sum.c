// Compile as C11 and link against a JSPI-enabled wee8 distribution.
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "wasm.h"

typedef struct {
  int32_t a, b;
} sum_request;

static wasm_trap_t* sum(void* env, const wasm_val_vec_t* args,
                        wasm_val_vec_t* results, bool* pending) {
  sum_request* request = env;
  request->a = args->data[0].of.i32;
  request->b = args->data[1].of.i32;
  if (pending) {
    *pending = true;
  } else {
    results->data[0] = (wasm_val_t)WASM_I32_VAL(request->a + request->b);
  }
  return NULL;
}

// (module
//   (import "env" "sum" (func $sum (param i32 i32) (result i32)))
//   (func (export "run") (result i32) i32.const 40 i32.const 2 call $sum))
static const unsigned char binary[] = {
    0,   97,  115, 109, 1, 0,   0, 0,  1,  11, 2,   96,  2,   127, 127,
    1,   127, 96,  0,   1, 127, 2, 11, 1,  3,  'e', 'n', 'v', 3,   's',
    'u', 'm', 0,   0,   3, 2,   1, 1,  7,  7,  1,   3,   'r', 'u', 'n',
    0,   1,   10,  10,  1, 8,   0, 65, 40, 65, 2,   16,  0,   11};

int main(void) {
  wasm_engine_t* engine = wasm_engine_new();
  wasm_store_t* store = wasm_store_new(engine);
  wasm_byte_vec_t bytes;
  wasm_byte_vec_new(&bytes, sizeof(binary), (const wasm_byte_t*)binary);
  wasm_module_t* module = wasm_module_new(store, &bytes);
  wasm_byte_vec_delete(&bytes);
  if (!module) {
    wasm_store_delete(store);
    wasm_engine_delete(engine);
    return EXIT_FAILURE;
  }

  sum_request request = {0};
  wasm_functype_t* type = wasm_functype_new_2_1(
      wasm_valtype_new_i32(), wasm_valtype_new_i32(), wasm_valtype_new_i32());
  wasm_func_t* host =
      wasm_func_new_suspending(store, type, sum, &request, NULL);
  wasm_functype_delete(type);
  wasm_extern_t* import_items[] = {wasm_func_as_extern(host)};
  wasm_extern_vec_t imports = {1, import_items};
  wasm_trap_t* trap = NULL;
  wasm_instance_t* instance = wasm_instance_new(store, module, &imports, &trap);
  wasm_extern_vec_t exports = WASM_EMPTY_VEC;
  wasm_promising_func_t* run = NULL;
  wasm_jspi_call_t* call = NULL;
  wasm_val_t answer = WASM_I32_VAL(0);
  wasm_val_vec_t results = {1, &answer};
  int status = EXIT_FAILURE;
  if (!instance) goto done;
  wasm_instance_exports(instance, &exports);
  run = wasm_func_promising(wasm_extern_as_func(exports.data[0]), &trap);
  if (!run) goto done;

  wasm_val_vec_t args = WASM_EMPTY_VEC;
  trap = wasm_promising_func_call(run, &args, &results, &call);
  if (trap || !call) goto done;

  // The guest is suspended. An event loop would deliver this completion.
  wasm_val_t value = WASM_I32_VAL(request.a + request.b);
  wasm_val_vec_t completed = {1, &value};
  trap = wasm_jspi_call_resume(&call, &completed, NULL, &results);
  if (!trap && !call && answer.of.i32 == 42) {
    printf("%" PRId32 "\n", answer.of.i32);
    status = EXIT_SUCCESS;
  }

done:
  if (trap) {
    wasm_message_t message;
    wasm_trap_message(trap, &message);
    fprintf(stderr, "%.*s\n", (int)message.size, message.data);
    wasm_byte_vec_delete(&message);
    wasm_trap_delete(trap);
  }
  wasm_jspi_call_delete(call);
  wasm_promising_func_delete(run);
  wasm_extern_vec_delete(&exports);
  if (instance) wasm_instance_delete(instance);
  wasm_func_delete(host);
  wasm_module_delete(module);
  wasm_store_delete(store);
  wasm_engine_delete(engine);
  return status;
}
