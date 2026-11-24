// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Compile-only compatibility probe. Never apply an old compiler's bytecode to
// the host kernel. The original library is an external test input, not shipped
// with Chromium. Keep profiles opaque; their private layout can change.
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void* CompilerSymbol(void* handle,
                            const char* library,
                            const char* name) {
  void* symbol = dlsym(handle, name);
  Dl_info origin = {0};
  char resolved[PATH_MAX];
  if (!symbol || !dladdr(symbol, &origin) || !origin.dli_fname ||
      !realpath(origin.dli_fname, resolved) || strcmp(resolved, library)) {
    fprintf(stderr, "Wrong or missing compiler symbol provider: %s\n", name);
    exit(4);
  }
  return symbol;
}

int main(int argc, char** argv) {
  if (argc < 3 || (argc - 3) % 2) {
    fprintf(stderr, "usage: probe LIBRARY PROFILE [KEY VALUE ...]\n");
    return 2;
  }
  char library[PATH_MAX];
  if (!realpath(argv[1], library)) {
    perror("compiler library");
    return 3;
  }
  void* handle = dlopen(library, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
  if (!handle) {
    fprintf(stderr, "dlopen: %s\n", dlerror());
    return 3;
  }
  void* (*create)(void) =
      CompilerSymbol(handle, library, "sandbox_create_params");
  int (*set)(void*, const char*, const char*) =
      CompilerSymbol(handle, library, "sandbox_set_param");
  void (*free_params)(void*) =
      CompilerSymbol(handle, library, "sandbox_free_params");
  void* (*compile)(const char*, void*, char**) =
      CompilerSymbol(handle, library, "sandbox_compile_string");
  void (*free_profile)(void*) =
      CompilerSymbol(handle, library, "sandbox_free_profile");
  // sandbox_free_error is exported by libSystem on Lion and by the host's
  // system library. This follows Seatbelt's actual libSystem import binding.
  void (*free_error)(char*) = dlsym(RTLD_DEFAULT, "sandbox_free_error");
  if (!free_error) {
    fprintf(stderr, "Missing system sandbox_free_error\n");
    return 4;
  }
  printf("compiler_library=%s\n", library);
  FILE* source = fopen(argv[2], "rb");
  if (!source || fseek(source, 0, SEEK_END)) {
    perror("profile");
    return 5;
  }
  long size = ftell(source);
  if (size < 1 || size > 16 * 1024 * 1024) {
    fprintf(stderr, "Invalid profile length\n");
    return 6;
  }
  rewind(source);
  char* text = calloc((size_t)size + 1, 1);
  if (!text || fread(text, 1, (size_t)size, source) != (size_t)size) {
    fprintf(stderr, "Cannot read profile\n");
    return 7;
  }
  fclose(source);
  void* parameters = create();
  if (!parameters) {
    return 8;
  }
  for (int i = 3; i < argc; i += 2) {
    if (set(parameters, argv[i], argv[i + 1])) {
      fprintf(stderr, "Invalid parameter: %s\n", argv[i]);
      return 9;
    }
  }
  char* error = NULL;
  void* profile = compile(text, parameters, &error);
  int result = profile ? 0 : 1;
  printf("compiled=%s error=%s\n", profile ? "yes" : "no",
         error ? error : "none");
  if (profile) {
    free_profile(profile);
  }
  if (error) {
    free_error(error);
  }
  free_params(parameters);
  free(text);
  dlclose(handle);
  return result;
}
