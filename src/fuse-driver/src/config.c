#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "config.h"

// Global configuration instance
static fs_config_t global_config;

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
    
    char line[256];
    while (fgets(line, sizeof(line), file)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n') {
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
            
            // Process configuration
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
    }
    
    fclose(file);
    return true;
}

// Free configuration resources
void config_cleanup(fs_config_t *config) {
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
}