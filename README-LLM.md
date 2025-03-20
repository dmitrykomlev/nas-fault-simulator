# NAS Emulator Project - Context Document

> **Note**: This is a private context document to maintain knowledge continuity in AI assistant conversations about this project. Not intended for public documentation.

## Project Overview

The NAS Emulator is a testing tool designed to simulate fault scenarios in Network Attached Storage systems. Its primary purpose is to enable QA and development teams to test backup software against various failure modes that are difficult to reproduce with real hardware.

### Key Problem Statement

When backing up large datasets (terabytes) to NAS devices, various failure modes can occur:
- Silent data corruption (NAS confirms write but doesn't actually persist data)
- Network disruptions during long operations
- Intermittent failures based on timing or operation count
- Data integrity issues during checkpoint operations

These failures are difficult to reproduce reliably with real hardware, making systematic testing nearly impossible.

## Target Functionality

The NAS Emulator will simulate a real NAS device with configurable fault injection capabilities:
- Appear as a standard network share (SMB)
- Allow configuration of various failure modes
- Support large data transfers (hundreds of GBs)
- Provide monitoring and logging of system behavior
- Enable precise control over when and how failures occur

## Architecture Components

### 1. FUSE Filesystem Layer
- Core component that intercepts filesystem operations
- Implements configurable fault injection at the I/O level
- Provides hooks for silent corruption, partial writes, timing-based failures
- Exposes API for configuration and monitoring

### 2. Network Layer
- SMB server implementation
- Network disruption simulation capabilities
- Authentication and share configuration
- Protocol-level fault injection

### 3. Backend Service
- RESTful API for configuration and control
- Metrics collection and aggregation
- State management for fault scenarios
- Coordination between components

### 4. Web Dashboard
- Real-time activity monitoring
- Graphical metrics display
- Fault configuration interface
- Storage analytics
- Share configuration

### 5. Storage Backend
- Support for large volume management
- Performance optimization for backup workloads
- Data persistence across container restarts

## Fault Injection Capabilities

1. **Silent Data Corruption**
   - Report success but don't write data
   - Write corrupted/modified data
   - Partial writes

2. **Network Disruptions**
   - Complete disconnections
   - Intermittent connectivity
   - Bandwidth throttling
   - Latency introduction
   - Packet loss

3. **Timing-based Failures**
   - Fail after X minutes of operation
   - Fail at specific times of day
   - Periodic failures

4. **Operation-based Failures**
   - Fail every Nth operation
   - Fail after X GB transferred
   - Fail during specific operation types (writes vs. reads)

5. **Protocol-specific Issues**
   - SMB session termination
   - Authentication failures
   - Share permission changes

## Implementation Strategy

### Phase 1: Core Functionality
- Basic FUSE implementation with passthrough operations
- Simple SMB server configuration
- Docker container setup
- Basic configuration API

### Phase 2: Fault Injection
- Implement core fault injection mechanisms
- Add silent corruption capabilities
- Implement network disruption simulation

### Phase 3: Dashboard & Monitoring
- Basic web UI for configuration
- Metrics collection and display
- Operation logging

### Phase 4: Advanced Features
- Complex failure scenarios
- Scheduled/sequenced fault injection
- Performance optimization for large transfers

## Technology Stack

- **FUSE**: ANSI C implementation with makefiles for filesystem interception
- **Docker**: For packaging, distribution, and development environments
- **Samba/SMB**: For network share protocol
- **Golang**: For backend service implementation
- **React with TypeScript**: For web dashboard, using Material-UI or Chakra UI components
- **Prometheus/Grafana**: For metrics collection and visualization
- **Redis/SQLite**: For state management

## Development Notes

### FUSE Implementation Considerations
- ANSI C implementation with makefiles
- Need to handle large file operations efficiently
- Must accurately simulate real NAS behavior under normal conditions
- Should support custom error injection on specific operations

### Development Workflow
- Component-focused development with separate Docker environments for each component
- Multi-stage Docker builds for production images
- Separate development Dockerfiles for FUSE driver, backend service, and web UI
- Volume mounting for rapid iteration during development
- Automated testing for individual components and integrated system

### Docker Deployment
- Volume mapping for large storage requirements
- Network configuration for SMB exposure
- Resource limits for realistic performance
- Multi-stage builds to minimize final image size

### Testing Strategy
- Component-level unit tests
- Integration with actual backup software
- Validation of fault injection behavior
- Performance testing with large datasets
- Automated CI/CD pipeline

## Project Status Tracking

This section will be updated as development progresses:

- [ ] Project initialization
- [ ] Core FUSE implementation
- [ ] Basic SMB configuration
- [ ] Docker container setup
- [ ] Configuration API
- [ ] Basic fault injection
- [ ] Web dashboard skeleton
- [ ] Metrics collection
- [ ] Advanced fault scenarios
- [ ] Performance optimization
- [ ] Documentation and distribution

## Open Questions/Decisions

1. Storage backend strategy for large datasets
2. Authentication mechanism for the dashboard
3. Level of SMB protocol compliance required
4. Performance targets under load
5. Additional fault scenarios to implement