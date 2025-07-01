#include "fault_injector.h"
#include "log.h"
#include "config.h"
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

// Operational statistics tracking
typedef struct {
    size_t bytes_read;
    size_t bytes_written;
    int operation_count;
    time_t start_time;
    int op_counts[FS_OP_COUNT];  // Count per operation type
} operation_stats_t;

static operation_stats_t stats;

// Random number generator seeded?
static bool rng_seeded = false;

// Initialize the fault injector
void fault_injector_init(void) {
    LOG_INFO("Fault injector initialized");
    
    // Seed random number generator
    if (!rng_seeded) {
        srand((unsigned int)time(NULL));
        rng_seeded = true;
    }
    
    // Initialize operation statistics
    memset(&stats, 0, sizeof(stats));
    stats.start_time = time(NULL);
}

// Clean up fault injector resources
void fault_injector_cleanup(void) {
    LOG_INFO("Fault injector cleaned up");
    LOG_INFO("Final operation stats: %d operations, %zu bytes read, %zu bytes written",
             stats.operation_count, stats.bytes_read, stats.bytes_written);
}

// Helper function to check if a probability threshold is met
bool check_probability(float probability) {
    if (!rng_seeded) {
        srand((unsigned int)time(NULL));
        rng_seeded = true;
        LOG_DEBUG("Random number generator seeded");
    }
    
    LOG_DEBUG("Checking probability: threshold=%.3f", probability);
    
    if (probability <= 0.0f) {
        LOG_DEBUG("Probability check: threshold <= 0, returning false");
        return false;
    }
    
    if (probability >= 1.0f) {
        LOG_DEBUG("Probability check: threshold >= 1, returning true");
        return true;
    }
    
    // Generate random number between 0 and 1
    float r = (float)rand() / (float)RAND_MAX;
    bool result = r < probability;
    LOG_DEBUG("Probability check: random=%.3f, threshold=%.3f, result=%s", 
              r, probability, result ? "TRIGGER" : "skip");
    return result;
}

// Helper to check if timing conditions are met
bool check_timing_fault(fs_op_type_t operation) {
    fs_config_t *config = config_get_global();
    
    if (!config->enable_fault_injection || !config->timing_fault || !config->timing_fault->enabled) {
        return false;
    }
    
    // Check if the operation should be affected
    if (!config_should_affect_operation(config->timing_fault->operations_mask, operation)) {
        return false;
    }
    
    // Check time elapsed since start
    if (config->timing_fault->after_minutes > 0) {
        time_t now = time(NULL);
        double elapsed_minutes = difftime(now, stats.start_time) / 60.0;
        
        if (elapsed_minutes < config->timing_fault->after_minutes) {
            LOG_DEBUG("Timing fault: %s not triggered (only %.1f minutes elapsed, need %d)",
                     fs_op_names[operation], elapsed_minutes, config->timing_fault->after_minutes);
            return false;
        }
        
        LOG_INFO("Timing fault: %s triggered after %.1f minutes",
                fs_op_names[operation], elapsed_minutes);
        return true;
    }
    
    return false;
}

// Helper to check if operation count conditions are met
bool check_operation_count_fault(fs_op_type_t operation) {
    fs_config_t *config = config_get_global();
    
    if (!config->enable_fault_injection || !config->operation_count_fault || !config->operation_count_fault->enabled) {
        return false;
    }
    
    // Check if the operation should be affected
    if (!config_should_affect_operation(config->operation_count_fault->operations_mask, operation)) {
        return false;
    }
    
    // Check operation count
    if (config->operation_count_fault->every_n_operations > 0 &&
        stats.operation_count % config->operation_count_fault->every_n_operations == 0) {
        LOG_INFO("Operation count fault: %s triggered on operation #%d",
                fs_op_names[operation], stats.operation_count);
        return true;
    }
    
    // Check byte count
    if (config->operation_count_fault->after_bytes > 0 &&
        (stats.bytes_read + stats.bytes_written) >= config->operation_count_fault->after_bytes) {
        LOG_INFO("Operation count fault: %s triggered after %zu bytes processed",
                fs_op_names[operation], (stats.bytes_read + stats.bytes_written));
        return true;
    }
    
    return false;
}

// Apply an error fault if configured
bool apply_error_fault(fs_op_type_t operation, int *error_code) {
    fs_config_t *config = config_get_global();
    
    if (!config->enable_fault_injection || !config->error_fault) {
        return false;
    }
    
    // Check if the operation should be affected
    if (!config_should_affect_operation(config->error_fault->operations_mask, operation)) {
        return false;
    }
    
    // Check probability
    if (!check_probability(config->error_fault->probability)) {
        return false;
    }
    
    // Apply the error fault
    *error_code = config->error_fault->error_code;
    LOG_INFO("Error fault injected for %s: error code %d", fs_op_names[operation], *error_code);
    return true;
}

// Apply a delay fault if configured
bool apply_delay_fault(fs_op_type_t operation) {
    //LOG_INFO("apply_delay_fault: START for operation %d", operation);
    fs_config_t *config = config_get_global();
    //LOG_INFO("apply_delay_fault: Got config");
    
    if (!config->enable_fault_injection || !config->delay_fault) {
        //LOG_INFO("apply_delay_fault: No delay_fault config, returning false");
        return false;
    }
    
    //LOG_INFO("apply_delay_fault: Checking if operation should be affected...");
    // Check if the operation should be affected
    if (!config_should_affect_operation(config->delay_fault->operations_mask, operation)) {
        //OG_INFO("apply_delay_fault: Operation not affected, returning false");
        return false;
    }
    
    //LOG_INFO("apply_delay_fault: Checking probability...");
    // Check probability
    if (!check_probability(config->delay_fault->probability)) {
        //LOG_INFO("apply_delay_fault: Probability check failed, returning false");
        return false;
    }
    
    // Apply the delay fault
    int delay_ms = config->delay_fault->delay_ms;
    LOG_INFO("Delay fault injected for %s: sleeping for %d ms", fs_op_names[operation], delay_ms);
    usleep(delay_ms * 1000); // Convert ms to microseconds
    //LOG_INFO("apply_delay_fault: Sleep completed, returning true");
    return true;
}

// Apply a corruption fault if configured
bool apply_corruption_fault(fs_op_type_t operation, char *buffer, size_t size) {
    fs_config_t *config = config_get_global();
    
    LOG_DEBUG("=== CORRUPTION FAULT CHECK for %s ===", fs_op_names[operation]);
    LOG_DEBUG("Buffer: %p, Size: %zu", buffer, size);
    
    if (!config->enable_fault_injection || !config->corruption_fault) {
        LOG_DEBUG("Corruption fault: config->corruption_fault is NULL");
        return false;
    }
    
    if (!buffer) {
        LOG_DEBUG("Corruption fault: buffer is NULL");
        return false;
    }
    
    if (size == 0) {
        LOG_DEBUG("Corruption fault: size is 0");
        return false;
    }
    
    LOG_DEBUG("Corruption fault config: probability=%.3f, percentage=%.1f, operations_mask=0x%x",
              config->corruption_fault->probability, 
              config->corruption_fault->percentage, 
              config->corruption_fault->operations_mask);
    
    // Check if the operation should be affected
    bool should_affect = config_should_affect_operation(config->corruption_fault->operations_mask, operation);
    LOG_DEBUG("Operation %s should be affected: %s", fs_op_names[operation], should_affect ? "YES" : "NO");
    if (!should_affect) {
        return false;
    }
    
    // Check probability
    LOG_DEBUG("Checking corruption probability...");
    bool prob_triggered = check_probability(config->corruption_fault->probability);
    LOG_DEBUG("Corruption probability result: %s", prob_triggered ? "TRIGGERED" : "not triggered");
    if (!prob_triggered) {
        return false;
    }
    
    // Validate corruption percentage
    if (config->corruption_fault->percentage < 0.0 || config->corruption_fault->percentage > 100.0) {
        LOG_ERROR("Invalid corruption percentage: %.1f%% (must be 0-100)", config->corruption_fault->percentage);
        return false;
    }
    
    // Calculate how many bytes to corrupt
    size_t corrupt_bytes = (size_t)(size * config->corruption_fault->percentage / 100.0);
    LOG_DEBUG("Calculated corrupt_bytes: %zu (%.1f%% of %zu)", 
              corrupt_bytes, config->corruption_fault->percentage, size);
    
    // Corrupt at least one byte if percentage is non-zero
    if (corrupt_bytes == 0 && config->corruption_fault->percentage > 0) {
        corrupt_bytes = 1;
        LOG_DEBUG("Adjusted corrupt_bytes to 1 (minimum for non-zero percentage)");
    }
    
    // Safety check: don't corrupt more bytes than we have
    if (corrupt_bytes > size) {
        corrupt_bytes = size;
        LOG_DEBUG("Capped corrupt_bytes to buffer size: %zu", corrupt_bytes);
    }
    
    LOG_INFO("=== APPLYING CORRUPTION ===");
    LOG_INFO("Corruption fault injected for %s: corrupting %zu of %zu bytes (%.1f%%)",
            fs_op_names[operation], corrupt_bytes, size, config->corruption_fault->percentage);
    
    // Log original data sample (first 32 bytes)
    LOG_DEBUG("Original data sample (first 32 bytes):");
    for (size_t i = 0; i < (size < 32 ? size : 32); i++) {
        LOG_DEBUG("  [%zu]: 0x%02x ('%c')", i, (unsigned char)buffer[i], 
                  (buffer[i] >= 32 && buffer[i] < 127) ? buffer[i] : '.');
    }
    
    // Corrupt random bytes in the buffer
    for (size_t i = 0; i < corrupt_bytes && size > 0; i++) {
        size_t pos = rand() % size;
        char original = buffer[pos];
        char corrupted = (char)(rand() % 256);
        buffer[pos] = corrupted;
        LOG_DEBUG("Corrupted byte at pos %zu: 0x%02x -> 0x%02x", 
                  pos, (unsigned char)original, (unsigned char)corrupted);
    }
    
    LOG_INFO("=== CORRUPTION COMPLETE ===");
    return true;
}

// Get partial size for partial operation faults
size_t apply_partial_fault(fs_op_type_t operation, size_t original_size) {
    fs_config_t *config = config_get_global();
    
    if (!config->enable_fault_injection || !config->partial_fault || original_size == 0) {
        return original_size;
    }
    
    // Check if the operation should be affected
    if (!config_should_affect_operation(config->partial_fault->operations_mask, operation)) {
        return original_size;
    }
    
    // Check probability
    if (!check_probability(config->partial_fault->probability)) {
        return original_size;
    }
    
    // Calculate reduced size
    size_t new_size = (size_t)(original_size * config->partial_fault->factor);
    
    // Ensure at least 1 byte is processed
    if (new_size == 0) {
        new_size = 1;
    }
    
    LOG_INFO("Partial fault injected for %s: reduced size from %zu to %zu bytes (factor: %.2f)",
            fs_op_names[operation], original_size, new_size, config->partial_fault->factor);
    
    return new_size;
}

// Check if a fault should be triggered for an operation
bool should_trigger_fault(fs_op_type_t operation) {
    //LOG_INFO("should_trigger_fault: START for operation %d", operation);
    fs_config_t *config = config_get_global();
    //LOG_INFO("should_trigger_fault: Got config, enable_fault_injection=%s", config->enable_fault_injection ? "true" : "false");
    
    if (!config->enable_fault_injection) {
        //LOG_INFO("should_trigger_fault: Fault injection disabled, returning false");
        return false;
    }
    
    //LOG_INFO("should_trigger_fault: Counting operation...");
    // Count this operation - but be careful about timing/count-based faults
    // We'll count the operation, but check conditions with the OLD count
    // to avoid off-by-one errors in fault triggering
    int old_count = stats.operation_count;
    
    stats.operation_count++;
    stats.op_counts[operation]++;
    
    //LOG_INFO("should_trigger_fault: Operation counted: %d -> %d", old_count, stats.operation_count);
    
    //LOG_INFO("should_trigger_fault: Checking timing conditions...");
    // Check if any timing condition is met (using current time)
    if (check_timing_fault(operation)) {
        //LOG_INFO("Fault triggered for %s due to timing condition", fs_op_names[operation]);
        return true;
    }
    //LOG_INFO("should_trigger_fault: No timing fault");
    
    //LOG_INFO("should_trigger_fault: Checking operation count conditions...");
    // Check if any operation count condition is met (using the OLD count to avoid off-by-one)
    // Temporarily restore old count for the check
    int new_count = stats.operation_count;
    stats.operation_count = old_count;
    bool count_fault = check_operation_count_fault(operation);
    stats.operation_count = new_count;
    
    if (count_fault) {
        LOG_INFO("Fault triggered for %s due to operation count condition", fs_op_names[operation]);
        return true;
    }
    //LOG_INFO("should_trigger_fault: No operation count fault");
    
    //LOG_INFO("should_trigger_fault: END - returning false");
    // For all other fault types, we'll check them at the point of use
    // rather than here, since they need different handling
    
    return false;
}

// Update operation statistics (e.g., bytes processed)
void update_operation_stats(fs_op_type_t operation, size_t bytes) {
    if (operation == FS_OP_READ) {
        stats.bytes_read += bytes;
    } else if (operation == FS_OP_WRITE) {
        stats.bytes_written += bytes;
    }
    
    LOG_DEBUG("Operation stats: %s processed %zu bytes (total: read=%zu, written=%zu)",
             fs_op_names[operation], bytes, stats.bytes_read, stats.bytes_written);
}