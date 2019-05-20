consul kv put backend/age_extraction_debug true
consul kv put backend/memory_parameters_enable_gpu_memory_check false
consul kv put backend/misc_image_allowed_rotation true
consul kv put backend/liveness_check_save_faked_id_image true
consul kv put backend/liveness_check_eyes_awareness_threshold 0.5
consul kv put backend/liveness_check_save_faked_id_image false
consul kv put backend/misc_log_level DEBUG

consul kv put api-env/SAVE_LIVENESS_VIDEOS true
consul kv put api-env/USE_OCR true

consul kv get -recurse