#ifndef FAULT_INJECTOR_H
#define FAULT_INJECTOR_H

#include <stdbool.h>
#include <stddef.h>  /* For size_t */
#include "fs_common.h"

// Initialize the fault injector
void fault_injector_init(void);

// Clean up fault injector resources
void fault_injector_cleanup(void);

// Check if a fault should be triggered for an operation
bool should_trigger_fault(fs_op_type_t operation);

// Update operation statistics (e.g., bytes processed)
void update_operation_stats(fs_op_type_t operation, size_t bytes);

// Apply an error fault if configured
bool apply_error_fault(fs_op_type_t operation, int *error_code);

// Apply a delay fault if configured
bool apply_delay_fault(fs_op_type_t operation);

// Apply a corruption fault if configured
bool apply_corruption_fault(fs_op_type_t operation, char *buffer, size_t size);

// Get partial size for partial operation faults
size_t apply_partial_fault(fs_op_type_t operation, size_t original_size);

// Helper function to check if a probability threshold is met (for internal use)
bool check_probability(float probability);

#endif // FAULT_INJECTOR_H