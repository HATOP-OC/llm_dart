#ifndef LLAMA_BINDINGS_H
#define LLAMA_BINDINGS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Структури для взаємодії з Dart через FFI
typedef struct {
    int64_t handle;
} llama_dart_context;

typedef struct {
    int32_t maxTokens;
    int32_t contextLength;
    float temperature;
    float topP;
    float topK;              // ДОДАНО
    float repeatPenalty;     // ДОДАНО
    int32_t seed;
    double frequencyPenalty;
    double presencePenalty;
} llama_dart_inference_params;

typedef struct {
    int32_t* tokens;
    int32_t nTokens;
} llama_dart_tokens;

typedef struct {
    int32_t nGpuLayers;
    int32_t quantizationType;
    int32_t seed;
    int32_t nThreads;
    int32_t nBatch;
} llama_dart_model_params;

// Колбек для звітування про прогрес
typedef void (*llama_dart_progress_callback)(int32_t token_id, const char* piece);

// Публічні функції для Dart FFI
int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params);
llama_dart_context* llama_dart_create_context(int32_t model_id);
llama_dart_tokens* llama_dart_tokenize(llama_dart_context* ctx, const char* text);
char* llama_dart_generate(llama_dart_context* ctx, llama_dart_tokens* tokens, llama_dart_inference_params* params);
void llama_dart_free_context(llama_dart_context* ctx);
void llama_dart_free_tokens(llama_dart_tokens* tokens);
void llama_dart_free_string(char* str);
void llama_dart_set_progress_callback(llama_dart_progress_callback callback);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BINDINGS_H