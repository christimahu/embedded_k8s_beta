# Cluster Support Services

The scripts in this directory are used to set up shared services that support the Kubernetes cluster.

Unlike the Kubernetes components themselves, these services are typically run on a single, designated node (which could be a Raspberry Pi, a Jetson, or any other machine on the network) and provide cluster-wide functionality.

---

## Available Scripts

* **`setup_registry.sh`**:
    Installs and runs a private, local Docker container registry. This allows the cluster to pull images from a local source instead of the public Docker Hub, which is faster, avoids rate limits, and is more secure.

* **`gen_certs.sh`**:
    A placeholder script for automating the creation of a private Certificate Authority (CA) and generating TLS certificates. This is the first step in upgrading the local container registry from insecure HTTP to secure HTTPS.
