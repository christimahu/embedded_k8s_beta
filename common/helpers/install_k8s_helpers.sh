# Helper and Utility Scripts

This directory contains optional, quality-of-life scripts for installing useful command-line tools and developer utilities.

These scripts are not required for the cluster to function but can significantly improve the experience of managing and developing on your Kubernetes cluster.

---

## Available Scripts

### **Generic Development Tools**

* **`install_neovim.sh`**:
    Installs the Neovim text editor with a pre-configured setup optimized for editing Kubernetes configs and other text files. Provides a modern, terminal-based editing experience without heavy dependencies.

* **`vim_quick_reference.sh`**:
    A quick reference guide for Vim/Neovim commands. Run this anytime you forget a keybinding or need to look up common operations.

---

### **Kubernetes Extras**

* **`install_k8s_extras.sh`**:
    Installs a suite of stable, production-ready CLI tools for enhancing Kubernetes operations. These are the standard tools used by k8s administrators and developers worldwide to improve workflow efficiency.
    - **jq** - JSON processor for parsing kubectl output
    - **yq** - YAML processor for editing k8s configs
    - **helm** - Kubernetes package manager
    - **kubectx** - Fast context switching between clusters
    - **kubens** - Fast namespace switching
    - **k9s** - A powerful terminal UI for managing Kubernetes

---

### **AI-Powered Kubernetes Tools**

* **`install_k8s_ai.sh`**:
    Installs AI-native tools that use large language models to enhance Kubernetes operations, from natural language `kubectl` commands to AI-powered diagnostics.
    
    These tools represent the cutting edge of AI-assisted infrastructure management and align with this repo's AI-native philosophy.

---

### **Chaos Engineering**

* **`install_chaos_engineering.sh`**:
    Installs Chaos Mesh, a CNCF chaos engineering platform for Kubernetes. Chaos engineering is the practice of intentionally injecting failures to test system resilience. Essential for learning how distributed systems behave under failure conditions.

---

## Installation Order

You can install these scripts in any order, but the recommended sequence respects their dependencies:

1.  **`install_neovim.sh`** - Set up your text editor first for editing configs.
2.  **`install_k8s_extras.sh`** - Install the foundational admin tools. **This is a prerequisite for `install_chaos_engineering.sh`** because it installs Helm.
3.  **`install_k8s_ai.sh`** - Optional: Add AI-powered tools.
4.  **`install_chaos_engineering.sh`** - Optional: Set up the chaos engineering platform.

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
