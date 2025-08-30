# Makefile for lensline.nvim bug reproduction environment
# Simplifies Docker operations for bug reporters and maintainers

# Neovim version (default to latest, or specify like: make run NVIM_VERSION=v0.9.4)
NVIM_VERSION ?= latest

.PHONY: help build run clean

# Default target
help:
	@echo "Lensline Bug Reproduction"
	@echo ""
	@echo "Commands:"
	@echo "  make run               - Build and run reproduction environment"
	@echo "  make clean             - Remove Docker image"
	@echo ""
	@echo "Options:"
	@echo "  NVIM_VERSION=v0.9.4    - Specify Neovim version (default: latest)"
	@echo ""
	@echo "Usage:"
	@echo "  1. git clone https://github.com/orbarila/lensline.nvim.git"
	@echo "  2. make run"
	@echo "  3. Neovim starts automatically with lensline configured"
	@echo ""
	@echo "Note: Multi-architecture support (ARM64/x86_64)"

# Build the Docker image
build:
	@echo "Building lensline reproduction environment with Neovim $(NVIM_VERSION)..."
	docker build --build-arg NVIM_VERSION=$(NVIM_VERSION) -t lensline-repro .
	@echo "Build complete! Use 'make run' to start the environment."

# Build and run the reproduction environment
run: build
	@echo "Starting reproduction environment with Neovim..."
	docker run -it --rm lensline-repro

# Clean up Docker image
clean:
	docker rmi lensline-repro 2>/dev/null || true