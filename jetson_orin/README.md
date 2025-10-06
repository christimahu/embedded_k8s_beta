# NVIDIA Jetson Orin Setup Scripts

Welcome to the Jetson Orin setup guide. The scripts in this directory perform a complete, end-to-end setup of an NVIDIA Jetson Orin device, transforming it from its stock, desktop-oriented state into a hardened, headless server optimized for performance and reliability as a Kubernetes cluster node.

This guide is intentionally detailed and educational. The Jetson platform has a unique boot architecture that can be confusing. We'll walk through it step-by-step to demystify the process and explain the purpose behind each command.

---

## Understanding the Jetson Boot Process (The "Why")

Before running any scripts, it's crucial to understand *why* this multi-step process is necessary and how the Jetson actually boots.

### The UEFI Boot Chain

The Jetson Orin uses a UEFI-based boot process, similar to modern PCs. Here's the complete boot chain:

1. **UEFI Firmware** (stored in QSPI-NOR flash on the board)
   - Reads boot configuration from NVRAM (Non-Volatile RAM on the motherboard)
   - Attempts to boot from entries in the boot order (Boot0001, Boot0008, etc.)

2. **EFI System Partition (ESP)** on microSD partition 10
   - Contains the bootloader file: `BOOTaa64.efi`
   - This is why the microSD is **permanently required** - it holds the ESP

3. **Extlinux Bootloader** 
   - Reads `/boot/extlinux/extlinux.conf` from the microSD
   - This config file specifies `root=UUID=<device>` to determine where the OS lives

4. **Root Filesystem**
   - Can be on microSD (stock) or NVMe SSD (after running our scripts)
   - Contains the full Linux operating system

**Critical Understanding:** The microSD card cannot be removed. It contains the EFI System Partition (partition 10) which is required for boot. Our scripts move the *root filesystem* to the SSD for performance, but the boot process still starts from the microSD's ESP.

### The 15-Partition Layout

The microSD card uses a complex GUID Partition Table (GPT) with 15 partitions created by NVIDIA's flashing process:
- Partition 1: Root filesystem (what we clone to SSD)
- Partition 10: EFI System Partition (ESP) - **required for boot**
- Other partitions: Firmware, recovery, device trees, etc.

**Never manually repartition or reformat the microSD.** Use the provided tools.

---

## Directory Structure

```
jetson_orin/
├── README.md
├── tools/                    # Utility scripts (run as needed)
│   ├── inspect_nvram.sh      # View UEFI boot configuration (read-only)
│   ├── clean_nvram.sh        # Remove custom NVRAM boot entries
│   └── reimage_microsd.sh    # Restore microSD to factory state
└── setup/                    # Sequential setup scripts
    ├── 01_config_headless.sh # Configure for remote SSH access
    ├── 02_clone_os_to_ssd.sh # Copy OS to NVMe SSD
    ├── 03_set_boot_to_ssd.sh # Configure bootloader to use SSD
    ├── 04_strip_microsd_rootfs.sh # Remove redundant OS files from microSD
    ├── 05_update_os.sh       # Apply system updates
    └── 06_verify_setup.sh    # Verify configuration (run AFTER all steps)
```

---

## The Recommended Workflow (Using an NVMe SSD)

This workflow is highly recommended for any serious use, especially for a Kubernetes cluster. The NVMe SSD (which you must purchase and install separately) provides a massive boost in performance and reliability compared to a microSD card.

Follow these steps in order. Powering down or rebooting at specific moments is crucial for the process to work correctly.

### **Initial Physical Setup**

1. Flash the official NVIDIA JetPack OS image (`sd-blob.img`) to your microSD card using a tool like BalenaEtcher.
2. Install the microSD card and your NVMe SSD into the Jetson.
3. Connect peripherals for the one-time setup: a LAN cable, a USB keyboard, and an HDMI monitor.
4. Power on the device and complete the on-screen graphical Ubuntu setup (creating a user, setting the timezone, etc.).
5. Once on the desktop, open a terminal and clone this repository:
   ``` bash
   git clone https://github.com/yourusername/embedded_k8s.git
   ```

### **Script-Based Setup**

#### **Step 1: Configure Headless Mode**

* **Script:** `setup/01_config_headless.sh`
* **Action:** This script prepares the OS on the microSD card for remote management. It sets a static IP, changes the hostname, removes the resource-heavy desktop GUI, and disables swap memory (a Kubernetes requirement).
* **Why a Shutdown is Required:** After this script, you will run `sudo shutdown now`. This ensures all configurations are saved and allows you to safely disconnect the keyboard and monitor. From this point on, all other steps will be performed remotely via SSH.

``` bash
cd embedded_k8s/jetson_orin/setup
sudo ./01_config_headless.sh
# When complete:
sudo shutdown now
```

#### **Step 2: Clone the OS to the SSD**

* **Script:** `setup/02_clone_os_to_ssd.sh`
* **Action:** After powering the device back on and SSH'ing in, run this script. It performs a complete copy of your configured OS from the microSD card to the NVMe SSD. It also configures the SSD's `/etc/fstab` to mount the microSD's EFI partition at `/boot/efi` after boot.

``` bash
ssh user@<jetson-ip>
cd embedded_k8s/jetson_orin/setup
sudo ./02_clone_os_to_ssd.sh
```

#### **Step 3: Set Boot Device to SSD**

* **Script:** `setup/03_set_boot_to_ssd.sh`
* **Action:** This script modifies the bootloader configuration file (`extlinux.conf`) on the microSD card, changing the `root=` parameter to point to the SSD's UUID.
* **Why a Reboot is Required:** This change only takes effect when the bootloader reads the file on startup. You **must reboot** after this script for the Jetson to start using the SSD as its root filesystem.

``` bash
sudo ./03_set_boot_to_ssd.sh
# When complete:
sudo reboot
```

After reboot, verify you're running from SSD:
``` bash
findmnt -n -o SOURCE /
# Should show: /dev/nvme0n1p1
```

#### **Step 4: Strip the MicroSD Root Filesystem (Optional but Recommended)**

* **Script:** `setup/04_strip_microsd_rootfs.sh`
* **Action:** This security script removes the now-redundant OS files from the microSD card, leaving only the essential `/boot` directory (which contains the EFI System Partition and bootloader files).
* **Why this is important:** After confirming you're running from the SSD, this step prevents a scenario where someone with physical access could force the device to boot from the old, un-updated OS on the microSD card.

``` bash
sudo ./04_strip_microsd_rootfs.sh
```

#### **Step 5: Update the Operating System**

* **Script:** `setup/05_update_os.sh`
* **Action:** Applies all the latest software updates and security patches to the OS, which is now running from the fast NVMe SSD.

``` bash
sudo ./05_update_os.sh
```

#### **Step 6: Verify Setup**

* **Script:** `setup/verify_setup.sh`
* **Action:** Run this **only after completing all setup steps** to verify the node is in the correct final state.

``` bash
sudo ./06_verify_setup.sh
```

**At this point, your Jetson node is fully prepared, secure, and performant. You are ready to proceed with the scripts in the `common/` directory to install Kubernetes.**

---

## Alternative Workflow (MicroSD Card Only)

If you do not have an NVMe SSD, you can run a minimal setup. **This is not recommended for production use.**

1. Follow the **Initial Physical Setup**.
2. Run `setup/01_config_headless.sh` and shut down as instructed.
3. Power back on and SSH into the device.
4. **SKIP** scripts 02, 03, and 04.
5. Run `setup/05_update_os.sh`.

---

## Utility & Recovery Scripts (tools/)

### **inspect_nvram.sh**
A non-destructive diagnostic script that displays the current UEFI boot configuration stored in NVRAM. Use this to check for unexpected custom boot entries.

**When to use:**
- After troubleshooting to verify boot configuration
- Before running `clean_nvram.sh` to see what will be removed
- Any time you're curious about the boot state

``` bash
sudo ./tools/inspect_nvram.sh
```

### **clean_nvram.sh**
Removes custom UEFI boot entries from NVRAM that were created outside the standard NVIDIA setup process. This script preserves all standard entries (Boot0000-Boot0008) and only removes custom additions.

**When to use:**
- After external troubleshooting that may have modified NVRAM
- If `inspect_nvram.sh` shows unexpected boot entries
- Before re-running the setup sequence to ensure a clean state

``` bash
sudo ./tools/clean_nvram.sh
```

**Important:** Nothing in this repository creates custom NVRAM entries. If you find custom entries, they came from external tools or manual modifications.

### **reimage_microsd.sh**
Performs a complete re-imaging of the microSD card using the `sd-blob.img` file. This is a destructive operation that restores the microSD to factory-fresh state.

**When to use:**
- To factory reset a node for redeployment
- After testing/troubleshooting has left the microSD in an unknown state
- When you need a guaranteed clean slate

**Critical requirement:** Must be run while booted from the NVMe SSD, not from the microSD.

``` bash
sudo ./tools/reimage_microsd.sh
```

**Obtaining sd-blob.img:** Download the appropriate JetPack SD card image from NVIDIA's official site and extract it. Place the `sd-blob.img` file in the `jetson_orin/tools/` directory. See: https://www.jetson-ai-lab.com/initial_setup_jon.html

**Complete factory reset workflow:**
If you need to fully reset a node (clean NVRAM + fresh microSD):
``` bash
cd embedded_k8s/jetson_orin/tools
sudo ./clean_nvram.sh
sudo ./reimage_microsd.sh
sudo reboot
# Then complete Ubuntu setup and begin setup sequence from 01_
```

---

## Understanding NVRAM

**NVRAM (Non-Volatile RAM)** is a small chip on the Jetson's motherboard that stores firmware settings, including UEFI boot entries. NVRAM persists across:
- Power cycles
- MicroSD re-imaging
- SSD replacement

**You cannot clear NVRAM by re-imaging storage devices.** Use `clean_nvram.sh` or NVIDIA's Force Recovery Mode to reset NVRAM.

**Standard NVIDIA boot entries:**
- Boot0000: UEFI Setup Menu
- Boot0001: MicroSD Card (ESP on partition 10)
- Boot0002-0005: Network boot options (PXE, HTTP)
- Boot0006: Boot Manager Menu
- Boot0007: UEFI Shell
- Boot0008: NVMe SSD (if present)

Any entry numbered Boot0009 or higher was created by external tools and should be investigated.

---

## Troubleshooting

### "System won't boot after running 03_set_boot_to_ssd.sh"

Check what the system is actually booted from:
``` bash
findmnt -n -o SOURCE /
sudo efibootmgr | grep BootCurrent
```

Verify the microSD's extlinux.conf points to the SSD:
``` bash
sudo mount /dev/mmcblk0p1 /mnt
cat /mnt/boot/extlinux/extlinux.conf | grep "root="
# Should show: root=UUID=<ssd-uuid>
sudo umount /mnt
```

### "Verify script shows failures"

**Do not run `06_verify_setup.sh` in the middle of the setup sequence.** It checks for the final state after ALL steps are complete. Failures are expected if you haven't finished all steps 01-05.

### "I need to start over completely"

Boot from SSD, then:
``` bash
cd embedded_k8s/jetson_orin/tools
sudo ./clean_nvram.sh
sudo ./reimage_microsd.sh
```

This gives you a factory-fresh starting point.

---

## Important Notes

- **The microSD card is permanently required** - it contains the EFI System Partition needed for boot
- **Script 04 is optional** - the system works fine with the full OS still on the microSD
- **NVRAM is separate from storage** - re-imaging the microSD does not reset NVRAM
- **Run scripts in order** - the sequence 01→02→03→04→05 is designed to be executed sequentially
- **Verify only at the end** - `06_verify_setup.sh` checks the final state, not intermediate states

---

## Recovery Without Linux PC

If the Jetson won't boot and you don't have a Linux PC for Force Recovery Mode:
1. If booted from SSD: Use `tools/reimage_microsd.sh`
2. If unable to boot at all: Remove microSD, re-image on Mac using BalenaEtcher, reinstall

---

## See Also

- [NVIDIA Jetson AI Lab - Initial Setup Guide](https://www.jetson-ai-lab.com/initial_setup_jon.html)
- [NVIDIA Developer - Jetson Orin Nano User Guide](https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/index.html)
