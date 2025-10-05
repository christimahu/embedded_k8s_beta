# NVIDIA Jetson Orin Setup Scripts

The scripts in this directory perform a complete, end-to-end setup of an NVIDIA Jetson Orin device. The workflow takes a device from its initial state (booting from a freshly flashed microSD card) and transforms it into a hardened, headless server running on a fast NVMe SSD, fully prepared to be a Kubernetes cluster node.

## The Importance of the NVMe SSD

The NVIDIA Jetson Orin Developer Kit does **not** ship with an NVMe SSD; this is a component you must purchase and install separately.

While it is technically possible to run the entire operating system from the microSD card, it is **highly recommended** to use an NVMe SSD for any serious workload, especially Kubernetes. This two-step process of booting from the microSD and then migrating the OS to the SSD is a specific requirement of the Jetson platform's boot process.

The benefits of using an SSD are significant:
- **Performance:** An NVMe SSD offers dramatically faster read/write speeds, which is crucial for container image pulls, application performance, and overall system responsiveness.
- **Reliability & Longevity:** MicroSD cards are not designed for the constant, small read/write operations of a server OS and are prone to corruption and failure over time. An SSD is built for this workload and is far more reliable for a 24/7 server.

### **Skipping the SSD Setup (Untested & Not Recommended)**
If you choose not to use an NVMe SSD, you can skip **Step 2** (`02_clone_os_to_ssd.sh`) and **Step 3** (`03_strip_microsd_rootfs.sh`). However, this configuration is untested and not recommended due to the performance and reliability concerns mentioned above.

---

## Setup Workflow

To ensure a successful setup, the scripts in the `setup/` directory must be run in the following numerical order.

### **Step 1: Configure Headless Mode**
* **Script:** `setup/01_config_headless.sh`
* **Action:** Configures the base system settings (network, hostname, removes GUI, disables swap) on the microSD card.

### **Step 2: Clone OS to SSD**
* **Script:** `setup/02_clone_os_to_ssd.sh`
* **Action:** Clones the configured OS from the microSD card to the NVMe SSD and updates the bootloader to run from the SSD.

### **Step 3: Strip MicroSD Root Filesystem**
* **Script:** `setup/03_strip_microsd_rootfs.sh`
* **Action:** A crucial security step. Removes the now-redundant OS from the microSD card, leaving it as a boot-only device.

### **Step 4: Update Operating System**
* **Script:** `setup/04_update_os.sh`
* **Action:** Applies all system software updates and security patches to the OS now running on the SSD.

**At this point, the Jetson node is fully prepared. You can now proceed with the scripts in the `common/` directory to install Kubernetes and assign the node a role in the cluster.**

---

## Utility Scripts

* **`factory_reset.sh`**: A destructive script that re-images the microSD card from a file on the SSD, allowing you to start the setup process over without physical access to the card.
