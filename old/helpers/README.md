# Helper and Utility Scripts

This directory contains optional, quality-of-life scripts for installing useful command-line tools and developer utilities.

These scripts are not required for the cluster to function but can significantly improve the experience of managing and developing on your Kubernetes cluster.

---

## Available Scripts

### **Generic Development Tools**

* **`install_nvim.sh`**:
    Installs the Neovim text editor with a pre-configured setup optimized for editing Kubernetes configs, Python, Rust, and Go. Includes LSP (Language Server Protocol) for intelligent code editing, syntax highlighting, and useful plugins. Provides a modern, terminal-based editing experience.

* **`init.lua`**:
    The configuration file for Neovim. Uses the Packer plugin manager to install language servers, file browser, fuzzy finder, and other productivity tools. Extensively documented with tutorial-style comments explaining every setting.

* **`vim_quick_reference.sh`**:
    A quick reference guide for Vim/Neovim commands. Run this anytime you forget a keybinding or need to look up common operations.

---

### **Kubernetes Tools**

* **`install_k8s_tools.sh`**:
    Installs stable, production-ready CLI tools for Kubernetes operations:
    - **jq** - JSON processor for parsing kubectl output
    - **yq** - YAML processor for editing k8s configs
    - **helm** - Kubernetes package manager
    - **kubectx** - Fast context switching between clusters
    - **kubens** - Fast namespace switching
    - **k9s** - Beautiful terminal UI for Kubernetes
    
    These are the standard tools used by k8s administrators and developers worldwide.

---

### **AI-Powered Kubernetes Tools**

* **`install_k8s_ai.sh`**:
    Installs AI-native tools that use large language models to enhance Kubernetes operations:
    - **kubectl-ai** - Natural language interface to kubectl (Google Cloud project)
    - **k8sgpt** - AI-powered cluster diagnostics and troubleshooting (CNCF Sandbox)
    
    These tools require API keys for AI services (OpenAI, Azure OpenAI, or local models). They represent the cutting edge of AI-assisted infrastructure management and align with this repo's AI-native philosophy.

---

### **Chaos Engineering**

* **`install_chaos_engineering.sh`**:
    Installs Chaos Mesh, a CNCF chaos engineering platform for Kubernetes. Chaos engineering is the practice of intentionally injecting failures to test system resilience.
    
    Chaos Mesh can simulate:
    - Pod failures (kill pods, make them unavailable)
    - Network chaos (latency, packet loss, partitions)
    - Resource stress (CPU/memory pressure)
    - I/O failures (slow disks, read/write errors)
    - Time skew (shift system clocks)
    
    Essential for learning how distributed systems behave under failure conditions and building confidence in your cluster's reliability.

---

## Installation Order

You can install these scripts in any order, but the recommended sequence is:

1. **`install_nvim.sh`** - Set up your text editor first for editing configs
2. **`install_k8s_tools.sh`** - Install stable k8s tools (required for some other scripts)
3. **`install_k8s_ai.sh`** - Optional: Add AI-powered tools
4. **`install_chaos_engineering.sh`** - Optional: Set up chaos engineering platform

---

## Philosophy

This repo encourages hands-on learning and experimentation with modern cloud-native workflows. The tools in this directory support that goal by:

- **Reducing friction** - Good tooling makes experimentation faster and more enjoyable
- **Teaching best practices** - These are industry-standard tools used in production
- **Enabling AI-native workflows** - Embrace AI assistants as first-class tools
- **Building resilience** - Chaos engineering teaches failure modes through practice

All scripts follow a tutorial-style documentation approach, explaining not just *how* to use the tools, but *why* they exist and when to use them.

---

## Notes

- All scripts must be run with `sudo`
- Scripts are idempotent - safe to run multiple times
- Each script includes extensive comments explaining concepts and usage
- Tools are installed for the user who invoked `sudo`, not for root

---

## Contributing

When adding new scripts to this directory:
- Follow the established tutorial-style commenting approach
- Include "why this tool exists" explanations
- Provide usage examples in the output
- Test on actual ARM64 hardware (Jetson/Raspberry Pi)
- Update this README with the new tool
