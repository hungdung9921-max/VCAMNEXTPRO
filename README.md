# Hướng Dẫn Xây Dựng & Triển Khai VCAMNEXTPRO (iOS 16+)

Dự án **VCAMNEXTPRO** được thiết kế theo tiêu chuẩn hiện đại dành cho hệ điều hành iOS từ phiên bản 16.0 trở lên, mô phỏng trực quan và cải tiến dựa trên các tính năng cao cấp của phiên bản Vcam thương mại.

---

## 📁 1. Cấu Trúc Dự Án

```
VCAM PROX/
└── VCAMNEXTPRO/
    ├── VCAMNEXTPROApp.swift             # Entry point của ứng dụng
    ├── Models/
    │   ├── AccountInfo.swift           # Quản lý tài khoản, bản quyền, hạn dùng, số máy
    │   ├── CameraConfig.swift          # Cấu hình tọa độ (X, Y, Zoom, Rotation, Color Sync)
    │   └── MediaSource.swift           # Quản lý file ảnh / video / live stream
    ├── ViewModels/
    │   └── AppViewModel.swift          # Xử lý State, IP mạng, copy URL, logic điều khiển
    ├── Views/
    │   ├── MainView.swift              # Màn hình chính Dark Mode
    │   ├── FloatingControlView.swift   # Nút điều khiển nổi (Floating Widget)
    │   └── Components/
    │       ├── HeaderView.swift        # Header hiển thị Logo và trạng thái Active
    │       ├── AccountCardView.swift   # Khung tài khoản (Expired date, Quota thiết bị)
    │       ├── DeviceLinkCardView.swift# Cấu hình Wi-Fi, USB, OBS RTMP Stream, Start Server
    │       ├── DirectMediaCardView.swift# Bộ chọn Ảnh (Image) & Video (Video)
    │       ├── CameraBehaviorCardView.swift # Color Sync, Screen Sample, Transform Sliders
    │       └── Color+Hex.swift         # Tiện ích chuyển đổi mã màu Hex
```

---

## ⚙️ 2. Yêu Cầu Môi Trường & Khả Năng Tương Thích

- **Hệ điều hành iOS hỗ trợ**: iOS 16.0 – iOS 17.x / 18.x
- **Framework giao diện**: SwiftUI (tận dụng tối đa `PhotosPicker`, `Combine`, `AVFoundation`)
- **Môi trường biên dịch**:
  - Máy Mac chạy Xcode 15 trở lên (hoặc cross-compile qua Theos / Swift toolchain).
  - Hoặc đóng gói thành file `.ipa` để cài đặt trực tiếp qua TrollStore, ESign, Sideloadly hoặc AltStore.

---

## 🛠️ 3. Các Bước Mở & Build Dự Án Trên Xcode

1. **Tạo Xcode Project**:
   - Mở Xcode > Chọn **Create a new Xcode project**.
   - Chọn template **iOS > App**.
   - Đặt tên sản phẩm: `VCAMNEXTPRO`.
   - Interface: **SwiftUI**, Language: **Swift**.
   - Deployment Target: **iOS 16.0**.

2. **Thêm các file mã nguồn**:
   - Kéo toàn bộ thư mục `VCAMNEXTPRO/` vào cây thư mục của Xcode.
   - Đảm bảo đã tích chọn **Copy items if needed** và **Add to targets: VCAMNEXTPRO**.

3. **Cấu hình Quyền Trong `Info.plist`**:
   Để ứng dụng có thể chọn ảnh, video và phát hiện địa chỉ mạng nội bộ, hãy thêm các key sau vào `Info.plist`:
   ```xml
   <!-- Quyền truy cập thư viện ảnh/video -->
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Ứng dụng cần truy cập thư viện để chọn ảnh và video phát lên camera.</string>

   <!-- Quyền truy cập mạng cục bộ (OBS / Wi-Fi Streaming) -->
   <key>NSLocalNetworkUsageDescription</key>
   <string>Ứng dụng cần quyền mạng nội bộ để nhận luồng OBS qua Wi-Fi.</string>
   ```

4. **Build & Chạy Thử**:
   - Chọn thiết bị iPhone thật chạy iOS 16+ hoặc Simulator.
   - Bấm **Cmd + R** để build và trải nghiệm giao diện.

---

## 🔄 4. Cơ Chế Kết Nối Cốt Lõi (Architecture Overview)

1. **Giao tiếp liên tiến trình (IPC - Inter-Process Communication)**:
   - App ghi các thông số cấu hình ($X, Y, Zoom, Rotation, Color$) vào Shared Preferences (`UserDefaults(suiteName: "group.com.vcamnextpro")`) hoặc file cấu hình JSON tại thư mục dùng chung.
   - Khi có thay đổi, App gửi tín hiệu `CFNotificationCenterPostNotification` (Darwin Notification) để thông báo cho module render cập nhật tức thì mà không cần restart app.

2. **Bộ Nhận Luồng Trực Tiếp (Device Link / OBS)**:
   - Khi bấm **Start Server**, app kích hoạt socket RTMP listener trên cổng mặc định `1935`.
   - Trên máy tính, người dùng cấu hình OBS Studio:
     - Stream URL: `rtmp://<IP_iPhone>/live`
     - Stream Key: `live`
   - Video từ OBS sẽ được decode trực tiếp thành các frame `CVPixelBufferRef` với độ trễ siêu thấp (< 100ms).

3. **Cơ Chế Khóa Bản Quyền Thương Mại (Commercial License Guard)**:
   - Mỗi thiết bị được định danh bằng mã băm SHA256 của `identifierForVendor` + Key phần cứng.
   - App gửi request định kỳ tới máy chủ quản lý để xác thực số lượng thiết bị kích hoạt (`Devices in use: x / 999`) và thời hạn thuê bao.
