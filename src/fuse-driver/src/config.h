#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include "log.h"

// Configuration structure
typedef struct {
    // Basic filesystem options
    char *storage_path;      // Path to backing storage
    char *log_file;          // Path to log file
    int log_level;           // Log level (0-3)
    
    // Fault injection options (to be expanded later)
    bool enable_fault_injection;  // Master switch for fault injection
    
    // Config file path (if used)
    char *config_file;       // Path to configuration file
} fs_config_t;

// Initialize configuration with defaults
void config_init(fs_config_t *config);

// Load configuration from file
bool config_load_from_file(fs_config_t *config, const char *filename);

// Free configuration resources
void config_cleanup(fs_config_t *config);

// Print current configuration
void config_print(fs_config_t *config);

// Get global configuration
fs_config_t* config_get_global(void);

#endif /* CONFIG_H */