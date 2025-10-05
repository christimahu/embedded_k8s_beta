# embedded_k8s

This repository contains a collection of shell scripts for setting up a Kubernetes cluster on ARM64 single-board computers.

The philosophy is to separate the hardware-specific setup from the role-specific configuration. This allows any prepared board (e.g., a Jetson Orin or a Raspberry Pi) to be used for any cluster role (e.g., control plane, worker, or support services).

---

## Directory Structure

- **`./`**
  - **[`README.md`](./README.md)**
- **`common/`**
  - **`helpers/`**
    - **[`README.md`](./common/helpers/README.md)**
    - `install_nvim.sh`
    - `init.lua`
  - **`k8s/`**
    - **[`README.md`](./common/k8s/README.md)**
    - **`setup/`**
      - `01_install_deps.sh`
      - `02_install_kube.sh`
    - **`control_plane/`**
      - `init.sh`
    - **`worker/`**
      - `join.sh`
  - **`services/`**
    - **[`README.md`](./common/services/README.md)**
    - `gen_certs.sh`
    - `setup_registry.sh`
- **`jetson_orin/`**
  - **[`README.md`](./jetson_orin/README.md)**
  - **`setup/`**
    - `01_config_headless.sh`
    - `02_clone_os_to_ssd.sh`
    - `03_set_boot_to_ssd.sh`
    - `04_strip_microsd_rootfs.sh`
    - `05_update_os.sh`
  - `factory_reset.sh`
- **`raspberry_pi/`**
  - **[`README.md`](./raspberry_pi/README.md)**

---

* ### `jetson_orin/`
    Contains the scripts to take a stock NVIDIA Jetson Orin Developer Kit from a fresh OS flash to a clean, headless state, ready for cluster configuration. This is the starting point for preparing a Jetson board.

* ### `raspberry_pi/`
    This directory will contain the equivalent setup scripts for a Raspberry Pi. (Currently a placeholder).

* ### `common/`
    Contains hardware-agnostic scripts for installing Kubernetes, its dependencies, shared services, and helper utilities. These scripts are run on a board *after* it has been prepared using its platform-specific setup scripts.
