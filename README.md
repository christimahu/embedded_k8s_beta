# embedded_k8s

This repository contains a collection of shell scripts for setting up a Kubernetes cluster on ARM64 single-board computers.

The philosophy is to separate the hardware-specific setup from the role-specific configuration. This allows any prepared board (e.g., a Jetson Orin or a Raspberry Pi) to be used for any cluster role (e.g., control plane, worker, or support services).

---

## Directory Structure

- **`./`**
  - **[`README.md`](./README.md)**
- **`COMMON/`**
  - **`HELPERS/`**
    - **[`README.md`](./common/helpers/README.md)**
    - `install_nvim.sh`
    - `init.lua`
  - **`K8S/`**
    - **[`README.md`](./common/k8s/README.md)**
    - **`SETUP/`**
      - `01_install_deps.sh`
      - `02_install_kube.sh`
    - **`CONTROL_PLANE/`**
      - `init.sh`
    - **`WORKER/`**
      - `join.sh`
  - **`SERVICES/`**
    - **[`README.md`](./common/services/README.md)**
    - `gen_certs.sh`
    - `setup_registry.sh`
- **`JETSON_ORIN/`**
  - **[`README.md`](./jetson_orin/README.md)**
  - **`SETUP/`**
    - `01_config_headless.sh`
    - `02_clone_os_to_ssd.sh`
    - `03_set_boot_to_ssd.sh`
    - `04_strip_microsd_rootfs.sh`
    - `05_update_os.sh`
    - `verify_setup.sh`
  - **`TOOLS/`**
    - `inspect_nvram.sh`
    - `clean_nvram.sh`
    - `reimage_microsd.sh`
- **`RASPBERRY_PI/`**
  - **[`README.md`](./raspberry_pi/README.md)**

---

## Overview

### `JETSON_orin/`
Contains the scripts to take a stock NVIDIA Jetson Orin Developer Kit from a fresh OS flash to a clean, headless state running from NVMe SSD, ready for cluster configuration. This is the starting point for preparing a Jetson board.

**Key directories:**
- `SETUP/` - Sequential scripts (01-05) to configure the device for headless operation and migrate to SSD
- `TOOLS/` - Utility scripts for NVRAM management and recovery operations

See the [Jetson Orin README](./jetson_orin/README.md) for detailed setup instructions.

### `RASPBERRY_PI/`
This directory will contain the equivalent setup scripts for a Raspberry Pi. (Currently a placeholder).

### `COMMON/`
Contains hardware-agnostic scripts for installing Kubernetes, its dependencies, shared services, and helper utilities. These scripts are run on a board *after* it has been prepared using its platform-specific setup scripts.

**Key directories:**
- `K8S/` - Core Kubernetes installation and cluster management
- `SERVICES/` - Shared cluster services (container registry, etc.)
- `HELPERS/` - Optional development tools (Neovim, etc.)

---

## Quick Start

### For Jetson Orin Devices

1. **Prepare the Hardware**
   - Flash JetPack to microSD card
   - Install microSD and NVMe SSD in the Jetson
   - Boot and complete Ubuntu setup

2. **Run Platform-Specific Setup** (with monitor/keyboard initially)
   ``` bash
   cd jetson_orin/setup
   sudo ./01_config_headless.sh
   sudo shutdown now
   ```

3. **Continue via SSH** (after powering back on)
   ``` bash
   ssh user@<jetson-ip>
   cd jetson_orin/setup
   sudo ./02_clone_os_to_ssd.sh
   sudo ./03_set_boot_to_ssd.sh
   sudo reboot
   
   # After reboot, SSH back in:
   sudo ./04_strip_microsd_rootfs.sh  # Optional but recommended
   sudo ./05_update_os.sh
   sudo ./verify_setup.sh
   ```

4. **Install Kubernetes**
   ``` bash
   cd common/k8s/setup
   sudo ./01_install_deps.sh
   sudo ./02_install_kube.sh
   ```

5. **Assign Cluster Role**
   
   For the first control plane node:
   ``` bash
   cd common/k8s/control_plane
   sudo ./init.sh
   ```
   
   For worker nodes:
   ``` bash
   cd common/k8s/worker
   sudo ./join.sh
   ```

---

## Important Concepts

### Hardware-Agnostic Design
The scripts are organized to separate hardware-specific setup (`JETSON_ORIN/`, `RASPBERRY_PI/`) from role-specific configuration (`COMMON/K8S/`). This means:
- A Jetson prepared with `JETSON_ORIN/setup` can become a control plane, worker, or services node
- A Raspberry Pi prepared with `RASPBERRY_PI/setup` can serve the same roles
- Cluster configuration is identical regardless of underlying hardware

### Jetson Boot Architecture
The Jetson Orin uses a UEFI boot process with these key components:
- **NVRAM**: Firmware settings stored on the motherboard (persists across storage re-imaging)
- **EFI System Partition (ESP)**: On microSD partition 10 (required for boot)
- **Extlinux Config**: `/boot/extlinux/extlinux.conf` on microSD (specifies root device)
- **Root Filesystem**: Can be on microSD or NVMe SSD

**The microSD card is permanently required** because it contains the ESP. The setup scripts move the root filesystem to SSD for performance while keeping the boot files on microSD.

### NVRAM Management
NVRAM (Non-Volatile RAM) stores UEFI boot configuration and persists across:
- Power cycles
- Storage device re-imaging
- OS updates

The `TOOLS/` directory provides utilities to inspect and manage NVRAM:
- `inspect_nvram.sh` - View current boot configuration
- `clean_nvram.sh` - Remove non-standard boot entries
- `reimage_microsd.sh` - Restore microSD to factory state

---

## Troubleshooting

### Jetson won't boot after setup
1. Check what device is mounted as root:
   ``` bash
   findmnt -n -o SOURCE /
   ```

2. Inspect NVRAM boot configuration:
   ``` bash
   sudo ./jetson_orin/tools/inspect_nvram.sh
   ```

3. If needed, restore to factory state:
   ``` bash
   # Must be run while booted from SSD
   sudo ./jetson_orin/tools/clean_nvram.sh
   sudo ./jetson_orin/tools/reimage_microsd.sh
   ```

### Verify script shows failures
Do not run `verify_setup.sh` until ALL setup steps (01-05) are complete. It checks for the final state, not intermediate states.

### Custom NVRAM boot entries detected
If `inspect_nvram.sh` shows entries numbered Boot0009 or higher:
- These were created by external tools or troubleshooting
- Remove them with `clean_nvram.sh`
- Nothing in this repository creates custom NVRAM entries

---

## Script Execution Order

### Platform Preparation (Jetson Orin)
Run these in sequence on each device:
1. `JETSON_ORIN/setup/01_config_headless.sh`
2. `JETSON_ORIN/setup/02_clone_os_to_ssd.sh`
3. `JETSON_ORIN/setup/03_set_boot_to_ssd.sh`
4. `JETSON_ORIN/setup/04_strip_microsd_rootfs.sh` (optional)
5. `JETSON_ORIN/setup/05_update_os.sh`
6. `JETSON_ORIN/setup/verify_setup.sh`

### Kubernetes Installation (All Platforms)
Run these on every node:
1. `COMMON/k8s/setup/01_install_deps.sh`
2. `COMMON/k8s/setup/02_install_kube.sh`

### Role Assignment
Run ONE of these per node:
- **First control plane:** `COMMON/k8s/control_plane/init.sh`
- **Workers or additional control planes:** `COMMON/k8s/worker/join.sh`

---

## Repository Philosophy

This repository is designed to be:
- **Educational**: Verbose comments explain the "why" behind each command
- **Modular**: Hardware setup is separate from cluster configuration
- **Repeatable**: Scripts can be run on multiple identical devices
- **Transparent**: No hidden state; all configuration is explicit and documented
- **Recoverable**: Tools provided to inspect state and restore to known-good configurations

Each script includes tutorial-style comments explaining Linux kernel modules, networking concepts, boot processes, and Kubernetes architecture. These scripts serve as both automation tools and learning resources.

---

## Contributing

When adding new scripts or modifying existing ones:
- Follow the tutorial-style commenting approach
- Include verbose explanations of WHY, not just WHAT
- Add pre-flight checks and clear error messages
- Test on actual hardware before committing
- Update relevant README files

---

## License

[Add your license information here]

---

## See Also

- [NVIDIA Jetson AI Lab - Initial Setup Guide](https://www.jetson-ai-lab.com/initial_setup_jon.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [NVIDIA Jetson Orin Developer Guide](https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/index.html)
