#ifndef FAULT_INJECTOR_H
#define FAULT_INJECTOR_H

#include <stdbool.h>
#include <stddef.h>  /* For size_t */

// Initialize the fault injector
void fault_injector_init(void);

// Clean up fault injector resources
void fault_injector_cleanup(void);

// Check if a fault should be triggered for an operation
bool should_trigger_fault(const char *operation);

// Update operation statistics (e.g., bytes processed)
void update_operation_stats(const char *operation, size_t bytes);

#endif // FAULT_INJECTOR_H