# Contributing to Cosmos Docker

Thank you for your interest in contributing to the Cosmos Docker project! This document provides guidelines for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/cosmos-docker.git`
3. Create a feature branch: `git checkout -b feature/my-new-feature`

## Development Setup

1. Ensure you have Docker and Docker Compose installed
2. Copy the environment file: `cp cosmoshub-4.env .env` (or any other chain configuration)
3. Test your changes: `make start`

## Testing Changes

Before submitting a pull request:

1. Test the build process: `make clean && make start`
2. Verify the node starts successfully
3. Check logs for any errors: `make logs`
4. Test the monitoring script: `make monitor`

## Submitting Changes

1. Ensure your code follows the existing style
2. Update documentation if necessary
3. Test your changes thoroughly
4. Commit with a clear message
5. Push to your fork and submit a pull request

## Reporting Issues

When reporting issues, please include:

- Operating system and version
- Docker and Docker Compose versions
- Error logs (`make logs`)
- Steps to reproduce the issue
- Expected vs actual behavior

## Code Style

- Use clear, descriptive variable names
- Add comments for complex configurations
- Follow Docker best practices
- Keep environment variables organized and documented

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
