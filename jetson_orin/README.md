# NVIDIA Jetson Orin Setup Scripts

This directory contains scripts for transforming an NVIDIA Jetson Orin Developer Kit from its stock, desktop-oriented state into a production-ready, headless Kubernetes node optimized for GPU computing and distributed AI workloads.

---

## Table of Contents

- [Overview](#overview)
- [Understanding the Jetson Boot Architecture](#understanding-the-jetson-boot-architecture)
- [Directory Structure](#directory-structure)
- [Installation Workflows](#installation-workflows)
  - [Recommended: With NVMe SSD](#recommended-workflow-with-nvme-ssd)
  - [Alternative: MicroSD Only](#alternative-workflow-microsd-only)
- [Understanding the NVRAM Tools](#understanding-the-nvram-tools)
- [Troubleshooting](#troubleshooting)
- [Hardware Requirements](#hardware-requirements)
- [Additional Resources](#additional-resources)

---

## Overview

The Jetson Orin ships as a desktop computer with Ubuntu, a graphical interface, and swap memory enabled. For production Kubernetes and GPU workloads, this default configuration is problematic:

**Default State Issues:**
- ❌ Desktop GUI wastes GPU memory and CPU cycles
- ❌ Swap memory conflicts with Kubernetes requirements
- ❌ MicroSD card I/O is too slow for container image pulls
- ❌ Requires monitor and keyboard for management

**After These Scripts:**
- ✅ Headless server accessible via SSH
- ✅ OS running from fast NVMe SSD (optional but highly recommended)
- ✅ Swap disabled (Kubernetes requirement)
- ✅ Desktop GUI removed (resource efficiency)
- ✅ System hardened and optimized for 24/7 operation

**Time Investment:** 30-45 minutes per node (mostly automated)

---

## Understanding the Jetson Boot Architecture

The Jetson Orin uses a **UEFI-based boot process** similar to modern PCs, but with critical differences that affect how you manage the device. Understanding this architecture is essential for troubleshooting and maintenance.

### The Boot Chain

```
Power On
    ↓
UEFI Firmware (QSPI-NOR flash on motherboard)
    ↓
Reads NVRAM (boot configuration stored on motherboard)
    ↓
Attempts boot from entries in boot order (Boot0001, Boot0008, etc.)
    ↓
Loads bootloader from EFI System Partition (ESP) on microSD partition 10
    ↓
Bootloader reads /boot/extlinux/extlinux.conf (on microSD partition 1)
    ↓
Mounts root filesystem (can be microSD or NVMe SSD)
    ↓
Linux boots
```

### Critical Concept: The MicroSD Card is Permanently Required

**You cannot remove the microSD card.** Here's why:

The microSD card contains **15 partitions** created by NVIDIA's JetPack flashing process:
- **Partition 1:** Root filesystem (what we migrate to SSD)
- **Partition 10:** EFI System Partition (ESP) - **Required for boot**
- **Partitions 2-9, 11-15:** Firmware, device trees, recovery data

**The ESP on partition 10 contains `BOOTAA64.efi`** - the UEFI bootloader binary that the firmware executes at startup. Without this partition, the Jetson cannot boot.

### What We Actually Do

Our setup scripts **do not** move everything to the SSD. Instead:

1. **MicroSD retains:**
   - EFI System Partition (partition 10) - Required for boot
   - `/boot` directory (partition 1) - Bootloader configuration
   - All other firmware partitions (2-9, 11-15)

2. **SSD receives:**
   - Root filesystem (/, /home, /var, etc.)
   - All application data and container images
   - 100× faster I/O for Kubernetes operations

3. **Boot process:**
   - Firmware loads from microSD ESP → Bootloader reads config from microSD `/boot` → Root filesystem runs from SSD

**Result:** Fast SSD performance for the OS, but microSD remains installed for boot firmware.

### NVRAM: Non-Volatile RAM

**NVRAM** is a small chip on the Jetson motherboard that stores UEFI firmware settings, including boot entry configurations. NVRAM is:

- ✅ Persistent across power cycles
- ✅ Persistent across storage re-imaging
- ✅ **Independent of microSD and SSD contents**
- ❌ **Cannot** be cleared by formatting the microSD
- ❌ **Cannot** be cleared by replacing the SSD

**Why This Matters:**

If you've troubleshooted boot issues using external tools, you may have custom boot entries in NVRAM (Boot0009, Boot000A, etc.). These entries can cause the Jetson to boot via unexpected paths, bypassing the standard configuration.

The `tools/` scripts in this directory help you inspect and clean NVRAM to ensure predictable boot behavior.

### Standard NVIDIA Boot Entries

A factory-fresh Jetson has these NVRAM boot entries:
- **Boot0000:** UEFI Setup Menu
- **Boot0001:** MicroSD Card ESP (standard boot path)
- **Boot0002-0005:** Network boot options (PXE, HTTP)
- **Boot0006:** Boot Manager Menu  
- **Boot0007:** UEFI Shell
- **Boot0008:** NVMe SSD (if detected)

**Any entry numbered Boot0009 or higher was created by external tools** (not by these scripts) and may need investigation.

---

## Directory Structure

```
jetson_orin/
├── README.md                          # This file
├── setup/                             # Sequential setup scripts
│   ├── 01_config_headless.sh          # Configure for SSH, disable GUI
│   ├── 02_clone_os_to_ssd.sh          # Copy OS to NVMe SSD
│   ├── 03_set_boot_to_ssd.sh          # Update bootloader to use SSD
│   ├── 04_strip_microsd_rootfs.sh     # Remove OS files from microSD (security)
│   ├── 05_update_os.sh                # Apply system updates
│   └── 06_verify_setup.sh             # Validate final configuration
└── tools/                             # Maintenance and recovery utilities
    ├── inspect_nvram.sh               # View UEFI boot configuration
    ├── clean_nvram.sh                 # Remove custom boot entries
    └── reimage_microsd.sh             # Restore microSD to factory state
```

### Setup Scripts (`setup/`)

**Sequential scripts to prepare a Jetson for Kubernetes.** Run in order (01→02→03→04→05→06).

- Scripts 02, 03, 04 are **optional** if you don't have an NVMe SSD
- All scripts include extensive tutorial comments
- Each script has pre-flight checks to prevent errors

### Tools Scripts (`tools/`)

**Diagnostic and recovery utilities.** Run as needed, not part of the normal setup sequence.

- Read-only diagnostics (inspect_nvram.sh)
- Recovery operations (clean_nvram.sh, reimage_microsd.sh)
- Used for troubleshooting boot issues

---

## Installation Workflows

### Hardware Requirements

**Minimum (MicroSD Only):**
- NVIDIA Jetson Orin Nano Developer Kit
- MicroSD card (64GB+, Class 10 or better)
- Ethernet cable and network connection
- USB keyboard and HDMI monitor (for initial setup only)
- Power supply

**Recommended (With SSD):**
- All of the above, plus:
- NVMe M.2 SSD (256GB+ recommended, M.2 2280 form factor)

**For Distributed GPU Clusters:**
- Multiple Jetson units (3+ for meaningful distributed training)
- Network switch for dedicated cluster network
- Static IP assignments or DHCP reservations

### Pre-Installation: Flash JetPack to MicroSD

Before running any scripts, flash the official NVIDIA JetPack OS image to your microSD card:

1. **Download JetPack SD Card Image:**
   - Visit: https://developer.nvidia.com/embedded/jetpack
   - Download the SD card image for Jetson Orin Nano Developer Kit
   - File will be named similar to: `jetson-orin-nano-sd-card-image-rXX.X.X.img.xz`

2. **Flash to MicroSD Card:**
   - Use **Balena Etcher** (https://www.balena.io/etcher/) or `dd` on Linux
   - Flash the downloaded image to your microSD card
   - This creates the required 15-partition layout with ESP

3. **Initial Boot:**
   - Insert microSD into Jetson
   - Connect monitor, keyboard, and Ethernet
   - Power on and complete the Ubuntu initial setup wizard (oem-config)
   - Create a user account, set timezone, etc.

4. **Clone This Repository:**
   ```bash
   git clone https://github.com/yourusername/embedded_k8s.git
   cd embedded_k8s
   ```

Now proceed with one of the workflows below.

---

## Recommended Workflow: With NVMe SSD

This workflow provides **maximum performance and reliability** for Kubernetes workloads. The NVMe SSD delivers:
- 100× faster sequential I/O vs microSD
- Lower latency for container operations
- Better reliability for 24/7 operation
- More endurance for write-heavy workloads

**Total Time:** ~30-40 minutes per node

### Phase 1: Configure Headless Mode (With Monitor/Keyboard)

**Location:** At the physical device with monitor and keyboard attached

```bash
cd embedded_k8s/jetson_orin/setup
sudo ./01_config_headless.sh
```

**What this does:**
- Sets a static IP address for reliable SSH access
- Changes hostname to identify the node
- Removes desktop GUI (frees ~1-2GB RAM)
- Disables swap memory (Kubernetes requirement)
- Configures system for headless operation

**After completion:**
```bash
sudo shutdown now
```

**Disconnect monitor and keyboard. All remaining steps are via SSH.**

### Phase 2: OS Migration to SSD (Via SSH)

**Location:** SSH session from your workstation

Power the Jetson back on and SSH in:

```bash
ssh user@<jetson-static-ip>
cd embedded_k8s/jetson_orin/setup
```

#### Step 2a: Clone OS to SSD

```bash
sudo ./02_clone_os_to_ssd.sh
```

**What this does:**
- Partitions and formats the NVMe SSD (destroys any existing data)
- Performs a complete byte-for-byte copy of the configured OS
- Configures the SSD to mount the microSD's ESP at `/boot/efi`
- Takes 10-15 minutes depending on SSD speed

**Important:** After this script, you have **two identical copies** of the OS (microSD and SSD), but the system is still booting from microSD.

#### Step 2b: Configure Boot to Use SSD

```bash
sudo ./03_set_boot_to_ssd.sh
```

**What this does:**
- Modifies `/boot/extlinux/extlinux.conf` on the microSD
- Changes `root=` parameter to point to SSD's UUID
- Next boot will use SSD as root filesystem

**Critical:** This change only takes effect after reboot.

```bash
sudo reboot
```

**After reboot, verify you're running from SSD:**

```bash
findmnt -n -o SOURCE /
# Should show: /dev/nvme0n1p1
```

If you see `/dev/mmcblk0p1`, the boot configuration didn't work. See [Troubleshooting](#troubleshooting).

#### Step 2c: Security Hardening (Optional but Recommended)

```bash
sudo ./04_strip_microsd_rootfs.sh
```

**What this does:**
- Removes OS files from microSD partition 1, keeping only `/boot`
- Prevents someone with physical access from booting the old OS
- Security best practice after confirming SSD boot works

**Why this matters:** Without this step, an attacker could modify the bootloader config to boot from the old, unpatched OS on the microSD.

### Phase 3: System Updates and Verification

#### Step 3a: Apply Updates

```bash
sudo ./05_update_os.sh
```

**What this does:**
- Runs `apt update && apt upgrade` to install latest packages
- Applies security patches
- Faster on SSD than microSD (3-5 minutes vs 15-20 minutes)

#### Step 3b: Verify Configuration

```bash
sudo ./06_verify_setup.sh
```

**What this does:**
- Checks that OS is running from SSD
- Verifies bootloader points to SSD
- Confirms swap is disabled
- Validates headless configuration
- Checks that microSD was stripped (if step 04 was run)

**Only run after ALL setup steps are complete.** This validates the final state.

### What You Have Now

A production-ready Jetson node:
- ✅ Running from fast NVMe SSD
- ✅ Headless (SSH only)
- ✅ Swap disabled
- ✅ Desktop GUI removed
- ✅ Security hardened
- ✅ Fully updated
- ✅ Ready for Kubernetes installation

**Next Steps:**
```bash
cd ../../k8s/node_setup
sudo ./01_install_deps.sh
sudo ./02_install_kube.sh
```

---

## Alternative Workflow: MicroSD Only

If you don't have an NVMe SSD, you can still use the Jetson for Kubernetes. **This is acceptable for:**
- Learning and experimentation
- Development workloads
- Non-production clusters
- Budget-constrained projects

**Not recommended for:**
- Production workloads
- 24/7 operation
- Write-heavy applications (container registries, databases)
- High-performance GPU training jobs

**Total Time:** ~15-20 minutes per node

### Step 1: Configure Headless Mode

Same as the SSD workflow:

```bash
cd embedded_k8s/jetson_orin/setup
sudo ./01_config_headless.sh
sudo shutdown now
```

Disconnect monitor/keyboard, power on, SSH in.

### Step 2: Skip SSD Scripts

**Do NOT run:**
- ❌ `02_clone_os_to_ssd.sh` (requires SSD)
- ❌ `03_set_boot_to_ssd.sh` (requires SSD)
- ❌ `04_strip_microsd_rootfs.sh` (only makes sense after SSD migration)

### Step 3: Apply Updates

```bash
cd embedded_k8s/jetson_orin/setup
sudo ./05_update_os.sh
```

**Note:** This will take 15-20 minutes on microSD (vs 3-5 minutes on SSD) due to slower I/O.

### Step 4: Skip Verification

**Do NOT run:**
- ❌ `06_verify_setup.sh` (expects SSD configuration)

Instead, manually verify:
```bash
# Confirm running from microSD (expected)
findmnt -n -o SOURCE /
# Should show: /dev/mmcblk0p1

# Confirm swap is disabled
swapon --show
# Should show nothing

# Confirm headless
systemctl get-default
# Should show: multi-user.target
```

### What You Have Now

A basic Kubernetes-ready Jetson node:
- ✅ Headless (SSH only)
- ✅ Swap disabled
- ✅ Desktop GUI removed
- ✅ Fully updated
- ⚠️ Running from slower microSD storage

**Performance Impact:**
- Container image pulls: 3-5× slower
- Pod startup times: 2-3× slower
- Persistent volume I/O: Significantly slower
- MicroSD wear: Higher with write-heavy workloads

**Next Steps:**
```bash
cd ../../k8s/node_setup
sudo ./01_install_deps.sh
sudo ./02_install_kube.sh
```

**Upgrade Path:** You can add an SSD later and run scripts 02-04 to migrate without reinstalling.

---

## Understanding the NVRAM Tools

The `tools/` directory contains utilities for managing NVRAM boot configuration. These are **not part of the normal setup workflow** - they're for diagnostics and recovery.

### When to Use These Tools

**Scenario 1: Troubleshooting Boot Issues**

You changed something and the Jetson won't boot, or it's booting from an unexpected device.

**Solution:** Use `inspect_nvram.sh` to see what the firmware thinks it should boot from.

**Scenario 2: Custom Boot Entries Detected**

You or someone else used external tools (UEFI shell, efibootmgr manually, etc.) that created custom boot entries.

**Solution:** Use `clean_nvram.sh` to remove non-standard entries and restore factory boot configuration.

**Scenario 3: Complete Factory Reset**

You want to start over from scratch.

**Solution:** Use `clean_nvram.sh` + `reimage_microsd.sh` for a complete reset (must be run from SSD).

### Tool 1: inspect_nvram.sh (Read-Only Diagnostic)

**Purpose:** View the current UEFI boot configuration stored in NVRAM.

**When to use:**
- Before running clean_nvram.sh (to see what will be removed)
- When troubleshooting boot problems
- To verify boot configuration after changes
- Any time you're curious about the boot state

**Usage:**
```bash
cd embedded_k8s/jetson_orin/tools
sudo ./inspect_nvram.sh
```

**Example output:**
```
BootCurrent: 0001
BootOrder: 0001,0008,0002,0003,0004,0005,0006,0007,0000

Boot0000* Enter Setup
Boot0001* UEFI SD Device
Boot0008* UEFI Samsung SSD 980
```

**What this means:**
- Currently booted from Boot0001 (microSD ESP)
- Firmware tries Boot0001 first, then Boot0008 (SSD), then network options
- All entries are standard NVIDIA entries (0000-0008)

**Red flag example:**
```
BootCurrent: 0009
Boot0009* Custom Boot Entry
```

This indicates a non-standard entry that may need investigation.

**This script makes NO CHANGES** - it's purely informational.

### Tool 2: clean_nvram.sh (Remove Custom Boot Entries)

**Purpose:** Remove custom boot entries from NVRAM, restoring factory boot configuration.

**When to use:**
- After external troubleshooting that modified NVRAM
- If `inspect_nvram.sh` shows Boot0009 or higher entries
- Before re-running setup sequence to ensure clean state
- When boot behavior is unpredictable

**What it does:**
- Identifies any boot entries outside the standard range (0000-0008)
- Prompts for confirmation before removal
- Deletes custom entries using `efibootmgr -b XXXX -B`
- Preserves all standard NVIDIA boot entries

**Usage:**
```bash
cd embedded_k8s/jetson_orin/tools
sudo ./inspect_nvram.sh  # First, see what will be removed
sudo ./clean_nvram.sh    # Then remove custom entries
```

**Important notes:**
- Nothing in this repository creates custom NVRAM entries
- If you find Boot0009+, they came from external tools or manual modifications
- This operation is safe - it only removes non-standard entries
- Standard boot entries (0000-0008) are never touched

**After running:**
```bash
sudo ./inspect_nvram.sh  # Verify cleanup worked
```

### Tool 3: reimage_microsd.sh (Factory Reset)

**Purpose:** Completely re-image the microSD card with a fresh OS from `sd-blob.img`.

**When to use:**
- Complete factory reset for redeployment
- MicroSD corruption or unknown state
- Testing/troubleshooting has left the microSD in an unknown condition
- You need a guaranteed clean slate

**Critical requirements:**
- ⚠️ **MUST be run while booted from NVMe SSD**
- ⚠️ **Will DESTROY all data on the microSD**
- ⚠️ Requires `sd-blob.img` file in the tools directory

**What it does:**
- Stops if you're not booted from SSD (safety check)
- Uses `dd` to write the image to the microSD at the block level
- Recreates all 15 partitions, including the ESP
- Results in factory-fresh microSD with unmodified JetPack OS

**Obtaining sd-blob.img:**

1. Download the JetPack SD card image from NVIDIA:
   - https://developer.nvidia.com/embedded/jetpack
   - Extract the `.img` file from the download

2. Place it in the tools directory:
   ```bash
   cp ~/Downloads/jetson-orin-nano-sd-card-image.img embedded_k8s/jetson_orin/tools/sd-blob.img
   ```

**Usage:**
```bash
# IMPORTANT: Only run while booted from SSD
findmnt -n -o SOURCE /
# Must show: /dev/nvme0n1p1

cd embedded_k8s/jetson_orin/tools
sudo ./reimage_microsd.sh
```

**After re-imaging:**
```bash
sudo reboot
```

The Jetson will boot into the fresh OS on the microSD. You'll need to:
1. Complete Ubuntu initial setup (oem-config) with monitor/keyboard
2. Re-run the entire setup sequence from script 01

**Complete factory reset workflow:**

To completely reset a Jetson (clean NVRAM + fresh microSD):

```bash
# While booted from SSD:
cd embedded_k8s/jetson_orin/tools
sudo ./clean_nvram.sh      # Remove custom boot entries
sudo ./reimage_microsd.sh  # Factory-reset the microSD
sudo reboot

# After reboot (from fresh microSD):
# Complete Ubuntu setup with monitor/keyboard
# Then start over with setup/01_config_headless.sh
```

---

## Troubleshooting

### System Won't Boot After 03_set_boot_to_ssd.sh

**Symptom:** Jetson powers on but doesn't reach login screen, or boots from microSD instead of SSD.

**Diagnosis:**
```bash
# If you can boot at all, check where you actually booted from:
findmnt -n -o SOURCE /

# If you see /dev/mmcblk0p1, you're still on microSD (not SSD)
```

**Fix 1: Verify bootloader configuration**

```bash
# Mount the microSD to check its extlinux.conf
sudo mkdir -p /mnt/microsd
sudo mount /dev/mmcblk0p1 /mnt/microsd
cat /mnt/microsd/boot/extlinux/extlinux.conf | grep "root="

# Should show: root=UUID=<some-uuid>
# If it shows root=/dev/mmcblk0p1, script 03 didn't work

# Get the SSD's UUID:
sudo blkid -s UUID -o value /dev/nvme0n1p1

# Manually fix extlinux.conf:
sudo nano /mnt/microsd/boot/extlinux/extlinux.conf
# Change root= line to: root=UUID=<ssd-uuid-from-above>

sudo umount /mnt/microsd
sudo sync
sudo reboot
```

**Fix 2: Check NVRAM boot order**

```bash
cd embedded_k8s/jetson_orin/tools
sudo ./inspect_nvram.sh

# Look at BootCurrent - should be 0001 (microSD ESP)
# If it's 0008 or 0009+, you're using a non-standard boot path
```

### Verify Script Shows Failures

**Problem:** You ran `06_verify_setup.sh` and it reports failures.

**Cause:** Verify script checks the FINAL state after ALL steps. Running it mid-setup will show failures.

**Solution:** Complete all setup steps (01-05) before running 06. If you've completed all steps and still see failures, check:

```bash
# Manual verification:
findmnt -n -o SOURCE /           # Should show /dev/nvme0n1p1
swapon --show                    # Should be empty
systemctl get-default            # Should be multi-user.target
```

### Custom NVRAM Boot Entries Detected

**Symptom:** `inspect_nvram.sh` shows Boot0009 or higher entries.

**Cause:** External tools or manual modifications created custom boot entries.

**Solution:**
```bash
cd embedded_k8s/jetson_orin/tools
sudo ./clean_nvram.sh
```

Nothing in this repository creates custom NVRAM entries. If you have them, they came from external troubleshooting or manual efibootmgr commands.

### MicroSD Corruption or Unknown State

**Symptom:** File system errors, boot failures, or unknown modifications to the microSD.

**Solution:** Re-image the microSD (must be booted from SSD):

```bash
# ONLY run while booted from SSD!
findmnt -n -o SOURCE /  # Verify shows /dev/nvme0n1p1

cd embedded_k8s/jetson_orin/tools
sudo ./reimage_microsd.sh
```

### Performance Issues on MicroSD-Only Setup

**Symptom:** Slow pod starts, slow image pulls, timeouts during deployment.

**Cause:** MicroSD I/O limitations (typically 20-30 MB/s vs 1500+ MB/s for NVMe).

**Solutions:**

1. **Add an SSD (recommended):**
   - Install NVMe SSD
   - Run scripts 02-04 to migrate
   - No Kubernetes reconfiguration needed

2. **Optimize for microSD:**
   - Use smaller container images
   - Pre-pull images: `kubectl create -f imagePullJob.yaml`
   - Reduce replica counts
   - Use `imagePullPolicy: IfNotPresent`

3. **Accept limitations:**
   - MicroSD is viable for learning/development
   - Not recommended for production workloads

---

## Hardware Requirements

### Supported Devices

**Tested and fully supported:**
- NVIDIA Jetson Orin Nano Developer Kit (8GB)
- NVIDIA Jetson Orin Nano Developer Kit (4GB)

**Should work (not tested by this repository):**
- NVIDIA Jetson Orin NX Developer Kit
- NVIDIA Jetson AGX Orin Developer Kit

**Not supported:**
- Jetson Xavier series (different boot architecture)
- Jetson TX2 series (different boot architecture)
- Jetson Nano (original) (different boot architecture)

### Storage Requirements

**MicroSD Card:**
- Minimum: 64GB (128GB recommended)
- Speed: Class 10 or UHS-1 minimum (UHS-3 recommended)
- Brand: SanDisk, Samsung, or Kingston recommended
- **Never remove after initial setup**

**NVMe SSD (Optional but Recommended):**
- Form factor: M.2 2280 (other sizes may physically fit but aren't guaranteed)
- Interface: NVMe (not SATA M.2)
- Capacity: 256GB minimum, 512GB+ recommended for ML workloads
- Tested brands: Samsung 980/990, WD Black SN770, Crucial P3

**Storage Sizing for ML Workloads:**
- Container images: 10-50GB (PyTorch, TensorFlow, CUDA)
- Model checkpoints: 5-100GB (depends on model size)
- Training datasets: Varies widely (use NFS for large datasets)
- System + Kubernetes: ~20GB

**Recommendation for 3-node cluster:** 512GB SSD per node

### Network Requirements

**For single-node development:**
- Any network connection (Wi-Fi or Ethernet)

**For production clusters:**
- Dedicated Ethernet switch (1Gbps minimum, 10Gbps ideal)
- Static IP addresses or DHCP reservations
- Separate network from general-purpose traffic (optional but recommended)
- For distributed training: Low-latency network (<1ms inter-node latency)

### Power Requirements

**Per Jetson Orin Nano:**
- Official power supply: 5V 4A (20W) via DC barrel jack
- Actual consumption: 5-15W typical (25W peak during GPU training)
- **Do not use USB-C power** - insufficient for GPU workloads

**For 3-node cluster:**
- Total: 45-75W typical consumption
- Use three individual power supplies (not a shared USB hub)

---

## Additional Resources

### Official NVIDIA Documentation

**Essential reading:**
- [Jetson Orin Nano Developer Kit User Guide](https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/index.html)
  - Complete hardware documentation
  - JetPack installation instructions
  - GPIO pinouts and carrier board details

- [JetPack SDK Documentation](https://docs.nvidia.com/jetson/jetpack/index.html)
  - Software components included in JetPack
  - CUDA and TensorRT documentation
  - Developer tools and samples

- [NVIDIA Jetson AI Lab - Initial Setup Guide](https://www.jetson-ai-lab.com/initial_setup_jon.html)
  - Community-maintained setup guides
  - Performance benchmarks
  - Additional optimization tips

### Kubernetes on Jetson

**External resources:**
- [NVIDIA Cloud Native Stack](https://github.com/NVIDIA/cloud-native-stack)
  - Official NVIDIA Kubernetes stack for Jetson
  - More automated, less educational than this repository

- [k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin)
  - GPU support for Kubernetes (comes with JetPack)

### Community and Support

**For Jetson-specific issues:**
- NVIDIA Developer Forums: https://forums.developer.nvidia.com/c/agx-autonomous-machines/jetson-embedded-systems/
- Jetson Hacks: https://jetsonhacks.com/ (excellent tutorials)

**For issues with these scripts:**
- GitHub Issues in this repository
- Include output of: `06_verify_setup.sh` and `tools/inspect_nvram.sh`

---

## Next Steps

After completing the Jetson setup:

1. **Install Kubernetes:**
   ```bash
   cd ../../k8s/node_setup
   sudo ./01_install_deps.sh
   sudo ./02_install_kube.sh
   ```

2. **Create your cluster:**
   ```bash
   cd ../ops
   # On first node:
   sudo ./bootstrap_cluster.sh
   
   # On additional nodes:
   sudo ./join_node.sh
   ```

3. **Install cluster addons:**
   ```bash
   cd ../addons
   sudo ./install_cert_manager.sh
   sudo ./install_ingress_nginx.sh
   sudo ./install_linkerd.sh  # Lightweight for ARM
   sudo ./install_knative.sh  # Serverless platform
   ```

4. **Deploy GPU workloads:**
   - See `k8s/deployments/` for example manifests
   - Try distributed PyTorch training across multiple Jetson nodes
   - Experiment with Knative for scale-to-zero inference serving

**Your Jetson is now a production-ready Kubernetes node with GPU acceleration.**
