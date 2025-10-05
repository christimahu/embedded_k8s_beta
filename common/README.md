# Common Scripts

The scripts in this directory are hardware-agnostic and are intended to be run on a board *after* it has been prepared by its platform-specific setup scripts (e.g., those in the `jetson_orin/` directory).

These scripts handle the installation and configuration of Kubernetes, its supporting services, and other optional tools.

---

## Subdirectories

* ### `k8s/`
    This is the core directory for turning a prepared node into a functioning member of a Kubernetes cluster. It contains scripts to install dependencies, the required Kubernetes packages, and finally to initialize a control plane or join a worker node.

    [More Info](./k8s/README.md)

* ### `services/`
    This directory contains scripts for setting up shared services that support the cluster. The primary example is a local container registry, which allows for fast and private image distribution. These services can typically be run on any node in the cluster.

    [More Info](./services/README.md)

* ### `helpers/`
    This directory contains optional, quality-of-life scripts for installing useful command-line tools and developer utilities, such as a pre-configured Neovim setup.

    [More Info](./helpers/README.md)
