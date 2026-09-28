# Install on Proxmox VE

Two options. **A VM with GPU passthrough is recommended**: it's isolated from the hypervisor
and behaves like the plain Linux install.

## Option A (recommended): VM with PCIe passthrough

1. Enable IOMMU: set `intel_iommu=on` or `amd_iommu=on` in `/etc/kernel/cmdline` (systemd-boot)
   or in `GRUB_CMDLINE_LINUX_DEFAULT` (GRUB), then `proxmox-boot-tool refresh` or `update-grub`.
2. Load VFIO: add `vfio`, `vfio_iommu_type1` and `vfio_pci` to `/etc/modules`, run
   `update-initramfs -u -k all`, and reboot.
3. Create a VM: **q35** machine, **OVMF (UEFI)** BIOS, CPU type **host**.
   - **Cores: all of them.** Proxmox limits the VM to what you assign here. Give it as many
     as you want the games to use (e.g. 64), and the RAM you want (turn off ballooning for
     consistent performance).
4. Hardware → Add → PCI Device → pick the GPU, tick **All Functions**, **Primary GPU** off,
   **PCI-Express** on.
5. Install Ubuntu Server or Debian in the VM and follow [linux.md](linux.md).

## Option B: directly in an LXC container

Possible but fiddlier: the LXC must be **privileged** with nesting enabled and the GPU and input
devices passed in. The host must have the GPU driver loaded, and for NVIDIA the LXC and host
driver versions must match (this image handles that inside the Docker container).

`/etc/pve/lxc/<id>.conf` additions:

```
features: nesting=1
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 13:* rwm
lxc.cgroup2.devices.allow: c 10:223 rwm
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 509:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
lxc.mount.entry: /dev/uinput dev/uinput none bind,optional,create=file
lxc.mount.entry: /run/udev run/udev none bind,ro,optional,create=dir
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
```

(`509` is the usual `nvidia-uvm` major number; check with `ls -l /dev/nvidia-uvm` on the host.)

Put the udev rule from [linux.md](linux.md) step 3 on the **Proxmox host** (the kernel
there creates the virtual devices), set LXC **Cores** and **Memory** to what you want
available (LXC limits apply), then install Docker in the LXC and follow linux.md step 4.

The container logs show the CPU threads and RAM it can see, and warn if a limit is applied.

## Next steps

- [Usage](../usage.md): pairing Moonlight, Gaming Mode and Desktop Mode, controllers
- [Add-ons](../add-ons.md): Decky Loader, EmuDeck, Heroic and more
- [Troubleshooting](../troubleshooting.md): if something doesn't work
