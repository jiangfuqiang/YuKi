// SPDX-License-Identifier: MIT OR Apache-2.0
// Minimal C API for libDF (DeepFilterNet), matching libDF/src/capi.rs
#ifndef DEEP_FILTER_H
#define DEEP_FILTER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DFState DFState;

/// Create a DeepFilterNet model state.
/// - path: file path to a DeepFilterNet tar.gz onnx model
/// - atten_lim: attenuation limit in dB (e.g. 100 for maximum reduction)
/// - log_level: optional log level string ("error", "info", "debug") or NULL
DFState *df_create(const char *path, float atten_lim, const char *log_level);

/// Frame size in samples (input/output buffers for df_process_frame).
size_t df_get_frame_length(DFState *st);

/// Next log message, or NULL. Free with df_free_log_msg.
char *df_next_log_msg(DFState *st);
void df_free_log_msg(char *ptr);

/// Change attenuation limit (dB) at runtime.
void df_set_atten_lim(DFState *st, float lim_db);

/// Post-filter beta; 0 disables. Suitable range 0..0.05.
void df_set_post_filter_beta(DFState *st, float beta);

/// Process one frame of `df_get_frame_length()` float samples.
/// Returns local SNR of the current frame.
float df_process_frame(DFState *st, float *input, float *output);

void df_free(DFState *st);

#ifdef __cplusplus
}
#endif

#endif /* DEEP_FILTER_H */
