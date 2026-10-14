{ config, ... }:
# The webcam is an OV08X40 (ACPI OVTI08F4) behind the Intel CVS (INTC10E1)
# on the IPU7. Linux 7.2.7 needs three fixes for it, so this file builds
# patched copies of three in-tree modules. depmod prefers the copies in
# updates/ to the in-tree modules.
#
# * intel_cvs: the in-tree driver holds its wake GPIO. The four CS35L57
#   speaker amps read their speaker ID from the same pin, and then fail with
#   -EBUSY. The upstream patch takes only the IRQ. Do not blacklist
#   intel_cvs: the sensor binds only after intel_cvs binds.
# * ipu_bridge: the sensor is mounted upside down, and the firmware does not
#   report it.
# * ov08x40: the 2-lane binned mode gives only black frames on IPU7.
#
# Remove a patch when the kernel contains its fix.
let
  kernelPackages = config.boot.kernelPackages;
  cameraModules = kernelPackages.callPackage (
    {
      stdenv,
      kernel,
      kernelModuleMakeFlags,
    }:
    stdenv.mkDerivation {
      pname = "dark-archon-camera-modules";
      inherit (kernel) version src;

      # Unpack only the three drivers from the kernel tarball.
      unpackPhase = ''
        mkdir source
        cd source
        tar -xJf $src --strip-components=1 --wildcards \
          '*/drivers/media/i2c/cvs/*' \
          '*/drivers/media/i2c/ov08x40.c' \
          '*/drivers/media/pci/intel/ipu-bridge.c'
      '';

      patches = [
        ./intel-cvs-wake-irq.patch
        ./ipu-bridge-xps14-da14260-rotation.patch
        ./ov08x40-drop-2lane-binned-mode.patch
      ];

      # Build the three modules as one external module.
      postPatch = ''
        mkdir -p module/cvs
        cp drivers/media/i2c/cvs/*.[ch] module/cvs/
        cp drivers/media/i2c/ov08x40.c drivers/media/pci/intel/ipu-bridge.c module/
        cat > module/Kbuild <<'EOF'
        obj-m := intel_cvs.o ipu-bridge.o ov08x40.o
        intel_cvs-y := cvs/core.o cvs/v4l2.o
        EOF
      '';

      nativeBuildInputs = kernel.moduleBuildDependencies;
      hardeningDisable = [
        "format"
        "pic"
      ];

      buildPhase = ''
        runHook preBuild
        make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
          ${toString kernelModuleMakeFlags} M=$PWD/module modules
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm444 -t $out/lib/modules/${kernel.modDirVersion}/updates module/*.ko
        runHook postInstall
      '';
    }
  ) { };
in
{
  boot.extraModulePackages = [ cameraModules ];

  # Firefox must read the camera through PipeWire (libcamera). The raw IPU7
  # V4L2 nodes never give an image.
  programs.firefox.preferences."media.webrtc.camera.allow-pipewire" = true;
}
