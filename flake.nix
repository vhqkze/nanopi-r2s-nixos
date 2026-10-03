{
  description = "NixOS SD Image for NanoPi R2S";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        uboot-nanopi-r2s =
          let
            armTrustedFirmwareRK3328 = pkgs.armTrustedFirmwareRK3328.overrideAttrs (_: {
              NIX_LDFLAGS = "--no-warn-execstack --no-warn-rwx-segments";
              enableParallelBuilding = true;
            });
          in
          pkgs.buildUBoot {
            defconfig = "nanopi-r2s-rk3328_defconfig";
            extraPatches = [
              ./expand-kernel-image-addr-space.patch
            ];
            extraMeta.platforms = [ "aarch64-linux" ];
            BL31 = "${armTrustedFirmwareRK3328}/bl31.elf";
            makeFlags = [
              "BL31=${armTrustedFirmwareRK3328}/bl31.elf"
            ];
            BINMAN_ALLOW_MISSING = "1";
            enableParallelBuilding = true;
            filesToInstall = [
              "idbloader.img"
              "u-boot.itb"
            ];
          };

        default = self.nixosConfigurations.r2s.config.system.build.sdImage;
      };

      nixosConfigurations.r2s = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

          (
            {
              lib,
              pkgs,
              ...
            }:
            {
              # 这行不用写，会自动设置最新版
              # system.stateVersion = "26.11";

              # 配合 `services.avahi.enable=true;` 可以直接使用 `ssh root@r2s.local` 登录设备
              networking.hostName = "r2s";

              # 默认启用flake
              nix.settings.experimental-features = [
                "nix-command"
                "flakes"
              ];

              image.fileName = "nanopi-r2s-nixos";

              sdImage = {
                # 是否压缩镜像，如果是本地构建，建议改为 false，减少构建时间
                compressImage = true;
                postBuildCommands = ''
                  echo "==> Burning RK3328 U-Boot to raw SD image sectors..."
                  dd if=${self.packages.${system}.uboot-nanopi-r2s}/idbloader.img of=$img seek=64 conv=notrunc
                  dd if=${self.packages.${system}.uboot-nanopi-r2s}/u-boot.itb of=$img seek=16384 conv=notrunc
                '';
              };

              # 引导配置
              boot.loader.grub.enable = false;
              boot.loader.generic-extlinux-compatible.enable = true;

              # 调试串口与控制台输出（这个我不确定是否正确）
              boot.kernelParams = [
                "console=ttyS2,1500000n8"
                "console=tty0"
              ];

              # R2S 软路由专属性能调优
              # 应对 1GB 较小内存，开启 ZRAM 压缩内存，防止 nixos-rebuild 时 OOM
              zramSwap.enable = true;
              zramSwap.memoryPercent = 50;

              # 软路由高并发网络转发，调频策略推荐改为 performance
              powerManagement.cpuFreqGovernor = "performance";

              # 关掉不必要的东西，减少 img 体积和构建时间
              documentation.enable = lib.mkForce false;
              documentation.nixos.enable = lib.mkForce false;
              documentation.man.enable = lib.mkForce false;
              documentation.info.enable = lib.mkForce false;
              fonts.fontconfig.enable = lib.mkForce false; # 彻底移除字体配置库
              hardware.enableRedistributableFirmware = lib.mkForce false; # 默认就是false，无需设置
              boot.zfs.forceImportRoot = false;

              # 移除不必要的文件系统支持
              boot.supportedFilesystems = lib.mkForce {
                vfat = true; # 必须保留：用于引导分区（EFI/boot 目录）
                ext4 = true; # 必须保留：用于根分区
              };

              # 安装必要软件
              environment.systemPackages = with pkgs; [
                git
                neovim
              ];

              # 配置 ssh 免密登录，将里面的公钥换成你自己的公钥
              users.users.root = {
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrcm51SikiK/ynIp6hFFvNXwCKvngpocvO0v0MAoxw/ mbp"
                ];
              };

              # 配置 ssh 只能使用公钥登录
              services.openssh = {
                enable = true;
                settings = {
                  PermitRootLogin = "prohibit-password";
                  PasswordAuthentication = false; # 建议显式关闭密码登录，纯密钥更安全
                };
              };

              # 局域网设备发现
              services.avahi = {
                enable = true;
                nssmdns4 = true;
                openFirewall = true;
                publish = {
                  enable = true;
                  addresses = true;
                  workstation = false;
                  userServices = false;
                };
              };
            }
          )
        ];
      };
    };
}
