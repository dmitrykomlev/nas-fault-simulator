#ifndef LOG_H
#define LOG_H

#include <stdio.h>
#include <stdarg.h>
#include <time.h>

// Log levels
typedef enum {
    LOG_ERROR,  // Critical errors
    LOG_WARN,   // Warnings
    LOG_INFO,   // Informational messages
    LOG_DEBUG   // Detailed debug information
} log_level_t;

// Initialize logging system
void log_init(const char *log_file, log_level_t level);

// Close logging system
void log_close(void);

// Log a message with specific level
void log_message(log_level_t level, const char *format, ...);

// Helper macros for easier usage
#define LOG_ERROR(fmt, ...) log_message(LOG_ERROR, fmt, ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)  log_message(LOG_WARN, fmt, ##__VA_ARGS__)
#define LOG_INFO(fmt, ...)  log_message(LOG_INFO, fmt, ##__VA_ARGS__)
#define LOG_DEBUG(fmt, ...) log_message(LOG_DEBUG, fmt, ##__VA_ARGS__)

#endif // LOG_H