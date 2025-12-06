#include "llama_bindings.h"
#include "llama.h"
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <android/log.h>

#define LOG_TAG "LlamaBindings"
#define LOGI(... ) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static std::map<int32_t, llama_model*> g_models;
static std::map<int64_t, llama_context*> g_contexts;
static int32_t g_next_model_id = 1;
static int64_t g_next_context_id = 1;

static const std::vector<std::string> STOP_SEQUENCES = {
    "User:", "\nUser:", "Human:", "\nHuman:",
    "Assistant:", "\nAssistant:",
    "<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>",
    "<|eot_id|>", "<|end|>", "</s>", "<|assistant|>", "<|user|>",
};

extern "C" {

int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params) {
    try {
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = params->nGpuLayers;
        model_params. use_mmap = true;
        model_params.use_mlock = false;
        
        LOGI("Loading model from: %s", path);
        LOGI("MMAP: enabled (RAM optimized)");
        
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
    try {
        auto it = g_models.find(model_id);
        if (it == g_models.end()) {
            LOGE("Model ID %d not found", model_id);
            return nullptr;
        }
        
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = params->nCtx > 0 ? params->nCtx : 2048;
        ctx_params.n_batch = params->nBatch > 0 ? params->nBatch : 256;
        ctx_params.n_threads = params->nThreads > 0 ? params->nThreads : 2;
        ctx_params.n_threads_batch = params->nThreads > 0 ? params->nThreads : 2;
        
        LOGI("Creating context: n_ctx=%d, n_batch=%d, n_threads=%d", 
             ctx_params.n_ctx, ctx_params. n_batch, ctx_params.n_threads);
        
        llama_context* ctx = llama_init_from_model(it->second, ctx_params);
        if (!ctx) {
            LOGE("Failed to create context for model %d", model_id);
            return nullptr;
        }
        
        int64_t context_id = g_next_context_id++;
        g_contexts[context_id] = ctx;
        
        llama_dart_context* dart_ctx = new llama_dart_context();
        dart_ctx->handle = context_id;
        
        LOGI("Context created with ID: %ld", context_id);
        return dart_ctx;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_create_context: %s", e.what());
        return nullptr;
    }
}

llama_dart_tokens* llama_dart_tokenize(llama_dart_context* ctx, const char* text) {
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
    try {
        if (!ctx || !tokens || !params) {
            LOGE("Invalid parameters for generation");
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
        
        const int n_ctx = llama_n_ctx(llama_ctx);
        const int max_gen_tokens = std::min(params->maxTokens, 512);
        
        LOGI("Context size: %d, input tokens: %d, max gen: %d", n_ctx, tokens->nTokens, max_gen_tokens);
        
        // Очищуємо KV-cache через llama_memory_clear
        llama_memory_t memory = llama_get_memory(llama_ctx);
        if (memory) {
            llama_memory_clear(memory, true);
            LOGI("KV-cache cleared via llama_memory_clear");
        }
        
        // Перевіряємо чи вхідні токени поміщаються в контекст
        int input_tokens_count = tokens->nTokens;
        if (input_tokens_count + max_gen_tokens > n_ctx) {
            int max_input = n_ctx - max_gen_tokens - 64;
            if (max_input < 64) max_input = 64;
            
            if (input_tokens_count > max_input) {
                LOGI("Truncating input from %d to %d tokens", input_tokens_count, max_input);
                input_tokens_count = max_input;
            }
        }
        
        std::string result_text;
        
        try {
            std::vector<llama_token> input_tokens;
            int start_idx = tokens->nTokens - input_tokens_count;
            for (int i = start_idx; i < tokens->nTokens; i++) {
                input_tokens.push_back(tokens->tokens[i]);
            }
            
            LOGI("Processing %zu input tokens", input_tokens.size());
            
            llama_batch batch = llama_batch_get_one(input_tokens. data(), input_tokens.size());
            
            int ret = llama_decode(llama_ctx, batch);
            if (ret != 0) {
                LOGE("Failed to decode tokens, error: %d", ret);
                
                // Fallback з меншою кількістю токенів
                if (input_tokens.size() > 256) {
                    LOGI("Retrying with fewer tokens.. .");
                    
                    if (memory) {
                        llama_memory_clear(memory, true);
                    }
                    
                    std::vector<llama_token> reduced_tokens(
                        input_tokens.end() - 256, 
                        input_tokens.end()
                    );
                    
                    batch = llama_batch_get_one(reduced_tokens.data(), reduced_tokens.size());
                    ret = llama_decode(llama_ctx, batch);
                }
                
                if (ret != 0) {
                    result_text = "Error: Context overflow.  Try a shorter message.";
                    char* output = new char[result_text.length() + 1];
                    std::strcpy(output, result_text. c_str());
                    return output;
                }
            }
            
            // Семплер
            llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
            llama_sampler* sampler = llama_sampler_chain_init(sampler_params);
            
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(params->temperature));
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int)params->topK));
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params->topP, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
                64, params->repeatPenalty, params->frequencyPenalty, params->presencePenalty
            ));
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(params->seed));
            
            std::vector<llama_token> generated_tokens;
            
            LOGI("Starting generation...");
            
            for (int i = 0; i < max_gen_tokens; i++) {
                llama_token next_token = llama_sampler_sample(sampler, llama_ctx, -1);
                
                if (llama_vocab_is_eog(vocab, next_token)) {
                    LOGI("End of generation at step %d", i);
                    break;
                }
                
                generated_tokens.push_back(next_token);
                llama_sampler_accept(sampler, next_token);
                
                // Перевіряємо стоп-послідовності кожні 10 токенів
                if ((i + 1) % 10 == 0 && ! generated_tokens.empty()) {
                    std::vector<char> temp_buffer(generated_tokens. size() * 10);
                    int temp_len = llama_detokenize(vocab, generated_tokens. data(), 
                                                    generated_tokens.size(),
                                                    temp_buffer.data(), 
                                                    temp_buffer.size(), true, false);
                    if (temp_len > 0) {
                        std::string temp_text(temp_buffer. data(), temp_len);
                        if (check_stop_sequence(temp_text)) {
                            LOGI("Stop sequence detected at step %d", i);
                            break;
                        }
                    }
                }
                
                llama_batch next_batch = llama_batch_get_one(&next_token, 1);
                ret = llama_decode(llama_ctx, next_batch);
                if (ret != 0) {
                    LOGE("Decode error at step %d", i);
                    break;
                }
            }
            
            // Конвертуємо в текст
            if (! generated_tokens.empty()) {
                std::vector<char> text_buffer(generated_tokens.size() * 10);
                int text_len = llama_detokenize(vocab, generated_tokens.data(), 
                                                generated_tokens.size(),
                                                text_buffer.data(), 
                                                text_buffer.size(), true, false);
                
                if (text_len > 0) {
                    result_text = std::string(text_buffer.data(), text_len);
                    result_text = remove_stop_sequence(result_text);
                } else {
                    result_text = "";
                }
            }
            
            llama_sampler_free(sampler);
            LOGI("Generated %zu tokens", generated_tokens.size());
            
        } catch (const std::exception& e) {
            LOGE("Exception during generation: %s", e.what());
            result_text = "Error: Generation failed. ";
        }
        
        char* output = new char[result_text. length() + 1];
        std::strcpy(output, result_text.c_str());
        return output;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_generate: %s", e.what());
        return nullptr;
    }
}

void llama_dart_free_context(llama_dart_context* ctx) {
    if (ctx) {
        auto it = g_contexts.find(ctx->handle);
        if (it != g_contexts.end()) {
            llama_free(it->second);
            g_contexts.erase(it);
            LOGI("Context %ld freed", ctx->handle);
        }
        delete ctx;
    }
}

void llama_dart_free_model(int32_t model_id) {
    auto it = g_models.find(model_id);
    if (it != g_models.end()) {
        llama_model_free(it->second);
        g_models.erase(it);
        LOGI("Model %d freed", model_id);
    }
}

void llama_dart_free_tokens(llama_dart_tokens* tokens) {
    if (tokens) {
        delete[] tokens->tokens;
        delete tokens;
    }
}

void llama_dart_free_string(char* str) {
    delete[] str;
}

} // extern "C"