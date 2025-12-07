#include "llama_bindings.h"
#include "llama.h"
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <android/log.h>
#include <mutex>

#define LOG_TAG "LlamaBindings"
#define LOGI(... ) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

static std::map<int32_t, llama_model*> g_models;
static std::map<int64_t, llama_context*> g_contexts;
static int32_t g_next_model_id = 1;
static int64_t g_next_context_id = 1;
static std::mutex g_mutex;
static int g_generation_count = 0;

static const std::vector<std::string> STOP_SEQUENCES = {
    "User:", "\nUser:", "Human:", "\nHuman:",
    "Assistant:", "\nAssistant:",
    "<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>",
    "<|eot_id|>", "<|end|>", "</s>", "<|assistant|>", "<|user|>",
};

extern "C" {

int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        LOGI("=== LOAD MODEL START ===");
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = params->nGpuLayers;
        model_params. use_mmap = true;
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
        ctx_params.n_batch = params->nBatch > 0 ? params->nBatch : 512;
        ctx_params.n_threads = params->nThreads > 0 ? params->nThreads : 2;
        ctx_params.n_threads_batch = params->nThreads > 0 ? params->nThreads : 2;
        
        LOGI("Creating context: n_ctx=%d, n_batch=%d, n_threads=%d", 
             ctx_params.n_ctx, ctx_params.n_batch, ctx_params. n_threads);
        
        llama_context* ctx = llama_init_from_model(it->second, ctx_params);
        if (!ctx) {
            LOGE("Failed to create context for model %d", model_id);
            return nullptr;
        }
        
        int64_t context_id = g_next_context_id++;
        g_contexts[context_id] = ctx;
        
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

char* llama_dart_generate(llama_dart_context* ctx, llama_dart_tokens* tokens, llama_dart_inference_params* params) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_generation_count++;
    LOGI("========================================");
    LOGI("=== GENERATE START (call #%d) ===", g_generation_count);
    LOGI("========================================");
    
    try {
        if (! ctx || !tokens || !params) {
            LOGE("GENERATE: Invalid parameters");
            return nullptr;
        }
        
        auto it = g_contexts.find(ctx->handle);
        if (it == g_contexts.end()) {
            LOGE("Context handle %ld not found", ctx->handle);
            return nullptr;
        }
        
        llama_context* llama_ctx = it->second;
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
        
        LOGI("GENERATE: n_ctx=%d, n_batch=%d, input_tokens=%d, max_gen=%d", 
             n_ctx, n_batch, tokens->nTokens, max_gen_tokens);
        
        // ========== КРИТИЧНО: Повне очищення KV-cache ==========
        LOGI("GENERATE: Clearing KV-cache.. .");
        llama_memory_t memory = llama_get_memory(llama_ctx);
        if (memory) {
            llama_memory_clear(memory, true);
            LOGI("GENERATE: KV-cache cleared via llama_memory_clear");
        } else {
            LOGW("GENERATE: No memory object, trying llama_kv_self_clear.. .");
            // Fallback для старіших версій
        }
        
        // Перевіряємо кількість токенів
        int input_tokens_count = tokens->nTokens;
        if (input_tokens_count <= 0) {
            LOGE("GENERATE: No input tokens");
            char* error_msg = new char[64];
            strcpy(error_msg, "Error: No input tokens");
            return error_msg;
        }
        
        // Обрізаємо якщо потрібно
        if (input_tokens_count + max_gen_tokens > n_ctx) {
            int max_input = n_ctx - max_gen_tokens - 64;
            if (max_input < 64) max_input = 64;
            
            if (input_tokens_count > max_input) {
                LOGW("GENERATE: Truncating input from %d to %d tokens", input_tokens_count, max_input);
                input_tokens_count = max_input;
            }
        }
        
        // Перевіряємо що не перевищуємо batch size
        if (input_tokens_count > n_batch) {
            LOGW("GENERATE: Input tokens (%d) > n_batch (%d), truncating", input_tokens_count, n_batch);
            input_tokens_count = n_batch;
        }
        
        std::string result_text;
        llama_sampler* sampler = nullptr;
        
        try {
            // Копіюємо токени
            std::vector<llama_token> input_tokens;
            input_tokens.reserve(input_tokens_count);
            int start_idx = tokens->nTokens - input_tokens_count;
            
            for (int i = start_idx; i < tokens->nTokens; i++) {
                input_tokens.push_back(tokens->tokens[i]);
            }
            
            LOGI("GENERATE: Processing %zu input tokens (start_idx=%d)", input_tokens.size(), start_idx);
            
            // ========== КЛЮЧОВЕ ВИПРАВЛЕННЯ: Використовуємо правильний batch ==========
            // Замість llama_batch_get_one використовуємо llama_batch_init
            // і явно вказуємо позиції токенів починаючи з 0
            
            llama_batch batch = llama_batch_init(input_tokens.size(), 0, 1);
            
            for (size_t i = 0; i < input_tokens. size(); i++) {
                batch.token[i] = input_tokens[i];
                batch.pos[i] = i;  // Позиція починається з 0! 
                batch.n_seq_id[i] = 1;
                batch. seq_id[i][0] = 0;
                batch.logits[i] = (i == input_tokens.size() - 1); // Логіти тільки для останнього
            }
            batch.n_tokens = input_tokens. size();
            
            LOGI("GENERATE: Batch created with %d tokens, positions 0-%zu", 
                 batch. n_tokens, input_tokens.size() - 1);
            
            // Decode
            LOGI("GENERATE: Calling llama_decode.. .");
            int ret = llama_decode(llama_ctx, batch);
            LOGI("GENERATE: llama_decode returned %d", ret);
            
            // Звільняємо batch після використання
            llama_batch_free(batch);
            
            if (ret != 0) {
                LOGE("GENERATE: llama_decode failed with error %d", ret);
                
                // Спробуємо з меншою кількістю токенів
                if (input_tokens. size() > 128) {
                    LOGW("GENERATE: Retrying with 128 tokens.. .");
                    
                    if (memory) {
                        llama_memory_clear(memory, true);
                    }
                    
                    std::vector<llama_token> reduced_tokens(
                        input_tokens.end() - 128, 
                        input_tokens.end()
                    );
                    
                    llama_batch retry_batch = llama_batch_init(reduced_tokens.size(), 0, 1);
                    for (size_t i = 0; i < reduced_tokens. size(); i++) {
                        retry_batch.token[i] = reduced_tokens[i];
                        retry_batch. pos[i] = i;
                        retry_batch.n_seq_id[i] = 1;
                        retry_batch.seq_id[i][0] = 0;
                        retry_batch.logits[i] = (i == reduced_tokens. size() - 1);
                    }
                    retry_batch.n_tokens = reduced_tokens. size();
                    
                    ret = llama_decode(llama_ctx, retry_batch);
                    llama_batch_free(retry_batch);
                    
                    if (ret != 0) {
                        LOGE("GENERATE: Retry also failed");
                        result_text = "Error: Context overflow.  Try a shorter message.";
                        char* output = new char[result_text.length() + 1];
                        std::strcpy(output, result_text. c_str());
                        return output;
                    }
                    
                    // Оновлюємо input_tokens для правильного підрахунку позицій
                    input_tokens = reduced_tokens;
                } else {
                    result_text = "Error: Decode failed. ";
                    char* output = new char[result_text. length() + 1];
                    std::strcpy(output, result_text. c_str());
                    return output;
                }
            }
            
            // ========== Створення sampler ==========
            LOGI("GENERATE: Creating sampler.. .");
            llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
            sampler = llama_sampler_chain_init(sampler_params);
            
            if (! sampler) {
                LOGE("GENERATE: Failed to create sampler");
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
            
            // Поточна позиція в KV-cache
            int cur_pos = input_tokens.size();
            
            LOGI("GENERATE: Starting generation loop (cur_pos=%d, max=%d)...", cur_pos, max_gen_tokens);
            
            // ========== Цикл генерації ==========
            for (int i = 0; i < max_gen_tokens; i++) {
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
                
                // Decode наступного токена з правильною позицією
                llama_batch next_batch = llama_batch_init(1, 0, 1);
                next_batch.token[0] = next_token;
                next_batch.pos[0] = cur_pos;  // Використовуємо поточну позицію! 
                next_batch.n_seq_id[0] = 1;
                next_batch.seq_id[0][0] = 0;
                next_batch.logits[0] = true;
                next_batch.n_tokens = 1;
                
                cur_pos++;  // Інкрементуємо позицію
                
                ret = llama_decode(llama_ctx, next_batch);
                llama_batch_free(next_batch);
                
                if (ret != 0) {
                    LOGE("GENERATE: Decode error at step %d, pos=%d", i, cur_pos - 1);
                    break;
                }
            }
            
            LOGI("GENERATE: Loop finished, generated %zu tokens", generated_tokens.size());
            
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
        
        char* output = new char[result_text. length() + 1];
        std::strcpy(output, result_text.c_str());
        
        LOGI("=== GENERATE END (call #%d) ===", g_generation_count);
        return output;
        
    } catch (const std::exception& e) {
        LOGE("GENERATE: Top-level exception: %s", e.what());
        return nullptr;
    }
}

void llama_dart_free_context(llama_dart_context* ctx) {
    std::lock_guard<std::mutex> lock(g_mutex);
    LOGI("=== FREE CONTEXT ===");
    if (ctx) {
        auto it = g_contexts.find(ctx->handle);
        if (it != g_contexts.end()) {
            if (it->second) {
                llama_free(it->second);
            }
            g_contexts.erase(it);
        }
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