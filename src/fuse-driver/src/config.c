#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include "config.h"
#include "log.h"

// Global configuration instance
static fs_config_t global_config;
static bool global_config_initialized = false;

// Default values
static const char *default_storage_path = "/var/nas-storage";
static const char *default_log_file = "stdout";
static const int default_log_level = LOG_INFO;

// Initialize configuration with defaults
void config_init(fs_config_t *config) {
    if (config == NULL) {
        return;
    }
    
    memset(config, 0, sizeof(fs_config_t));
    
    // Set default values
    config->storage_path = strdup(default_storage_path);
    config->log_file = strdup(default_log_file);
    config->log_level = default_log_level;
    config->enable_fault_injection = false;
    config->config_file = NULL;
    
    // Initialize global config if this is the global instance
    if (config == &global_config) {
        global_config_initialized = true;
    }
}

// Simple config file parser
// Format: key=value
bool config_load_from_file(fs_config_t *config, const char *filename) {
    if (config == NULL || filename == NULL) {
        return false;
    }
    
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        fprintf(stderr, "Error: Could not open config file: %s\n", filename);
        return false;
    }
    
    char line[1024];
    while (fgets(line, sizeof(line), file)) {
        // Remove newline
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
        }
        
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\0') {
            continue;
        }
        
        // Find key-value separator
        char *separator = strchr(line, '=');
        if (separator == NULL) {
            // Not a key=value line, skip
            continue;
        }
        
        // Split key and value
        *separator = '\0';
        char *key = line;
        char *value = separator + 1;
        
        // Trim whitespace
        while (*key && (*key == ' ' || *key == '\t')) key++;
        while (*value && (*value == ' ' || *value == '\t')) value++;
        
        char *key_end = key + strlen(key) - 1;
        while (key_end > key && (*key_end == ' ' || *key_end == '\t')) {
            *key_end = '\0';
            key_end--;
        }
        
        char *value_end = value + strlen(value) - 1;
        while (value_end > value && (*value_end == ' ' || *value_end == '\t')) {
            *value_end = '\0';
            value_end--;
        }
        
        // Process key=value pair
        if (strcmp(key, "storage_path") == 0) {
            free(config->storage_path);
            config->storage_path = strdup(value);
        } else if (strcmp(key, "log_file") == 0) {
            free(config->log_file);
            config->log_file = strdup(value);
        } else if (strcmp(key, "log_level") == 0) {
            config->log_level = atoi(value);
        } else if (strcmp(key, "enable_fault_injection") == 0) {
            config->enable_fault_injection = (strcmp(value, "true") == 0 || strcmp(value, "1") == 0);
        } else {
            fprintf(stderr, "Warning: Unknown configuration key: %s\n", key);
        }
    }
    
    fclose(file);
    
    // Store config file path for future reference
    free(config->config_file);
    config->config_file = strdup(filename);
    
    return true;
}

// Free configuration resources
void config_cleanup(fs_config_t *config) {
    if (config == NULL) {
        return;
    }
    
    free(config->storage_path);
    free(config->log_file);
    free(config->config_file);
    
    memset(config, 0, sizeof(fs_config_t));
    
    if (config == &global_config) {
        global_config_initialized = false;
    }
}

// Print current configuration
void config_print(fs_config_t *config) {
    if (config == NULL) {
        return;
    }
    
    fprintf(stderr, "==== NAS Emulator Configuration ====\n");
    fprintf(stderr, "Storage path: %s\n", config->storage_path);
    fprintf(stderr, "Log file: %s\n", config->log_file);
    fprintf(stderr, "Log level: %d\n", config->log_level);
    fprintf(stderr, "Enable fault injection: %s\n", config->enable_fault_injection ? "true" : "false");
    if (config->config_file) {
        fprintf(stderr, "Config file: %s\n", config->config_file);
    }
    fprintf(stderr, "===================================\n");
}

// Get global configuration
fs_config_t* config_get_global(void) {
    if (!global_config_initialized) {
        config_init(&global_config);
    }
    
    return &global_config;
}