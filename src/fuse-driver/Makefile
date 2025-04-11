CC = gcc
CFLAGS = -Wall -Wextra -Werror -g $(shell pkg-config fuse --cflags)
LIBS = $(shell pkg-config fuse --libs) -lpthread

# Directory for config files
CONFDIR = /etc/nas-emu

TARGET = nas-emu-fuse
SRCDIR = src
OBJDIR = obj

SOURCES = $(SRCDIR)/fs_fault_injector.c \
          $(SRCDIR)/fs_operations.c \
          $(SRCDIR)/fault_injector.c \
          $(SRCDIR)/log.c \
          $(SRCDIR)/config.c

CONFIG_FILES = nas-emu-fuse.conf

OBJECTS = $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)

.PHONY: all clean install config

$(OBJDIR):
	mkdir -p $(OBJDIR)

all: $(OBJDIR) $(TARGET) config

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LIBS)

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJECTS)
	rm -rf $(OBJDIR)

install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/
	mkdir -p $(CONFDIR)
	install -m 644 $(CONFIG_FILES) $(CONFDIR)/

config:
	mkdir -p $(CONFDIR)
	[ -f $(CONFDIR)/nas-emu-fuse.conf ] || install -m 644 nas-emu-fuse.conf $(CONFDIR)/