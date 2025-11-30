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

// Глобальні змінні для зберігання моделей та контекстів
static std::map<int32_t, llama_model*> g_models;
static std::map<int64_t, llama_context*> g_contexts;
static int32_t g_next_model_id = 1;
static int64_t g_next_context_id = 1;
static llama_dart_progress_callback g_progress_callback = nullptr;

// Стоп-послідовності для зупинки генерації
static const std::vector<std::string> STOP_SEQUENCES = {
    "User:",
    "\nUser:",
    "Human:",
    "\nHuman:",
    "Assistant:",
    "\nAssistant:",
    "<|im_end|>",
    "<|im_start|>",
    "<end_of_turn>",
    "<start_of_turn>",
    "<|eot_id|>",
    "<|end|>",
    "</s>",
    "<|assistant|>",
    "<|user|>",
};

extern "C" {

int32_t llama_dart_load_model(const char* path, llama_dart_model_params* params) {
    try {
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = params->nGpuLayers;
        
        llama_model* model = llama_model_load_from_file(path, model_params);
        if (! model) {
            LOGE("Failed to load model from: %s", path);
            return -1;
        }
        
        int32_t model_id = g_next_model_id++;
        g_models[model_id] = model;
        
        LOGI("Model loaded with ID: %d", model_id);
        return model_id;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llama_dart_load_model: %s", e.what());
        return -1;
    }
}

llama_dart_context* llama_dart_create_context(int32_t model_id) {
    try {
        auto it = g_models.find(model_id);
        if (it == g_models.end()) {
            LOGE("Model ID %d not found", model_id);
            return nullptr;
        }
        
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = 2048;
        ctx_params.n_batch = 512;
        ctx_params.n_threads = 4;
        
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
            LOGE("Tokenization failed or buffer too small, needed: %d", -n_tokens);
            if (-n_tokens > max_tokens) {
                max_tokens = -n_tokens;
                tokens.resize(max_tokens);
                n_tokens = llama_tokenize(vocab, text, text_len, tokens.data(), max_tokens, true, false);
            }
        }
        
        if (n_tokens <= 0) {
            LOGE("Failed to tokenize text, falling back to single token");
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

// Функція для перевірки стоп-послідовностей
static bool check_stop_sequence(const std::string& text, std::string& cleaned_text) {
    for (const auto& stop : STOP_SEQUENCES) {
        size_t pos = text.find(stop);
        if (pos != std::string::npos) {
            cleaned_text = text.substr(0, pos);
            return true;
        }
    }
    cleaned_text = text;
    return false;
}

// Функція для детокенізації одного токена
static std::string detokenize_token(const llama_vocab* vocab, llama_token token) {
    std::vector<char> buffer(32);
    int len = llama_detokenize(vocab, &token, 1, buffer.data(), buffer. size(), false, false);
    if (len < 0) {
        buffer.resize(-len);
        len = llama_detokenize(vocab, &token, 1, buffer.data(), buffer.size(), false, false);
    }
    if (len > 0) {
        return std::string(buffer.data(), len);
    }
    return "";
}

char* llama_dart_generate(llama_dart_context* ctx, llama_dart_tokens* tokens, llama_dart_inference_params* params) {
    try {
        if (!ctx || !tokens || ! params) {
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
        
        std::string result_text;
        
        try {
            std::vector<llama_token> input_tokens;
            for (int i = 0; i < tokens->nTokens; i++) {
                input_tokens. push_back(tokens->tokens[i]);
            }
            
            llama_batch batch = llama_batch_get_one(input_tokens.data(), input_tokens.size());
            
            int ret = llama_decode(llama_ctx, batch);
            if (ret != 0) {
                LOGE("Failed to decode tokens, error: %d", ret);
                result_text = "Error: Failed to process input tokens. ";
            } else {
                float* logits = llama_get_logits_ith(llama_ctx, -1);
                if (! logits) {
                    LOGE("Failed to get logits");
                    result_text = "Error: Failed to get model logits.";
                } else {
                    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
                    llama_sampler* sampler = llama_sampler_chain_init(sampler_params);
                    
                    // Порядок семплерів важливий! 
                    // 1. Repeat penalty (застосовується до logits)
                    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
                        64,                          // penalty_last_n
                        params->repeatPenalty,       // repeat_penalty
                        params->frequencyPenalty,    // frequency_penalty
                        params->presencePenalty      // presence_penalty
                    ));
                    
                    // 2. Top-K sampling
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int)params->topK));
                    
                    // 3. Top-P sampling
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params->topP, 1));
                    
                    // 4.  Temperature
                    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params->temperature));
                    
                    // 5.  Distribution sampling
                    llama_sampler_chain_add(sampler, llama_sampler_init_dist(params->seed));
                    
                    std::vector<llama_token> generated_tokens;
                    int max_tokens = std::min(params->maxTokens, 512);
                    
                    for (int i = 0; i < max_tokens; i++) {
                        llama_token next_token = llama_sampler_sample(sampler, llama_ctx, -1);
                        
                        // Перевіряємо на кінець генерації
                        if (llama_vocab_is_eog(vocab, next_token)) {
                            LOGI("End of generation token reached");
                            break;
                        }
                        
                        generated_tokens. push_back(next_token);
                        
                        // Детокенізуємо поточний токен для перевірки стоп-послідовностей
                        std::string current_piece = detokenize_token(vocab, next_token);
                        result_text += current_piece;
                        
                        // Перевіряємо стоп-послідовності
                        std::string cleaned;
                        if (check_stop_sequence(result_text, cleaned)) {
                            LOGI("Stop sequence detected, stopping generation");
                            result_text = cleaned;
                            break;
                        }
                        
                        llama_sampler_accept(sampler, next_token);
                        
                        llama_batch next_batch = llama_batch_get_one(&next_token, 1);
                        
                        ret = llama_decode(llama_ctx, next_batch);
                        if (ret != 0) {
                            LOGE("Failed to decode generated token, stopping generation");
                            break;
                        }
                    }
                    
                    // Фінальне очищення результату
                    std::string final_cleaned;
                    check_stop_sequence(result_text, final_cleaned);
                    result_text = final_cleaned;
                    
                    if (result_text.empty()) {
                        result_text = "Error: No tokens generated.";
                    }
                    
                    llama_sampler_free(sampler);
                }
            }
            
        } catch (const std::exception& e) {
            LOGE("Exception during generation: %s", e.what());
            result_text = "Error: Exception during text generation.";
        }
        
        // Видаляємо пробіли з початку та кінця
        size_t start = result_text.find_first_not_of(" \t\n\r");
        size_t end = result_text.find_last_not_of(" \t\n\r");
        if (start != std::string::npos && end != std::string::npos) {
            result_text = result_text.substr(start, end - start + 1);
        }
        
        char* output = new char[result_text.length() + 1];
        std::strcpy(output, result_text. c_str());
        
        LOGI("Generated text: %s", result_text.c_str());
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
            g_contexts. erase(it);
            LOGI("Context %ld freed", ctx->handle);
        }
        delete ctx;
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

void llama_dart_set_progress_callback(llama_dart_progress_callback callback) {
    g_progress_callback = callback;
}

} // extern "C"