# Kernarium/Andarium：KosmicKrisp → MoltenVK + iOS 18.0 改造清单

> 目标：让 GPU 后端从「KosmicKrisp（Vulkan→Metal 4，要 iOS 26+）」
> 换成「MoltenVK（Vulkan→Metal 2/3，iOS 13+）」，并把全套部署目标降到 18.0。
> 这是**唯一能让 iOS 18.5 真机跑起来（无 JIT）的路线**，但它是几个月的图形栈返工，
> 下面按「改动顺序 + 文件级定位 + 验收判据」列出，前 4 步是骨架，第 5 步是真硬骨头。

---

## 0. 先认清判据（这一步失败就整条路线死）
MoltenVK 的 Vulkan 能力约 **Vulkan 1.0/1.1**（iOS 上还砍了一部分特性）。
本项目的宿主 GL 走 **Mesa Zink**，而 Zink 是照 **Vulkan 1.4** 的能力写的。
👉 **判据 = 把 MoltenVK 编成 iOS 的 ICD，喂给 Zink，看 `zink` 初始化会不会因缺特性直接拒绝。**
能过 → 往下做；过不了 → 要么给 MoltenVK 打补丁伪造特性（危险），要么放弃路线。

---

## 1. 部署目标 27.0 → 18.0（机械改动）
跑 `patch-ios18.sh`，它覆盖：
- `dependencies/*.sh` 里 `DEPLOYMENT_TARGET=27.0`（特别是 `build-apple-gpu.sh`，常量写死）
- `dependencies/platforms/ios-device-gpu-vulkan-arm64.tsv` 等所有 `deployment_target	27.0`
- 所有 `*.xcodeproj/project.pbxproj` 的 `IPHONEOS_DEPLOYMENT_TARGET = 27.0;`
- 还要**人工**处理：`dependencies/cmake/VerifyAppleGpuPrefix.cmake`（它会核对部署目标与 provider，改完 27.0 会把你的新前缀判为 invalid）

---

## 2. 把 KosmicKrisp 从依赖里摘掉
文件：`dependencies/platforms/ios-device-gpu-vulkan-arm64.tsv`
```
payload   ... 去掉 dynamic-KosmicKrisp-framework
components ... 去掉 kosmickrisp
gl_provider      zink-moltenvk      # 原来是 zink-kosmickrisp
vk_provider      moltenvk           # 原来是 venus-kosmickrisp
kosmickrisp_linkage          -> 删掉
vulkan_entrypoint  direct-vkGetInstanceProcAddr   # 保留
```
文件：`dependencies/build-apple-gpu.sh`
- Mesa 配置里 `-Dvulkan-drivers=kosmickrisp` → 改成不构建 kosmickrisp（Zink 用的是外部 Vulkan ICD，不是 Mesa 自带 vulkan 驱动）。
- 去掉 `MESA_TOOLS`/`kk_clc` 那段对 KosmicKrisp 的编译。
- 新增：把 MoltenVK 编成 `MoltenVK.framework`（iOS device，部署目标 18.0），产物放进 prefix 的 `Frameworks/`。

## 3. 加 MoltenVK 进依赖清单
文件：`dependencies/manifest.tsv` 加一行 MoltenVK 的固定 commit + patch series（或直接用 `--archive-manifest` 走官方 release 源码包）。
文件：`dependencies/prepare.sh` 让它能拿到 MoltenVK 源码（或走 archives.tsv，网络只在这里允许）。

## 4. 让 App 与校验认得 MoltenVK
- `Kernarium/scripts/package-ios-frameworks.sh`：`GPU_FRAMEWORKS="MesaEGL MesaGallium KosmicKrisp"` → 换成 `MoltenVK`；去掉 `--verify-only` 里对 kosmickrisp 的断言。
- `scripts/check-privacy-manifests.py`、`check-app-store-bundle.py`：若有 KosmicKrisp 硬编码，改掉。
- Xcode 工程里，原来嵌 `KosmicKrisp.xcframework` 的 Embed Frameworks 相位 → 换成 `MoltenVK.xcframework`。

## 5. ★真硬骨头：Zink ↔ MoltenVK 特性对齐
- 首跑 `verify-prefix` + 一个最小 Zink 初始化，抓 Vulkan 层日志（`MVK_CONFIG_LOG_LEVEL=debug`）。
- 大概率缺：`descriptorIndexing`、`bufferDeviceAddress`、部分 `VK_KHR_*`。两条路：
  a) 给 MoltenVK 开对应 Metal 特性的模拟/补丁；
  b) 降级 Zink 配置（`ZINK_NO_...` 环境变量 / 打 Mesa 补丁）。
- **这一步没有真机就是盲调**——必须接 iPhone 12 Pro（iOS 26 测试机最方便，能反推 18 的差异）实机看日志。

---

## 6. 顺序建议（别跳步）
1. 先只做第 1 步（降 18.0），用**软件渲染（ios-simulator 的 llvmpipe 不适用真机）**——真机没有软件渲染，所以第 1 步在真机上仍跑不起来，但能验证「框架能加载到启动」。
2. 第 2–4 步做出「带 MoltenVK 的 IPA」，哪怕黑屏，只要 App 不崩在 dyld。
3. 第 5 步反复调，直到 Zink 初始化通过、能出画面。
4. 最后才谈帧率和装 APK。

> 记住：**GPU 通了才谈得上装 APK**；GPU 不通，前面全是白做。所以第 0/5 步的判据要最先验。
