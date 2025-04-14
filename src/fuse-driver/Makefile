CC=gcc
CFLAGS=-Wall -g -D_FILE_OFFSET_BITS=64 `pkg-config fuse --cflags`
LDFLAGS=`pkg-config fuse --libs` -lpthread

# Target executable
TARGET=nas-emu-fuse

# Source files
SRC=src/fs_fault_injector.c src/fs_operations.c src/fault_injector.c src/log.c src/config.c

# Object files directory
OBJ_DIR=obj

# Object files
OBJ=$(patsubst src/%.c,$(OBJ_DIR)/%.o,$(SRC))

# Include environment variables from .env if it exists
-include ../.env

# Default values for environment variables
NAS_MOUNT_POINT ?= /mnt/nas-mount
NAS_STORAGE_PATH ?= /var/nas-storage
NAS_LOG_FILE ?= /var/log/nas-emu.log
NAS_LOG_LEVEL ?= 2

# Append environment variable definitions to CFLAGS
CFLAGS += -DNAS_MOUNT_POINT=\"$(NAS_MOUNT_POINT)\" \
         -DNAS_STORAGE_PATH=\"$(NAS_STORAGE_PATH)\" \
         -DNAS_LOG_FILE=\"$(NAS_LOG_FILE)\" \
         -DNAS_LOG_LEVEL=$(NAS_LOG_LEVEL)

all: $(TARGET)

# Create object directory if it doesn't exist
$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# Compile source files
$(OBJ_DIR)/%.o: src/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Link target executable
$(TARGET): $(OBJ)
	$(CC) -o $(TARGET) $(OBJ) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(OBJ)
	rm -rf $(OBJ_DIR)

.PHONY: all clean