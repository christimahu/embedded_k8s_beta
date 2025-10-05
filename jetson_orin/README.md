# NVIDIA Jetson Orin Setup Scripts

Welcome to the Jetson Orin setup guide. The scripts in this directory are designed to perform a complete, end-to-end setup of an NVIDIA Jetson Orin device. The goal is to transform a device from its stock, desktop-oriented state into a hardened, headless server optimized for performance and reliability, making it a perfect node for a Kubernetes cluster.

This guide is intentionally detailed. The Jetson platform has a unique and powerful boot process that can be confusing. We will walk through it step-by-step to demystify the process and explain the purpose behind each command.

---

## Understanding the Jetson Boot Process (The "Why")

Before running any scripts, it's crucial to understand *why* this multi-step process is necessary. Unlike a standard PC where you can simply install an OS directly onto any drive, the Jetson has a specific hardware limitation.

### The Two-Stage Firmware Boot

Think of the Jetson's boot process in two stages, like a simple "lizard brain" that wakes up a smarter "mammal brain":

1.  **The "Lizard Brain" (BootROM Firmware):** This is the lowest-level firmware, permanently burned into the Jetson's silicon chip. It is extremely basic. Its only job is to find and start the *next* stage of the boot process. Critically, **it only knows how to look in a few places, like the microSD card slot. It does not know how to read from an NVMe SSD.**

2.  **The "Mammal Brain" (U-Boot Bootloader):** This is a more sophisticated piece of firmware that the "Lizard Brain" finds on the microSD card. U-Boot is smart enough to understand different filesystems and devices. **It *does* know how to read from an NVMe SSD.**

This hardware reality means **you cannot flash the OS directly to the SSD and expect it to work.** The microSD card is a **mandatory key** required to start the engine. Our entire setup process is a clever workaround to use that key to start the engine, but then immediately switch it over to run on the high-performance SSD.



---

## The Recommended Workflow (Using an NVMe SSD)

This workflow is highly recommended for any serious use, especially for a Kubernetes cluster. The NVMe SSD (which you must purchase and install separately) provides a massive boost in performance and reliability compared to a microSD card.

Follow these steps in order. Powering down or rebooting at specific moments is crucial for the process to work correctly.

### **Initial Physical Setup**

1.  Flash the official NVIDIA JetPack OS image (`sd-blob.img`) to your microSD card using a tool like BalenaEtcher.
2.  Install the microSD card and your NVMe SSD into the Jetson.
3.  Connect peripherals for the one-time setup: a LAN cable, a USB keyboard, and an HDMI monitor.
4.  Power on the device and complete the on-screen graphical Ubuntu setup (creating a user, setting the timezone, etc.).
5.  Once on the desktop, open a terminal and clone this repository:
    `git clone https://github.com/christimahu/embedded_k8s.git`

### **Script-Based Setup**

#### **Step 1: Configure Headless Mode**

* **Script:** `setup/01_config_headless.sh`
* **Action:** This script prepares the OS on the microSD card for remote management. It sets a static IP, changes the hostname, removes the resource-heavy desktop GUI, and disables swap memory (a Kubernetes requirement).
* **Why a Shutdown is Required:** After this script, you will run `sudo shutdown now`. This is a deliberate stop. It ensures all configurations are saved and allows you to safely disconnect the keyboard and monitor. From this point on, all other steps will be performed remotely via SSH, which is a faster and more efficient workflow.

#### **Step 2: Clone the OS to the SSD (Optional)**

* **Script:** `setup/02_clone_os_to_ssd.sh`
* **Action:** After powering the device back on and SSH'ing in, run this script. It performs a byte-for-byte clone of your now-configured OS from the microSD card to the empty NVMe SSD. It does **not** yet change the boot order.
* **Why it's Optional:** You could use this script simply to create a backup of your OS onto the SSD without making it the primary boot device.

#### **Step 3: Set Boot Device to SSD (Optional)**

* **Script:** `setup/03_set_boot_to_ssd.sh`
* **Action:** This is the "master switch." This script edits the bootloader configuration file (`extlinux.conf`) on the microSD card, changing the `root=` parameter to point to the SSD's unique ID (UUID).
* **Why a Reboot is Required:** This change only takes effect when the U-Boot bootloader reads the file on startup. You **must reboot** after this script for the Jetson to start using the SSD as its main OS drive.

#### **Step 4: Strip the MicroSD Root Filesystem (Optional)**

* **Script:** `setup/04_strip_microsd_rootfs.sh`
* **Action:** This security script deletes the now-redundant OS files from the microSD card, leaving only the essential `/boot` directory.
* **Why this is important:** After rebooting and confirming you are running from the SSD, this step is crucial for security. It prevents a scenario where someone with physical access could force the device to boot from the old, un-updated OS on the microSD card.

#### **Step 5: Update the Operating System**

* **Script:** `setup/05_update_os.sh`
* **Action:** Applies all the latest software updates and security patches to the OS, which is now running from the fast NVMe SSD.

**At this point, your Jetson node is fully prepared, secure, and performant. You are ready to proceed with the scripts in the `common/` directory to install Kubernetes.**

---

## Alternative Workflow (MicroSD Card Only)

If you do not have an NVMe SSD, you can run a minimal setup. **This is not recommended or tested.**

1.  Follow the **Initial Physical Setup**.
2.  Run `setup/01_config_headless.sh` and shut down as instructed.
3.  Power back on and SSH into the device.
4.  **SKIP** scripts `02`, `03`, and `04`.
5.  Run `setup/05_update_os.sh`.

---

## Utility & Recovery Scripts

* **`verify_setup.sh`**: A non-destructive script you can run at any time to check the configuration state of your node and see if all setup steps have been completed successfully.
* **`factory_reset.sh`**: A destructive script that re-images the microSD card from an `sd-blob.img` file stored on the SSD, allowing you to start the entire setup process over from the beginning without physical access to the card.
