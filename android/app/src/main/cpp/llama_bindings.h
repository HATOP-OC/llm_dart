#ifndef LLAMA_BINDINGS_H
#define LLAMA_BINDINGS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Callback типи для async операцій
typedef void (*GenerationCallback)(const char* chunk, bool is_final, const char* error);
typedef int64_t Dart_Port;

// Структура параметрів моделі
typedef struct {
    int32_t nGpuLayers;
    int32_t quantizationType;
    int32_t seed;
    int32_t nBatch;
} llama_dart_model_params;

// Структура параметрів контексту
typedef struct {
    int32_t nCtx;      // Розмір контексту (1024, 2048, etc.)
    int32_t nBatch;    // Batch size (рекомендовано 512)
    int32_t nThreads;  // Кількість потоків CPU
} llama_dart_context_params;

// Структура контексту
typedef struct {
    int64_t handle;
} llama_dart_context;

// Структура токенів
typedef struct {
    int32_t* tokens;
    int32_t nTokens;
} llama_dart_tokens;

// Структура параметрів інференсу
typedef struct {
    int32_t maxTokens;
    int32_t contextLength;
    float temperature;
    float topP;
    float topK;
    float repeatPenalty;
    int32_t seed;
    float frequencyPenalty;
    float presencePenalty;
    int32_t timeoutMs;        // NEW: timeout в мілісекундах (0 = без timeout)
    bool clearKvCache;        // NEW: чи очищати KV-cache (false для incremental)
} llama_dart_inference_params;

// ========== Синхронні API функції ==========
int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params);
llama_dart_context* llama_dart_create_context(int32_t model_id, llama_dart_context_params* params);
llama_dart_tokens* llama_dart_tokenize(llama_dart_context* ctx, const char* text);
char* llama_dart_generate(llama_dart_context* ctx, llama_dart_tokens* tokens, llama_dart_inference_params* params);
void llama_dart_free_context(llama_dart_context* ctx);
void llama_dart_free_model(int32_t model_id);
void llama_dart_free_tokens(llama_dart_tokens* tokens);
void llama_dart_free_string(char* str);

// ========== Async API функції (NEW) ==========
// Запускає генерацію в окремому потоці, результат надсилається через Dart_Port
void llama_dart_generate_async(
    llama_dart_context* ctx, 
    llama_dart_tokens* tokens, 
    llama_dart_inference_params* params,
    Dart_Port result_port
);

// Скасовує активну генерацію для контексту
void llama_dart_cancel_generation(llama_dart_context* ctx);

// Перевіряє чи генерація активна
bool llama_dart_is_generating(llama_dart_context* ctx);

// Очищає KV-cache для контексту
void llama_dart_clear_kv_cache(llama_dart_context* ctx);

// Отримує поточну позицію в KV-cache
int32_t llama_dart_get_kv_cache_pos(llama_dart_context* ctx);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BINDINGS_H