#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include "config.h"

// Global configuration instance
static fs_config_t global_config;

// This function has been replaced by config_parse_operations_mask

// Helper function to check if an operation should be affected by a fault
bool config_should_affect_operation(uint32_t operations_mask, fs_op_type_t operation) {
    // If no operations are specified (mask is 0), affect no operations
    if (operations_mask == 0) {
        return false;
    }
    
    // If all bits set to 1, affect all operations
    if (operations_mask == 0xFFFFFFFF) {
        return true;
    }
    
    // Check if the bit for this operation is set in the mask
    return (operations_mask & (1 << operation)) != 0;
}

// Helper function to parse a string representation of operations to a bitmask
uint32_t config_parse_operations_mask(const char *operations_str) {
    if (!operations_str || strlen(operations_str) == 0) {
        return 0;  // Empty string = no operations
    }
    
    // Special case for "all" or "*"
    if (strcmp(operations_str, "all") == 0 || strcmp(operations_str, "*") == 0) {
        return 0xFFFFFFFF;  // All bits set = all operations
    }
    
    uint32_t mask = 0;
    char *str = strdup(operations_str);
    char *token = strtok(str, ",");
    
    while (token) {
        // Trim leading whitespace
        while (*token && isspace(*token)) {
            token++;
        }
        
        // Trim trailing whitespace
        char *end = token + strlen(token) - 1;
        while (end > token && isspace(*end)) {
            *end = '\0';
            end--;
        }
        
        // Find matching operation and set its bit
        for (int i = 0; i < FS_OP_COUNT; i++) {
            if (strcmp(token, fs_op_names[i]) == 0) {
                mask |= (1 << i);
                break;
            }
        }
        
        token = strtok(NULL, ",");
    }
    
    free(str);
    return mask;
}

// Get global configuration instance
fs_config_t *config_get_global(void) {
    return &global_config;
}

// Initialize configuration with defaults from environment variables
void config_init(fs_config_t *config) {
    const char *env_mount_point = getenv("NAS_MOUNT_POINT");
    const char *env_storage_path = getenv("NAS_STORAGE_PATH");
    const char *env_log_file = getenv("NAS_LOG_FILE");
    const char *env_log_level = getenv("NAS_LOG_LEVEL");
    
    // Set defaults first, then override with environment variables if available
    config->mount_point = strdup(env_mount_point ? env_mount_point : "/mnt/nas-mount");
    config->storage_path = strdup(env_storage_path ? env_storage_path : "/var/nas-storage");
    config->log_file = strdup(env_log_file ? env_log_file : "/var/log/nas-emu.log");
    config->log_level = env_log_level ? atoi(env_log_level) : 2;
    config->enable_fault_injection = false;
    config->config_file = NULL;
    
    // Initialize all fault pointers to NULL (disabled)
    config->error_fault = NULL;
    config->corruption_fault = NULL;
    config->delay_fault = NULL;
    config->timing_fault = NULL;
    config->operation_count_fault = NULL;
    config->partial_fault = NULL;
}

// Load configuration from file
bool config_load_from_file(fs_config_t *config, const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        fprintf(stderr, "Failed to open config file: %s\n", filename);
        return false;
    }
    
    // Store config file path
    if (config->config_file) {
        free(config->config_file);
    }
    config->config_file = strdup(filename);
    
    // Section tracking for nested configurations
    char current_section[128] = "";
    
    char line[256];
    while (fgets(line, sizeof(line), file)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // Check for section headers [section_name]
        if (line[0] == '[' && strchr(line, ']')) {
            sscanf(line, "[%127[^]]", current_section);
            
            // Initialize fault structures for each section
            if (strcmp(current_section, "error_fault") == 0 && !config->error_fault) {
                config->error_fault = calloc(1, sizeof(fault_error_t));
                if (config->error_fault) {
                    config->error_fault->probability = 0.5;  // Default values
                    config->error_fault->error_code = -EIO;
                    config->error_fault->operations_mask = 0xFFFFFFFF;  // Default: all operations
                }
            } else if (strcmp(current_section, "corruption_fault") == 0 && !config->corruption_fault) {
                config->corruption_fault = calloc(1, sizeof(fault_corruption_t));
                if (config->corruption_fault) {
                    config->corruption_fault->probability = 0.5;
                    config->corruption_fault->percentage = 10.0;
                    config->corruption_fault->silent = true;
                    config->corruption_fault->operations_mask = (1 << FS_OP_WRITE);  // Default: write only (safer)
                }
            } else if (strcmp(current_section, "delay_fault") == 0 && !config->delay_fault) {
                config->delay_fault = calloc(1, sizeof(fault_delay_t));
                if (config->delay_fault) {
                    config->delay_fault->probability = 0.5;
                    config->delay_fault->delay_ms = 500;
                    config->delay_fault->operations_mask = 0xFFFFFFFF;  // Default: all operations
                }
            } else if (strcmp(current_section, "timing_fault") == 0 && !config->timing_fault) {
                config->timing_fault = calloc(1, sizeof(fault_timing_t));
                if (config->timing_fault) {
                    config->timing_fault->enabled = false;  // Default: disabled for safety
                    config->timing_fault->after_minutes = 5;
                    config->timing_fault->operations_mask = 0xFFFFFFFF;  // Default: all operations
                }
            } else if (strcmp(current_section, "operation_count_fault") == 0 && !config->operation_count_fault) {
                config->operation_count_fault = calloc(1, sizeof(fault_operation_count_t));
                if (config->operation_count_fault) {
                    config->operation_count_fault->enabled = false;  // Default: disabled for safety
                    config->operation_count_fault->every_n_operations = 10;
                    config->operation_count_fault->after_bytes = 1024 * 1024; // 1MB
                    config->operation_count_fault->operations_mask = 0xFFFFFFFF;  // Default: all operations
                }
            } else if (strcmp(current_section, "partial_fault") == 0 && !config->partial_fault) {
                config->partial_fault = calloc(1, sizeof(fault_partial_t));
                if (config->partial_fault) {
                    config->partial_fault->probability = 0.5;
                    config->partial_fault->factor = 0.5;
                    config->partial_fault->operations_mask = (1 << FS_OP_READ) | (1 << FS_OP_WRITE);  // Default: read/write only
                }
            }
            
            continue;
        }
        
        char key[128] = {0};
        char value[128] = {0};
        
        // Parse key-value pairs
        if (sscanf(line, "%127[^=]=%127[^\n]", key, value) == 2) {
            // Trim whitespace
            char *k = key;
            while (*k && *k == ' ') k++;
            char *v = value;
            while (*v && *v == ' ') v++;
            
            // Remove trailing whitespace from key
            char *end = k + strlen(k) - 1;
            while (end > k && *end == ' ') {
                *end-- = '\0';
            }
            
            // Strip comments from value (everything after #)
            char *comment = strchr(v, '#');
            if (comment) {
                *comment = '\0';  // Terminate string at comment
                // Remove trailing whitespace after stripping comment
                end = v + strlen(v) - 1;
                while (end >= v && (*end == ' ' || *end == '\t')) {
                    *end-- = '\0';
                }
            }
            
            // Process global configuration
            if (strlen(current_section) == 0) {
                if (strcmp(k, "storage_path") == 0) {
                    free(config->storage_path);
                    config->storage_path = strdup(v);
                } else if (strcmp(k, "mount_point") == 0) {
                    free(config->mount_point);
                    config->mount_point = strdup(v);
                } else if (strcmp(k, "log_file") == 0) {
                    free(config->log_file);
                    config->log_file = strdup(v);
                } else if (strcmp(k, "log_level") == 0) {
                    config->log_level = atoi(v);
                } else if (strcmp(k, "enable_fault_injection") == 0) {
                    config->enable_fault_injection = (strcmp(v, "true") == 0 || strcmp(v, "1") == 0);
                }
            }
            // Process error fault configuration
            else if (strcmp(current_section, "error_fault") == 0 && config->error_fault) {
                if (strcmp(k, "probability") == 0) {
                    config->error_fault->probability = atof(v);
                } else if (strcmp(k, "error_code") == 0) {
                    config->error_fault->error_code = atoi(v);
                } else if (strcmp(k, "operations") == 0) {
                    config->error_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
            // Process corruption fault configuration
            else if (strcmp(current_section, "corruption_fault") == 0 && config->corruption_fault) {
                if (strcmp(k, "probability") == 0) {
                    config->corruption_fault->probability = atof(v);
                } else if (strcmp(k, "percentage") == 0) {
                    config->corruption_fault->percentage = atof(v);
                } else if (strcmp(k, "silent") == 0) {
                    config->corruption_fault->silent = (strcmp(v, "true") == 0 || strcmp(v, "1") == 0);
                } else if (strcmp(k, "operations") == 0) {
                    config->corruption_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
            // Process delay fault configuration
            else if (strcmp(current_section, "delay_fault") == 0 && config->delay_fault) {
                if (strcmp(k, "probability") == 0) {
                    config->delay_fault->probability = atof(v);
                } else if (strcmp(k, "delay_ms") == 0) {
                    config->delay_fault->delay_ms = atoi(v);
                } else if (strcmp(k, "operations") == 0) {
                    config->delay_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
            // Process timing fault configuration
            else if (strcmp(current_section, "timing_fault") == 0 && config->timing_fault) {
                if (strcmp(k, "enabled") == 0) {
                    config->timing_fault->enabled = (strcmp(v, "true") == 0 || strcmp(v, "1") == 0);
                } else if (strcmp(k, "after_minutes") == 0) {
                    config->timing_fault->after_minutes = atoi(v);
                } else if (strcmp(k, "operations") == 0) {
                    config->timing_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
            // Process operation count fault configuration
            else if (strcmp(current_section, "operation_count_fault") == 0 && config->operation_count_fault) {
                if (strcmp(k, "enabled") == 0) {
                    config->operation_count_fault->enabled = (strcmp(v, "true") == 0 || strcmp(v, "1") == 0);
                } else if (strcmp(k, "every_n_operations") == 0) {
                    config->operation_count_fault->every_n_operations = atoi(v);
                } else if (strcmp(k, "after_bytes") == 0) {
                    config->operation_count_fault->after_bytes = atol(v);
                } else if (strcmp(k, "operations") == 0) {
                    config->operation_count_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
            // Process partial operation fault configuration
            else if (strcmp(current_section, "partial_fault") == 0 && config->partial_fault) {
                if (strcmp(k, "probability") == 0) {
                    config->partial_fault->probability = atof(v);
                } else if (strcmp(k, "factor") == 0) {
                    config->partial_fault->factor = atof(v);
                } else if (strcmp(k, "operations") == 0) {
                    config->partial_fault->operations_mask = config_parse_operations_mask(v);
                }
            }
        }
    }
    
    fclose(file);
    return true;
}

// Free configuration resources
void config_cleanup(fs_config_t *config) {
    // Free basic configuration strings
    if (config->storage_path) {
        free(config->storage_path);
        config->storage_path = NULL;
    }
    
    if (config->mount_point) {
        free(config->mount_point);
        config->mount_point = NULL;
    }
    
    if (config->log_file) {
        free(config->log_file);
        config->log_file = NULL;
    }
    
    if (config->config_file) {
        free(config->config_file);
        config->config_file = NULL;
    }
    
    // Free error fault resources
    if (config->error_fault) {
        free(config->error_fault);
        config->error_fault = NULL;
    }
    
    // Free corruption fault resources
    if (config->corruption_fault) {
        free(config->corruption_fault);
        config->corruption_fault = NULL;
    }
    
    // Free delay fault resources
    if (config->delay_fault) {
        free(config->delay_fault);
        config->delay_fault = NULL;
    }
    
    // Free timing fault resources
    if (config->timing_fault) {
        free(config->timing_fault);
        config->timing_fault = NULL;
    }
    
    // Free operation count fault resources
    if (config->operation_count_fault) {
        free(config->operation_count_fault);
        config->operation_count_fault = NULL;
    }
    
    // Free partial fault resources
    if (config->partial_fault) {
        free(config->partial_fault);
        config->partial_fault = NULL;
    }
}

// Print current configuration
void config_print(fs_config_t *config) {
    printf("NAS Emulator Configuration:\n");
    printf("  Mount Point: %s\n", config->mount_point);
    printf("  Storage Path: %s\n", config->storage_path);
    printf("  Log File: %s\n", config->log_file);
    printf("  Log Level: %d\n", config->log_level);
    printf("  Enable Fault Injection: %s\n", config->enable_fault_injection ? "true" : "false");
    
    if (config->config_file) {
        printf("  Config File: %s\n", config->config_file);
    }
    
    // Print fault configurations if enabled
    if (config->enable_fault_injection) {
        if (config->error_fault) {
            printf("  Error Fault:\n");
            printf("    Probability: %.2f\n", config->error_fault->probability);
            printf("    Error Code: %d\n", config->error_fault->error_code);
            printf("    Operations: ");
            if (config->error_fault->operations_mask == 0xFFFFFFFF) {
                printf("all");
            } else {
                int printed = 0;
                for (int i = 0; i < FS_OP_COUNT; i++) {
                    if (config->error_fault->operations_mask & (1 << i)) {
                        printf("%s%s", printed > 0 ? ", " : "", fs_op_names[i]);
                        printed++;
                    }
                }
            }
            printf("\n");
        }
        
        if (config->corruption_fault) {
            printf("  Corruption Fault:\n");
            printf("    Probability: %.2f\n", config->corruption_fault->probability);
            printf("    Percentage: %.2f%%\n", config->corruption_fault->percentage);
            printf("    Silent: %s\n", config->corruption_fault->silent ? "true" : "false");
            printf("    Operations: ");
            if (config->corruption_fault->operations_mask == 0xFFFFFFFF) {
                printf("all");
            } else {
                int printed = 0;
                for (int i = 0; i < FS_OP_COUNT; i++) {
                    if (config->corruption_fault->operations_mask & (1 << i)) {
                        printf("%s%s", printed > 0 ? ", " : "", fs_op_names[i]);
                        printed++;
                    }
                }
            }
            printf("\n");
        }
        
        if (config->delay_fault) {
            printf("  Delay Fault:\n");
            printf("    Probability: %.2f\n", config->delay_fault->probability);
            printf("    Delay: %d ms\n", config->delay_fault->delay_ms);
            printf("    Operations: ");
            if (config->delay_fault->operations_mask == 0xFFFFFFFF) {
                printf("all");
            } else {
                int printed = 0;
                for (int i = 0; i < FS_OP_COUNT; i++) {
                    if (config->delay_fault->operations_mask & (1 << i)) {
                        printf("%s%s", printed > 0 ? ", " : "", fs_op_names[i]);
                        printed++;
                    }
                }
            }
            printf("\n");
        }
        
        // Print other fault types...
        // (similar structure for timing, operation count, and partial faults)
    }
}