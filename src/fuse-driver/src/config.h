#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stddef.h>  /* For size_t */
#include <stdint.h>  /* For uint32_t */
#include "fs_common.h"

// Error fault - returns error codes for operations
typedef struct {
    float probability;        // Probability of triggering (0.0-1.0)
    int error_code;           // Specific error code to return (e.g., -EIO)
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_error_t;

// Corruption fault - corrupts data in read/write operations
typedef struct {
    float probability;        // Probability of corrupting data
    float percentage;         // Percentage of data to corrupt (0-100)
    bool silent;              // Report success but corrupt data
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_corruption_t;

// Delay fault - adds latency to operations
typedef struct {
    float probability;        // Probability of adding delay
    int delay_ms;             // Delay in milliseconds
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_delay_t;

// Timing fault - triggers based on time patterns
typedef struct {
    bool enabled;             // Whether timing-based triggering is enabled
    int after_minutes;        // Start triggering after X minutes of operation
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_timing_t;

// Operation count fault - triggers based on operation counts
typedef struct {
    bool enabled;             // Whether count-based triggering is enabled
    int every_n_operations;   // Trigger on every Nth operation
    size_t after_bytes;       // Trigger after X bytes processed
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_operation_count_t;

// Partial operation fault - only completes part of read/write operations
typedef struct {
    float probability;        // Probability of partial operation
    float factor;             // Factor to multiply size by (0.0-1.0)
    uint32_t operations_mask; // Bit mask of operations to affect
} fault_partial_t;

// Configuration structure
typedef struct {
    // Basic filesystem options
    char *mount_point;       // Path to FUSE mount point
    char *storage_path;      // Path to backing storage
    char *log_file;          // Path to log file
    int log_level;           // Log level (0-3)
    
    // Fault injection master switch
    bool enable_fault_injection;  // Master switch for fault injection
    
    // Pointers to specific fault types (NULL if not enabled)
    fault_error_t *error_fault;
    fault_corruption_t *corruption_fault;
    fault_delay_t *delay_fault;
    fault_timing_t *timing_fault;
    fault_operation_count_t *operation_count_fault;
    fault_partial_t *partial_fault;
    
    // Config file path (if used)
    char *config_file;       // Path to configuration file
} fs_config_t;

// Initialize configuration with defaults from environment
void config_init(fs_config_t *config);

// Load configuration from file
bool config_load_from_file(fs_config_t *config, const char *filename);

// Free configuration resources
void config_cleanup(fs_config_t *config);

// Get global configuration instance
fs_config_t *config_get_global(void);

// Print current configuration
void config_print(fs_config_t *config);

// Helper function to check if an operation should be affected by a fault
bool config_should_affect_operation(uint32_t operations_mask, fs_op_type_t operation);

// Helper function to parse a string representation of operations to a bitmask
uint32_t config_parse_operations_mask(const char *operations_str);

#endif /* CONFIG_H */