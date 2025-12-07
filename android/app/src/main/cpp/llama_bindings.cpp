#include "llama_bindings.h"
#include "llama.h"
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <android/log.h>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>
#include <condition_variable>

// Dart FFI для NativePort
#include "dart_api_dl.h"

#define LOG_TAG "LlamaBindings"
#define LOGI(... ) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ========== Глобальний стан ==========
static std::map<int32_t, llama_model*> g_models;
static std::map<int64_t, llama_context*> g_contexts;
static std::map<int64_t, int32_t> g_kv_cache_positions;  // NEW: позиція в KV-cache для кожного контексту
static std::map<int64_t, std::atomic<bool>> g_cancel_flags;  // NEW: флаги скасування
static std::map<int64_t, std::atomic<bool>> g_generating_flags;  // NEW: флаги активної генерації
static int32_t g_next_model_id = 1;
static int64_t g_next_context_id = 1;
static std::mutex g_mutex;
static std::mutex g_generation_mutex;  // Окремий mutex для генерації
static int g_generation_count = 0;

static const std::vector<std::string> STOP_SEQUENCES = {
    "User:", "\nUser:", "Human:", "\nHuman:",
    "Assistant:", "\nAssistant:",
    "<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>",
    "<|eot_id|>", "<|end|>", "</s>", "<|assistant|>", "<|user|>",
};

// ========== Helper функції ==========
static bool check_stop_sequence(const std::string& text) {
    for (const auto& stop : STOP_SEQUENCES) {
        if (text.length() >= stop.length()) {
            if (text.compare(text.length() - stop.length(), stop. length(), stop) == 0) {
                return true;
            }
        }
    }
    return false;
}

static std::string remove_stop_sequence(const std::string& text) {
    for (const auto& stop : STOP_SEQUENCES) {
        if (text.length() >= stop.length()) {
            if (text.compare(text. length() - stop. length(), stop.length(), stop) == 0) {
                return text.substr(0, text.length() - stop.length());
            }
        }
    }
    return text;
}

// Надсилає результат в Dart через NativePort
static void send_to_dart(Dart_Port port, const char* message, bool is_error) {
    if (port == 0) return;
    
    Dart_CObject obj;
    obj. type = Dart_CObject_kString;
    obj.value.as_string = const_cast<char*>(message);
    
    Dart_PostCObject_DL(port, &obj);
}

extern "C" {

// ========== Ініціалізація Dart API ==========
DART_EXPORT intptr_t InitDartApiDL(void* data) {
    return Dart_InitializeApiDL(data);
}

// ========== Завантаження моделі ==========
int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        LOGI("=== LOAD MODEL START ===");
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = params->nGpuLayers;
        model_params.use_mmap = true;
        model_params.use_mlock = false;
        
        LOGI("Loading model from: %s", path);
        
        llama_model* model = llama_model_load_from_file(path, model_params);
        if (!model) {
            LOGE("Failed to load model from: %s", path);
            return -1;
        }
        
        int32_t model_id = g_next_model_id++;
        g_models[model_id] = model;
        
        LOGI("Model loaded successfully with ID: %d", model_id);
        return model_id;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_load_model: %s", e.what());
        return -1;
    }
}

// ========== Створення контексту ==========
llama_dart_context* llama_dart_create_context(int32_t model_id, llama_dart_context_params* params) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        LOGI("=== CREATE CONTEXT START ===");
        auto it = g_models.find(model_id);
        if (it == g_models.end()) {
            LOGE("Model ID %d not found", model_id);
            return nullptr;
        }
        
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = params->nCtx > 0 ? params->nCtx : 2048;
        // ВИПРАВЛЕННЯ: n_batch = 512 для великих промптів
        ctx_params.n_batch = params->nBatch > 0 ?  params->nBatch : 512;
        ctx_params. n_threads = params->nThreads > 0 ? params->nThreads : 4;
        ctx_params.n_threads_batch = params->nThreads > 0 ? params->nThreads : 4;
        
        LOGI("Creating context: n_ctx=%d, n_batch=%d, n_threads=%d", 
             ctx_params.n_ctx, ctx_params.n_batch, ctx_params. n_threads);
        
        llama_context* ctx = llama_init_from_model(it->second, ctx_params);
        if (!ctx) {
            LOGE("Failed to create context for model %d", model_id);
            return nullptr;
        }
        
        int64_t context_id = g_next_context_id++;
        g_contexts[context_id] = ctx;
        g_kv_cache_positions[context_id] = 0;  // NEW: ініціалізуємо позицію
        g_cancel_flags[context_id]. store(false);
        g_generating_flags[context_id].store(false);
        
        llama_dart_context* dart_ctx = new llama_dart_context();
        dart_ctx->handle = context_id;
        
        g_generation_count = 0;
        
        LOGI("Context created with ID: %ld", context_id);
        return dart_ctx;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_create_context: %s", e.what());
        return nullptr;
    }
}

// ========== Токенізація ==========
llama_dart_tokens* llama_dart_tokenize(llama_dart_context* ctx, const char* text) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        if (!ctx || !text) {
            LOGE("Invalid parameters for tokenization");
            return nullptr;
        }
        
        auto it = g_contexts.find(ctx->handle);
        if (it == g_contexts.end()) {
            LOGE("Context handle %ld not found", ctx->handle);
            return nullptr;
        }
        
        llama_context* llama_ctx = it->second;
        const llama_model* model = llama_get_model(llama_ctx);
        const llama_vocab* vocab = llama_model_get_vocab(model);
        
        size_t text_len = strlen(text);
        int max_tokens = text_len * 2 + 256;
        std::vector<llama_token> tokens(max_tokens);
        
        int n_tokens = llama_tokenize(vocab, text, text_len, tokens. data(), max_tokens, true, false);
        
        if (n_tokens < 0) {
            max_tokens = -n_tokens;
            tokens.resize(max_tokens);
            n_tokens = llama_tokenize(vocab, text, text_len, tokens.data(), max_tokens, true, false);
        }
        
        if (n_tokens <= 0) {
            LOGE("Failed to tokenize text");
            n_tokens = 1;
            tokens[0] = llama_vocab_bos(vocab);
        }
        
        llama_dart_tokens* result = new llama_dart_tokens();
        result->nTokens = n_tokens;
        result->tokens = new int32_t[n_tokens];
        
        for (int i = 0; i < n_tokens; i++) {
            result->tokens[i] = tokens[i];
        }
        
        LOGI("Tokenized text into %d tokens", n_tokens);
        return result;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_tokenize: %s", e.what());
        return nullptr;
    }
}

// ========== ГОЛОВНЕ ВИПРАВЛЕННЯ: Генерація з chunked processing ==========
char* llama_dart_generate(llama_dart_context* ctx, llama_dart_tokens* tokens, llama_dart_inference_params* params) {
    // Використовуємо окремий mutex для генерації щоб не блокувати інші операції
    std::lock_guard<std::mutex> lock(g_generation_mutex);
    
    g_generation_count++;
    LOGI("========================================");
    LOGI("=== GENERATE START (call #%d) ===", g_generation_count);
    LOGI("========================================");
    
    try {
        if (! ctx || !tokens || !params) {
            LOGE("GENERATE: Invalid parameters");
            return nullptr;
        }
        
        llama_context* llama_ctx = nullptr;
        {
            std::lock_guard<std::mutex> state_lock(g_mutex);
            auto it = g_contexts.find(ctx->handle);
            if (it == g_contexts.end()) {
                LOGE("Context handle %ld not found", ctx->handle);
                return nullptr;
            }
            llama_ctx = it->second;
            g_generating_flags[ctx->handle].store(true);
            g_cancel_flags[ctx->handle].store(false);
        }
        
        if (!llama_ctx) {
            LOGE("GENERATE: llama_ctx is NULL");
            return nullptr;
        }
        
        const llama_model* model = llama_get_model(llama_ctx);
        if (!model) {
            LOGE("GENERATE: model is NULL");
            return nullptr;
        }
        
        const llama_vocab* vocab = llama_model_get_vocab(model);
        if (!vocab) {
            LOGE("GENERATE: vocab is NULL");
            return nullptr;
        }
        
        const int n_ctx = llama_n_ctx(llama_ctx);
        const int n_batch = llama_n_batch(llama_ctx);
        const int max_gen_tokens = std::min(params->maxTokens, 512);
        const int timeout_ms = params->timeoutMs > 0 ? params->timeoutMs : 60000;  // Default 60 sec
        
        LOGI("GENERATE: n_ctx=%d, n_batch=%d, input_tokens=%d, max_gen=%d, timeout=%dms", 
             n_ctx, n_batch, tokens->nTokens, max_gen_tokens, timeout_ms);
        
        auto start_time = std::chrono::steady_clock::now();
        
        // ========== ВИПРАВЛЕННЯ #7: Опціональне очищення KV-cache ==========
        bool clear_kv = params->clearKvCache;
        int kv_pos = 0;
        
        {
            std::lock_guard<std::mutex> state_lock(g_mutex);
            kv_pos = g_kv_cache_positions[ctx->handle];
        }
        
        if (clear_kv || kv_pos == 0) {
            LOGI("GENERATE: Clearing KV-cache.. .");
            llama_memory_t memory = llama_get_memory(llama_ctx);
            if (memory) {
                llama_memory_clear(memory, true);
                LOGI("GENERATE: KV-cache cleared");
            }
            kv_pos = 0;
        } else {
            LOGI("GENERATE: Using incremental KV-cache, current pos=%d", kv_pos);
        }
        
        // Перевіряємо кількість токенів
        int input_tokens_count = tokens->nTokens;
        if (input_tokens_count <= 0) {
            LOGE("GENERATE: No input tokens");
            char* error_msg = new char[64];
            strcpy(error_msg, "Error: No input tokens");
            g_generating_flags[ctx->handle].store(false);
            return error_msg;
        }
        
        // Обрізаємо якщо потрібно
        if (kv_pos + input_tokens_count + max_gen_tokens > n_ctx) {
            int max_input = n_ctx - max_gen_tokens - kv_pos - 64;
            if (max_input < 64) {
                // Треба очистити KV-cache
                LOGW("GENERATE: Context overflow, clearing KV-cache");
                llama_memory_t memory = llama_get_memory(llama_ctx);
                if (memory) {
                    llama_memory_clear(memory, true);
                }
                kv_pos = 0;
                max_input = n_ctx - max_gen_tokens - 64;
            }
            
            if (input_tokens_count > max_input) {
                LOGW("GENERATE: Truncating input from %d to %d tokens", input_tokens_count, max_input);
                input_tokens_count = max_input;
            }
        }
        
        std::string result_text;
        llama_sampler* sampler = nullptr;
        
        try {
            // Копіюємо токени
            std::vector<llama_token> input_tokens;
            input_tokens.reserve(input_tokens_count);
            int start_idx = tokens->nTokens - input_tokens_count;
            
            for (int i = start_idx; i < tokens->nTokens; i++) {
                input_tokens. push_back(tokens->tokens[i]);
            }
            
            LOGI("GENERATE: Processing %zu input tokens (start_idx=%d, kv_pos=%d)", 
                 input_tokens.size(), start_idx, kv_pos);
            
            // ========== ВИПРАВЛЕННЯ #2: CHUNKED BATCH PROCESSING ==========
            // Замість truncation, обробляємо великі промпти частинами
            int processed = 0;
            int current_pos = kv_pos;
            
            while (processed < (int)input_tokens.size()) {
                // Перевірка на cancel
                if (g_cancel_flags[ctx->handle].load()) {
                    LOGI("GENERATE: Cancelled during input processing");
                    g_generating_flags[ctx->handle].store(false);
                    char* msg = new char[32];
                    strcpy(msg, "Cancelled");
                    return msg;
                }
                
                // Перевірка timeout
                auto now = std::chrono::steady_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time).count();
                if (elapsed > timeout_ms) {
                    LOGE("GENERATE: Timeout during input processing (%ld ms)", elapsed);
                    g_generating_flags[ctx->handle].store(false);
                    char* msg = new char[64];
                    strcpy(msg, "Error: Timeout during processing");
                    return msg;
                }
                
                int chunk_size = std::min(n_batch, (int)input_tokens.size() - processed);
                
                llama_batch batch = llama_batch_init(chunk_size, 0, 1);
                
                for (int i = 0; i < chunk_size; i++) {
                    batch.token[i] = input_tokens[processed + i];
                    batch.pos[i] = current_pos + i;
                    batch.n_seq_id[i] = 1;
                    batch.seq_id[i][0] = 0;
                    batch.logits[i] = (processed + i == (int)input_tokens.size() - 1);
                }
                batch.n_tokens = chunk_size;
                
                LOGI("GENERATE: Decoding chunk %d-%d (pos %d-%d)", 
                     processed, processed + chunk_size - 1, 
                     current_pos, current_pos + chunk_size - 1);
                
                int ret = llama_decode(llama_ctx, batch);
                llama_batch_free(batch);
                
                if (ret != 0) {
                    LOGE("GENERATE: llama_decode failed with error %d at chunk starting %d", ret, processed);
                    g_generating_flags[ctx->handle].store(false);
                    char* msg = new char[64];
                    strcpy(msg, "Error: Decode failed");
                    return msg;
                }
                
                processed += chunk_size;
                current_pos += chunk_size;
            }
            
            LOGI("GENERATE: All input tokens processed, current_pos=%d", current_pos);
            
            // ========== Створення sampler ==========
            LOGI("GENERATE: Creating sampler.. .");
            llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
            sampler = llama_sampler_chain_init(sampler_params);
            
            if (!sampler) {
                LOGE("GENERATE: Failed to create sampler");
                g_generating_flags[ctx->handle].store(false);
                char* error_msg = new char[64];
                strcpy(error_msg, "Error: Failed to create sampler");
                return error_msg;
            }
            
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(params->temperature));
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int)params->topK));
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params->topP, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
                64, params->repeatPenalty, params->frequencyPenalty, params->presencePenalty
            ));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(params->seed));
            
            std::vector<llama_token> generated_tokens;
            generated_tokens.reserve(max_gen_tokens);
            
            int cur_pos = current_pos;
            
            LOGI("GENERATE: Starting generation loop (cur_pos=%d, max=%d)...", cur_pos, max_gen_tokens);
            
            // ========== Цикл генерації ==========
            for (int i = 0; i < max_gen_tokens; i++) {
                // Перевірка на cancel
                if (g_cancel_flags[ctx->handle].load()) {
                    LOGI("GENERATE: Cancelled at step %d", i);
                    break;
                }
                
                // Перевірка timeout
                auto now = std::chrono::steady_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start_time).count();
                if (elapsed > timeout_ms) {
                    LOGE("GENERATE: Timeout at step %d (%ld ms)", i, elapsed);
                    break;
                }
                
                llama_token next_token = llama_sampler_sample(sampler, llama_ctx, -1);
                
                if (llama_vocab_is_eog(vocab, next_token)) {
                    LOGI("GENERATE: EOG at step %d", i);
                    break;
                }
                
                generated_tokens.push_back(next_token);
                llama_sampler_accept(sampler, next_token);
                
                // Перевірка стоп-послідовностей кожні 10 токенів
                if ((i + 1) % 10 == 0 && ! generated_tokens.empty()) {
                    std::vector<char> temp_buffer(generated_tokens.size() * 10);
                    int temp_len = llama_detokenize(vocab, generated_tokens. data(), 
                                                    generated_tokens.size(),
                                                    temp_buffer.data(), 
                                                    temp_buffer.size(), true, false);
                    if (temp_len > 0) {
                        std::string temp_text(temp_buffer. data(), temp_len);
                        if (check_stop_sequence(temp_text)) {
                            LOGI("GENERATE: Stop sequence at step %d", i);
                            break;
                        }
                    }
                }
                
                // Decode наступного токена
                llama_batch next_batch = llama_batch_init(1, 0, 1);
                next_batch.token[0] = next_token;
                next_batch.pos[0] = cur_pos;
                next_batch.n_seq_id[0] = 1;
                next_batch.seq_id[0][0] = 0;
                next_batch.logits[0] = true;
                next_batch.n_tokens = 1;
                
                cur_pos++;
                
                int ret = llama_decode(llama_ctx, next_batch);
                llama_batch_free(next_batch);
                
                if (ret != 0) {
                    LOGE("GENERATE: Decode error at step %d, pos=%d", i, cur_pos - 1);
                    break;
                }
            }
            
            // Зберігаємо позицію KV-cache
            {
                std::lock_guard<std::mutex> state_lock(g_mutex);
                g_kv_cache_positions[ctx->handle] = cur_pos;
            }
            
            LOGI("GENERATE: Loop finished, generated %zu tokens, final kv_pos=%d", 
                 generated_tokens.size(), cur_pos);
            
            // ========== Detokenize ==========
            if (! generated_tokens.empty()) {
                std::vector<char> text_buffer(generated_tokens.size() * 10 + 1);
                int text_len = llama_detokenize(vocab, generated_tokens.data(), 
                                                generated_tokens.size(),
                                                text_buffer.data(), 
                                                text_buffer.size() - 1, true, false);
                
                if (text_len > 0) {
                    text_buffer[text_len] = '\0';
                    result_text = std::string(text_buffer.data(), text_len);
                    result_text = remove_stop_sequence(result_text);
                } else {
                    result_text = "";
                }
            }
            
            if (sampler) {
                llama_sampler_free(sampler);
                sampler = nullptr;
            }
            
            LOGI("GENERATE: Success, result length: %zu", result_text. length());
            
        } catch (const std::exception& e) {
            LOGE("GENERATE: Exception: %s", e. what());
            if (sampler) {
                llama_sampler_free(sampler);
            }
            result_text = "Error: Generation failed.";
        } catch (...) {
            LOGE("GENERATE: Unknown exception");
            if (sampler) {
                llama_sampler_free(sampler);
            }
            result_text = "Error: Unknown failure.";
        }
        
        char* output = new char[result_text.length() + 1];
        std::strcpy(output, result_text.c_str());
        
        g_generating_flags[ctx->handle].store(false);
        
        LOGI("=== GENERATE END (call #%d) ===", g_generation_count);
        return output;
        
    } catch (const std::exception& e) {
        LOGE("GENERATE: Top-level exception: %s", e.what());
        g_generating_flags[ctx->handle].store(false);
        return nullptr;
    }
}

// ========== Async генерація в окремому потоці ==========
void llama_dart_generate_async(
    llama_dart_context* ctx, 
    llama_dart_tokens* tokens, 
    llama_dart_inference_params* params,
    Dart_Port result_port
) {
    // Копіюємо дані для потоку
    llama_dart_context ctx_copy = *ctx;
    
    llama_dart_tokens tokens_copy;
    tokens_copy.nTokens = tokens->nTokens;
    tokens_copy.tokens = new int32_t[tokens->nTokens];
    memcpy(tokens_copy.tokens, tokens->tokens, tokens->nTokens * sizeof(int32_t));
    
    llama_dart_inference_params params_copy = *params;
    
    std::thread([ctx_copy, tokens_copy, params_copy, result_port]() mutable {
        llama_dart_context local_ctx = ctx_copy;
        llama_dart_tokens local_tokens = tokens_copy;
        llama_dart_inference_params local_params = params_copy;
        
        char* result = llama_dart_generate(&local_ctx, &local_tokens, &local_params);
        
        // Надсилаємо результат в Dart
        if (result) {
            send_to_dart(result_port, result, false);
            delete[] result;
        } else {
            send_to_dart(result_port, "Error: Generation failed", true);
        }
        
        // Звільняємо скопійовані токени
        delete[] local_tokens.tokens;
    }).detach();
}

// ========== Cancel генерації ==========
void llama_dart_cancel_generation(llama_dart_context* ctx) {
    if (!ctx) return;
    
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_cancel_flags. count(ctx->handle)) {
        LOGI("Cancelling generation for context %ld", ctx->handle);
        g_cancel_flags[ctx->handle]. store(true);
    }
}

// ========== Перевірка чи генерація активна ==========
bool llama_dart_is_generating(llama_dart_context* ctx) {
    if (!ctx) return false;
    
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_generating_flags.count(ctx->handle)) {
        return g_generating_flags[ctx->handle].load();
    }
    return false;
}

// ========== Очищення KV-cache ==========
void llama_dart_clear_kv_cache(llama_dart_context* ctx) {
    if (! ctx) return;
    
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(ctx->handle);
    if (it != g_contexts.end() && it->second) {
        llama_memory_t memory = llama_get_memory(it->second);
        if (memory) {
            llama_memory_clear(memory, true);
        }
        g_kv_cache_positions[ctx->handle] = 0;
        LOGI("KV-cache cleared for context %ld", ctx->handle);
    }
}

// ========== Отримання позиції KV-cache ==========
int32_t llama_dart_get_kv_cache_pos(llama_dart_context* ctx) {
    if (! ctx) return 0;
    
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_kv_cache_positions. count(ctx->handle)) {
        return g_kv_cache_positions[ctx->handle];
    }
    return 0;
}

// ========== Звільнення ресурсів ==========
void llama_dart_free_context(llama_dart_context* ctx) {
    std::lock_guard<std::mutex> lock(g_mutex);
    LOGI("=== FREE CONTEXT ===");
    if (ctx) {
        // Спочатку скасовуємо генерацію
        if (g_cancel_flags.count(ctx->handle)) {
            g_cancel_flags[ctx->handle].store(true);
        }
        
        auto it = g_contexts.find(ctx->handle);
        if (it != g_contexts.end()) {
            if (it->second) {
                llama_free(it->second);
            }
            g_contexts.erase(it);
        }
        
        g_kv_cache_positions.erase(ctx->handle);
        g_cancel_flags.erase(ctx->handle);
        g_generating_flags. erase(ctx->handle);
        
        delete ctx;
    }
}

void llama_dart_free_model(int32_t model_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    LOGI("=== FREE MODEL %d ===", model_id);
    auto it = g_models.find(model_id);
    if (it != g_models.end()) {
        if (it->second) {
            llama_model_free(it->second);
        }
        g_models.erase(it);
    }
}

void llama_dart_free_tokens(llama_dart_tokens* tokens) {
    if (tokens) {
        if (tokens->tokens) {
            delete[] tokens->tokens;
            tokens->tokens = nullptr;  // ВИПРАВЛЕННЯ #4: prevent double-free
        }
        delete tokens;
    }
}

void llama_dart_free_string(char* str) {
    if (str) {
        delete[] str;
    }
}

} // extern "C"