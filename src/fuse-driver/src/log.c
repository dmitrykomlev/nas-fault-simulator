#include "log.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

// Log file handle
static FILE *log_file_handle = NULL;

// Current log level
static log_level_t current_log_level = LOG_INFO;

// Mutex for thread safety
static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

// Log level strings
static const char *level_strings[] = {
    "ERROR",
    "WARN ",
    "INFO ",
    "DEBUG"
};

// Initialize logging system
void log_init(const char *log_file, log_level_t level) {
    pthread_mutex_lock(&log_mutex);
    
    // Set log level
    current_log_level = level;
    
    // Close previous log file if open
    if (log_file_handle != NULL && log_file_handle != stdout) {
        fclose(log_file_handle);
    }
    
    // Open log file
    if (log_file == NULL || strcmp(log_file, "stdout") == 0) {
        log_file_handle = stdout;
    } else {
        log_file_handle = fopen(log_file, "a");
        if (log_file_handle == NULL) {
            fprintf(stderr, "Failed to open log file %s, using stdout\n", log_file);
            log_file_handle = stdout;
        }
    }
    
    // Log initialization
    time_t now = time(NULL);
    char time_str[26];
    ctime_r(&now, time_str);
    time_str[24] = '\0';  // Remove trailing newline
    
    fprintf(log_file_handle, "--- Log initialized at %s ---\n", time_str);
    fflush(log_file_handle);
    
    pthread_mutex_unlock(&log_mutex);
}

// Close logging system
void log_close(void) {
    pthread_mutex_lock(&log_mutex);
    
    if (log_file_handle != NULL && log_file_handle != stdout) {
        fclose(log_file_handle);
    }
    log_file_handle = NULL;
    
    pthread_mutex_unlock(&log_mutex);
}

// Log a message with specific level
void log_message(log_level_t level, const char *format, ...) {
    // Skip if level is higher than current level
    if (level > current_log_level || log_file_handle == NULL) {
        return;
    }
    
    pthread_mutex_lock(&log_mutex);
    
    // Get current time
    time_t now = time(NULL);
    struct tm tm_now;
    localtime_r(&now, &tm_now);
    
    // Print log header: [LEVEL] [Time]
    fprintf(log_file_handle, "[%s] [%02d:%02d:%02d] ", 
            level_strings[level],
            tm_now.tm_hour, tm_now.tm_min, tm_now.tm_sec);
    
    // Print log message
    va_list args;
    va_start(args, format);
    vfprintf(log_file_handle, format, args);
    va_end(args);
    
    // Add newline if not present
    if (format[strlen(format) - 1] != '\n') {
        fprintf(log_file_handle, "\n");
    }
    
    fflush(log_file_handle);
    
    pthread_mutex_unlock(&log_mutex);
}