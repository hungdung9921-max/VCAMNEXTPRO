import SwiftUI
import UIKit
import Foundation
import PhotosUI
import Combine
import Darwin
import AVFoundation

// ==========================================
// 1. DATA MODELS & ENUMS
// ==========================================

public enum SyncTargetArea: String, CaseIterable, Identifiable, Codable {
    case face = "Face"
    case forehead = "Forehead"
    case chin = "Chin"
    case sides = "Sides"
    public var id: String { self.rawValue }
}

public struct AccountInfo: Codable {
    public var username: String = "VIP_Master"
    public var accountType: String = "VcamProVip Enterprise"
    public var expirationDate: String = "31/12/2099"
    public var devicesInUse: Int = 1
    public var maxDevices: Int = 999
    public var isActive: Bool = true
}

public struct CameraConfig: Codable {
    public var posX: Double = 0.0
    public var posY: Double = 0.0
    public var scale: Double = 1.0
    public var rotation: Double = 0.0
    public var isFlipped: Bool = false       // Lật ngang
    public var isFlippedV: Bool = false      // Lật dọc

    public var isColorSyncEnabled: Bool = true
    public var selectedSyncArea: SyncTargetArea = .face
    public var screenSampleHex: String = "#2B4AAE"

    public var isFloatingControlEnabled: Bool = true
    public var overlayOpacity: Double = 0.85

    public mutating func pan(dx: Double, dy: Double) {
        posX = max(-2.0, min(2.0, posX + dx))
        posY = max(-2.0, min(2.0, posY + dy))
    }

    public mutating func zoom(delta: Double) {
        scale = max(0.2, min(4.0, scale + delta))
    }

    public mutating func rotate90() {
        rotation = (rotation + 90.0).truncatingRemainder(dividingBy: 360.0)
    }

    public mutating func toggleFlipH() {
        isFlipped.toggle()
    }

    public mutating func toggleFlipV() {
        isFlippedV.toggle()
    }

    public mutating func reset() {
        self.posX = 0.0
        self.posY = 0.0
        self.scale = 1.0
        self.rotation = 0.0
        self.isFlipped = false
        self.isFlippedV = false
        self.overlayOpacity = 0.85
    }
}

public enum MediaKind: String, Codable {
    case none = "None"
    case image = "Image"
    case video = "Video"
    case stream = "Live Stream"
}

public struct MediaSource: Identifiable, Codable {
    public var id: UUID = UUID()
    public var kind: MediaKind
    public var title: String
    public var isLive: Bool
    public static let empty = MediaSource(kind: .none, title: "Chưa chọn nguồn phát", isLive: false)
}

public enum ConnectionType: String, CaseIterable, Identifiable {
    case wifi = "Wi-Fi"
    case usb = "USB"
    public var id: String { self.rawValue }
}

// ==========================================
// 2. AVFOUNDATION LIVE CAMERA MANAGER
// ==========================================

public class CameraManager: NSObject, ObservableObject {
    @Published public var session = AVCaptureSession()
    @Published public var isSessionRunning = false
    @Published public var currentPosition: AVCaptureDevice.Position = .front
    @Published public var isAuthorized = false

    private let sessionQueue = DispatchQueue(label: "com.vcamprovip.cameraQueue")

    public override init() {
        super.init()
        checkPermissions()
    }

    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted { self.setupSession() }
                }
            }
        default:
            self.isAuthorized = false
        }
    }

    public func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition) else {
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("Error: \(error)")
            }

            self.session.commitConfiguration()
            self.startSession()
        }
    }

    public func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isSessionRunning = true }
            }
        }
    }

    public func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isSessionRunning = false }
            }
        }
    }

    public func switchCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        setupSession()
    }
}

// ==========================================
// 3. UI VIEW REPRESENTABLE CAMERA PREVIEW
// ==========================================

public struct CameraPreviewView: UIViewRepresentable {
    public class VideoPreviewUIView: UIView {
        public override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        public var previewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }

    public let session: AVCaptureSession

    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

// ==========================================
// 4. VIEW MODEL
// ==========================================

public class AppViewModel: ObservableObject {
    @Published public var account: AccountInfo = AccountInfo()
    @Published public var config: CameraConfig = CameraConfig()
    @Published public var currentMedia: MediaSource = .empty
    @Published public var connectionType: ConnectionType = .wifi

    @Published public var isServerRunning: Bool = false
    @Published public var lanIP: String = "192.168.1.28"
    @Published public var obsStreamUrl: String = "rtmp://192.168.1.28/live"

    @Published public var selectedUIImage: UIImage? = nil
    @Published public var isPreviewExpanded: Bool = true
    @Published public var showToast: Bool = false
    @Published public var toastMessage: String = ""

    public let cameraManager = CameraManager()

    public init() {
        fetchLocalIP()
    }

    public func toggleServer() {
        isServerRunning.toggle()
        showNotification(msg: isServerRunning ? "Đã bật luồng OBS: \(obsStreamUrl)" : "Đã tắt máy chủ OBS")
    }

    public func resetTransform() {
        config.reset()
        showNotification(msg: "Đã đặt lại vị trí Camera")
    }

    public func updateMedia(kind: MediaKind, title: String, image: UIImage? = nil) {
        currentMedia = MediaSource(kind: kind, title: title, isLive: true)
        selectedUIImage = image
        showNotification(msg: "Đã chọn: \(title)")
    }

    public func removeMedia() {
        currentMedia = .empty
        selectedUIImage = nil
        showNotification(msg: "Đã xóa nguồn phát")
    }

    public func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showNotification(msg: "Đã sao chép: \(text)")
    }

    public func showNotification(msg: String) {
        toastMessage = msg
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showToast = false
        }
    }

    private func fetchLocalIP() {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        guard let firstAddr = ifaddr else { return }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        if let ip = address, !ip.isEmpty {
            self.lanIP = ip
            self.obsStreamUrl = "rtmp://\(ip)/live"
        }
    }
}

// ==========================================
// 5. COLOR EXTENSION
// ==========================================

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// ==========================================
// 6. LIVE CAMERA PREVIEW CARD COMPONENT
// ==========================================

struct LiveCameraPreviewCard: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#10B981"))
                        .frame(width: 8, height: 8)
                    Text("LIVE CAMERA PREVIEW")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: {
                    vm.cameraManager.switchCamera()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 13))
                        Text(vm.cameraManager.currentPosition == .front ? "Trước" : "Sau")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#38BDF8"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#1E293B"))
                    .cornerRadius(8)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(height: 250)

                if vm.cameraManager.isAuthorized {
                    CameraPreviewView(session: vm.cameraManager.session)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(height: 250)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        Text("Chạm để cấp quyền Camera")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }

                if vm.currentMedia.kind != .none {
                    Group {
                        if let img = vm.selectedUIImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.artframe")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                    Text(vm.currentMedia.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 140, height: 180)
                        }
                    }
                    .opacity(vm.config.overlayOpacity)
                    .offset(x: vm.config.posX * 120, y: vm.config.posY * 120)
                    .scaleEffect(vm.config.scale)
                    .rotationEffect(.degrees(vm.config.rotation))
                    .scaleEffect(x: vm.config.isFlipped ? -1 : 1, y: vm.config.isFlippedV ? -1 : 1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                vm.config.posX = Double(value.translation.width / 120)
                                vm.config.posY = Double(value.translation.height / 120)
                            }
                    )
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "viewfinder")
                            .font(.system(size: 28))
                            .foregroundColor(Color(hex: "#10B981").opacity(0.6))
                        Spacer()
                    }
                    Spacer()
                }

                VStack {
                    HStack {
                        Text(String(format: "ZOOM: %.1fx | PAN: (%.2f, %.2f) | R: %.0f°", vm.config.scale, vm.config.posX, vm.config.posY, vm.config.rotation))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding(10)
                    Spacer()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#10B981").opacity(0.4), lineWidth: 1.5)
            )

            HStack(spacing: 12) {
                Text("Độ mờ lớp phủ:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)

                Slider(value: $vm.config.overlayOpacity, in: 0.1...1.0)
                    .tint(Color(hex: "#10B981"))

                Text("\(Int(vm.config.overlayOpacity * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 40)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

// ==========================================
// 7. BRAND HEADER COMPONENT (VcamProVip)
// ==========================================

struct HeaderView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#F59E0B"), Color(hex: "#EC4899"), Color(hex: "#6366F1")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 58, height: 58)
                    .shadow(color: Color(hex: "#F59E0B").opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "camera.aperture")
                    .resizable().scaledToFit().frame(width: 32, height: 32).foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("VcamProVip")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text("PRO VIP")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#F59E0B"))
                        .cornerRadius(4)
                }

                Text("Nguồn: \(vm.currentMedia.kind == .none ? "Mặc định (IMG_0036)" : vm.currentMedia.title)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)

                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#10B981")).frame(width: 8, height: 8)
                    Text("Active • Live Engine Ready").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#10B981"))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct AccountCardView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").foregroundColor(Color(hex: "#F59E0B"))
                Text("Tài Khoản Bản Quyền").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "#10B981")).frame(width: 44, height: 44)
                    Image(systemName: "person.fill").foregroundColor(.black).font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.account.username).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(vm.account.accountType).font(.system(size: 13)).foregroundColor(Color(hex: "#F59E0B"))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16))
                    Text("Đăng\nxuất").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#EF4444"))
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HẠN BẢN QUYỀN").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                    Text(vm.account.expirationDate).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("SỐ THIẾT BỊ SỬ DỤNG").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                    Text("\(vm.account.devicesInUse) / \(vm.account.maxDevices)").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "#10B981"))
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct DeviceLinkCardView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color(hex: "#38BDF8"))
                Text("Kết nối OBS Studio").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(ConnectionType.allCases) { type in
                    Button(action: { vm.connectionType = type }) {
                        Text(type.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(vm.connectionType == type ? .white : .gray)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(vm.connectionType == type ? Color(hex: "#262626") : Color.clear)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(4).background(Color(hex: "#171717")).cornerRadius(10)

            HStack {
                Text("IP MẠNG").font(.system(size: 13, weight: .semibold)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                Spacer()
                Text(vm.lanIP).font(.system(size: 14, design: .monospaced)).foregroundColor(.white)
                Button(action: { vm.copyText(vm.lanIP) }) {
                    Image(systemName: "doc.on.doc").foregroundColor(Color(hex: "#38BDF8"))
                }
            }

            HStack {
                Text("OBS URL").font(.system(size: 13, weight: .semibold)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                Spacer()
                Text(vm.obsStreamUrl).font(.system(size: 13, design: .monospaced)).foregroundColor(.white).lineLimit(1)
                Button(action: { vm.copyText(vm.obsStreamUrl) }) {
                    Image(systemName: "doc.on.doc").foregroundColor(Color(hex: "#10B981"))
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "wifi").font(.system(size: 20)).foregroundColor(Color(hex: "#38BDF8"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wi-Fi Link").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    Text(vm.isServerRunning ? "Đang lắng nghe tín hiệu" : "Đã tắt").font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
            }

            Button(action: { vm.toggleServer() }) {
                HStack(spacing: 8) {
                    Image(systemName: vm.isServerRunning ? "stop.fill" : "play.fill")
                    Text(vm.isServerRunning ? "Dừng Máy Chủ OBS" : "Bật Máy Chủ OBS").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundColor(.white)
                .background(vm.isServerRunning ? Color(hex: "#EF4444") : Color(hex: "#10B981")).cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct DirectMediaCardView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedVideo: PhotosPickerItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundColor(Color(hex: "#F59E0B"))
                Text("Nguồn Media").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#1E1E1E")).frame(height: 100)
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#2B2B2B")).frame(width: 75, height: 70)
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundColor(.gray)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.currentMedia.kind == .none ? "Chưa chọn file" : vm.currentMedia.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Text("Sẵn sàng hiển thị lên Camera").font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                if vm.currentMedia.kind != .none {
                    Button(action: { vm.removeMedia() }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(.gray).padding(10)
                    }
                }
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo").font(.system(size: 16, weight: .semibold))
                        Text("Chọn Ảnh").font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundColor(.white)
                    .background(Color(hex: "#0284C7")).cornerRadius(10)
                }
                .onChange(of: selectedPhoto) { newItem in
                    guard let item = newItem else { return }
                    item.loadTransferable(type: Data.self) { result in
                        switch result {
                        case .success(let data):
                            if let d = data, let uiImg = UIImage(data: d) {
                                DispatchQueue.main.async {
                                    vm.updateMedia(kind: .image, title: "IMG_\(Int.random(in: 1000...9999)).JPG", image: uiImg)
                                }
                            }
                        case .failure:
                            break
                        }
                    }
                }

                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    HStack(spacing: 8) {
                        Image(systemName: "film").font(.system(size: 16, weight: .semibold))
                        Text("Chọn Video").font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundColor(.white)
                    .background(Color(hex: "#EA580C")).cornerRadius(10)
                }
                .onChange(of: selectedVideo) { _ in
                    vm.updateMedia(kind: .video, title: "VID_\(Int.random(in: 1000...9999)).MP4")
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct CameraBehaviorCardView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.2.square").foregroundColor(.gray)
                Text("Hành vi & Tinh chỉnh").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                Image(systemName: "eyedropper.halffull").font(.system(size: 18)).foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đồng bộ màu sắc").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text("Bật - Vùng \(vm.config.selectedSyncArea.rawValue)").font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                Toggle("", isOn: $vm.config.isColorSyncEnabled).labelsHidden().tint(Color(hex: "#10B981"))
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: vm.config.screenSampleHex)).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MẪU MÀU MÀN HÌNH").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                        Text(vm.config.screenSampleHex).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: "eyedropper").font(.system(size: 16)).foregroundColor(Color(hex: "#10B981"))
                }

                HStack(spacing: 6) {
                    ForEach(SyncTargetArea.allCases) { area in
                        Button(action: { vm.config.selectedSyncArea = area }) {
                            Text(area.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(vm.config.selectedSyncArea == area ? .black : .white)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(vm.config.selectedSyncArea == area ? Color(hex: "#10B981") : Color(hex: "#262626"))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(12).background(Color(hex: "#171717")).cornerRadius(12)

            HStack(spacing: 12) {
                Image(systemName: "square.2.layers.3d").font(.system(size: 18)).foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nút nổi điều khiển").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text(vm.config.isFloatingControlEnabled ? "Đang bật" : "Đã tắt").font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
                Toggle("", isOn: $vm.config.isFloatingControlEnabled).labelsHidden().tint(Color(hex: "#10B981"))
            }

            // Tọa độ & Reset
            HStack {
                Text(String(format: "X %.2f  Y +%.2f  %.2fx  R %.0f  H:%@ V:%@",
                            vm.config.posX, vm.config.posY, vm.config.scale, vm.config.rotation,
                            vm.config.isFlipped ? "BẬT" : "TẮT",
                            vm.config.isFlippedV ? "BẬT" : "TẮT"))
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                Button(action: { vm.resetTransform() }) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 18)).foregroundColor(Color(hex: "#10B981"))
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

// ==========================================
// 8. FLOATING CONTROL REMOTE HUD (NÂNG CẤP ĐA NĂNG)
// ==========================================

struct FloatingControlView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var offset: CGSize = CGSize(width: 120, height: -100)
    @State private var isExpanded: Bool = false

    var body: some View {
        if vm.config.isFloatingControlEnabled {
            ZStack {
                if !isExpanded {
                    // Nút nổi thu gọn (Draggable Floating Pill)
                    VStack(spacing: 8) {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isExpanded = true
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.9))
                                    .frame(width: 54, height: 54)
                                    .shadow(color: Color(hex: "#F59E0B").opacity(0.4), radius: 8, x: 0, y: 3)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(colors: [Color(hex: "#F59E0B"), Color(hex: "#10B981")], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 2.5
                                            )
                                    )

                                VStack(spacing: 2) {
                                    Image(systemName: "camera.aperture")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Color(hex: "#F59E0B"))
                                    Text("VIP")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.white)
                                }
                            }
                        }

                        // Nút tâm ngắm nhanh đưa về 0,0
                        Button(action: {
                            vm.resetTransform()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.85))
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                                Image(systemName: "scope")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                offset = CGSize(
                                    width: gesture.translation.width + offset.width,
                                    height: gesture.translation.height + offset.height
                                )
                            }
                    )
                } else {
                    // Bảng điều khiển nổi toàn năng (Expanded Remote HUD)
                    VStack(spacing: 12) {
                        // Header Bar
                        HStack {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .foregroundColor(Color(hex: "#F59E0B"))
                            Text("VcamProVip Remote")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)

                            Spacer()

                            // Nút Reset
                            Button(action: {
                                vm.resetTransform()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "#10B981"))
                                    .padding(6)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }

                            // Nút Thu nhỏ
                            Button(action: {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        // D-Pad Điều Hướng Di Chuyển (Pan X, Y) + Zoom Controls
                        HStack(spacing: 16) {
                            // Cụm phím D-Pad 4 chiều
                            VStack(spacing: 4) {
                                Button(action: { vm.config.pan(dx: 0, dy: -0.05) }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 36, height: 28)
                                        .background(Color(hex: "#262626"))
                                        .cornerRadius(6)
                                }

                                HStack(spacing: 4) {
                                    Button(action: { vm.config.pan(dx: -0.05, dy: 0) }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 28)
                                            .background(Color(hex: "#262626"))
                                            .cornerRadius(6)
                                    }

                                    Button(action: {
                                        vm.config.posX = 0
                                        vm.config.posY = 0
                                    }) {
                                        Circle()
                                            .fill(Color(hex: "#10B981"))
                                            .frame(width: 22, height: 22)
                                    }

                                    Button(action: { vm.config.pan(dx: 0.05, dy: 0) }) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 28)
                                            .background(Color(hex: "#262626"))
                                            .cornerRadius(6)
                                    }
                                }

                                Button(action: { vm.config.pan(dx: 0, dy: 0.05) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 36, height: 28)
                                        .background(Color(hex: "#262626"))
                                        .cornerRadius(6)
                                }
                            }
                            .foregroundColor(.white)

                            // Cụm Phóng To / Thu Nhỏ (Zoom)
                            VStack(spacing: 6) {
                                Text("ZOOM")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.gray)

                                HStack(spacing: 6) {
                                    Button(action: { vm.config.zoom(delta: -0.1) }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 32)
                                            .background(Color(hex: "#262626"))
                                            .cornerRadius(6)
                                    }

                                    Text(String(format: "%.1fx", vm.config.scale))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#38BDF8"))
                                        .frame(width: 44)

                                    Button(action: { vm.config.zoom(delta: 0.1) }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 32)
                                            .background(Color(hex: "#262626"))
                                            .cornerRadius(6)
                                    }
                                }
                                .foregroundColor(.white)

                                Text(String(format: "X:%.2f Y:%.2f", vm.config.posX, vm.config.posY))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }

                        Divider().background(Color.white.opacity(0.15))

                        // Hàng Nút Thao Tác Nhanh (Xoay 90°, Lật Ngang, Lật Dọc, Đổi Cam)
                        HStack(spacing: 6) {
                            // Xoay 90 độ
                            Button(action: { vm.config.rotate90() }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "rotate.right.fill")
                                        .font(.system(size: 13))
                                    Text("\(Int(vm.config.rotation))°")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#1E293B"))
                                .cornerRadius(8)
                            }

                            // Lật gương Ngang (Flip Horizontal)
                            Button(action: { vm.config.toggleFlipH() }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                        .font(.system(size: 12))
                                    Text(vm.config.isFlipped ? "Lật: Bật" : "Ngang")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(vm.config.isFlipped ? Color(hex: "#10B981") : Color(hex: "#1E293B"))
                                .foregroundColor(vm.config.isFlipped ? .black : .white)
                                .cornerRadius(8)
                            }

                            // Lật gương Dọc (Flip Vertical)
                            Button(action: { vm.config.toggleFlipV() }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down.fill")
                                        .font(.system(size: 12))
                                    Text(vm.config.isFlippedV ? "Dọc: Bật" : "Dọc")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(vm.config.isFlippedV ? Color(hex: "#10B981") : Color(hex: "#1E293B"))
                                .foregroundColor(vm.config.isFlippedV ? .black : .white)
                                .cornerRadius(8)
                            }

                            // Đổi Camera Trước / Sau
                            Button(action: { vm.cameraManager.switchCamera() }) {
                                VStack(spacing: 3) {
                                    Image(systemName: "camera.rotate.fill")
                                        .font(.system(size: 13))
                                    Text(vm.cameraManager.currentPosition == .front ? "Cam Sau" : "Cam Trước")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#0284C7"))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .padding(14)
                    .frame(width: 280)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(hex: "#0F172A").opacity(0.96))
                            .shadow(color: .black.opacity(0.6), radius: 15, x: 0, y: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(LinearGradient(colors: [Color(hex: "#F59E0B"), Color(hex: "#38BDF8")], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                            )
                    )
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                offset = CGSize(
                                    width: gesture.translation.width + offset.width,
                                    height: gesture.translation.height + offset.height
                                )
                            }
                    )
                }
            }
        }
    }
}

// ==========================================
// 9. MAIN VIEW & APP ENTRY
// ==========================================

struct MainView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ZStack {
            Color(hex: "#0C0C0E").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .foregroundColor(Color(hex: "#F59E0B"))
                    Text("VcamProVip")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.top, 10).padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        HeaderView()
                        LiveCameraPreviewCard()
                        AccountCardView()
                        DeviceLinkCardView()
                        DirectMediaCardView()
                        CameraBehaviorCardView()
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Remote Điều Khiển Nổi (Floating Control HUD)
            FloatingControlView()

            if vm.showToast {
                VStack {
                    Spacer()
                    Text(vm.toastMessage)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)))
                        .padding(.bottom, 30)
                }
            }
        }
    }
}

@main
struct VcamProVipApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
