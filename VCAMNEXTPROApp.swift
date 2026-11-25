import SwiftUI
import PhotosUI
import Combine

// ==========================================
// 1. DATA MODELS
// ==========================================

public enum SyncTargetArea: String, CaseIterable, Identifiable, Codable {
    case face = "Face"
    case forehead = "Forehead"
    case chin = "Chin"
    case sides = "Sides"
    public var id: String { self.rawValue }
}

public struct AccountInfo: Codable {
    public var username: String = "cuuam"
    public var accountType: String = "Managed account"
    public var expirationDate: String = "15/02/2054"
    public var devicesInUse: Int = 18
    public var maxDevices: Int = 999
    public var isActive: Bool = true
}

public struct CameraConfig: Codable {
    public var posX: Double = -0.04
    public var posY: Double = 0.14
    public var scale: Double = 1.35
    public var rotation: Double = 0.0
    public var isFlipped: Bool = false
    public var isColorSyncEnabled: Bool = true
    public var selectedSyncArea: SyncTargetArea = .face
    public var screenSampleHex: String = "#2B4AAE"
    public var isFloatingControlEnabled: Bool = true

    public mutating func reset() {
        self.posX = -0.04
        self.posY = 0.14
        self.scale = 1.35
        self.rotation = 0.0
        self.isFlipped = false
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
    public static let empty = MediaSource(kind: .none, title: "No source selected", isLive: false)
}

public enum ConnectionType: String, CaseIterable, Identifiable {
    case wifi = "Wi-Fi"
    case usb = "USB"
    public var id: String { self.rawValue }
}

// ==========================================
// 2. VIEW MODEL
// ==========================================

public class AppViewModel: ObservableObject {
    @Published public var account: AccountInfo = AccountInfo()
    @Published public var config: CameraConfig = CameraConfig()
    @Published public var currentMedia: MediaSource = .empty
    @Published public var connectionType: ConnectionType = .wifi

    @Published public var isServerRunning: Bool = false
    @Published public var lanIP: String = "192.168.1.28"
    @Published public var obsStreamUrl: String = "rtmp://192.168.1.28/live"

    @Published public var showToast: Bool = false
    @Published public var toastMessage: String = ""

    public init() {
        fetchLocalIP()
    }

    public func toggleServer() {
        isServerRunning.toggle()
        showNotification(msg: isServerRunning ? "Server started at \(obsStreamUrl)" : "Server stopped")
    }

    public func resetTransform() {
        config.reset()
        showNotification(msg: "Camera parameters reset")
    }

    public func updateMedia(kind: MediaKind, title: String) {
        currentMedia = MediaSource(kind: kind, title: title, isLive: true)
        showNotification(msg: "Loaded: \(title)")
    }

    public func removeMedia() {
        currentMedia = .empty
        showNotification(msg: "Media cleared")
    }

    public func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showNotification(msg: "Copied: \(text)")
    }

    private func showNotification(msg: String) {
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
// 3. COLOR EXTENSION
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
// 4. UI COMPONENTS
// ==========================================

struct HeaderView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.8), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 58, height: 58)
                Image(systemName: "camera.aperture")
                    .resizable().scaledToFit().frame(width: 32, height: 32).foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("VCAMNEXTPRO")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Camera source: \(vm.currentMedia.kind == .none ? "IMG_0036" : vm.currentMedia.title)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Active").font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct AccountCardView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle").foregroundColor(.gray)
                Text("Account").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "#10B981")).frame(width: 44, height: 44)
                    Image(systemName: "person.fill").foregroundColor(.black).font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.account.username).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(vm.account.accountType).font(.system(size: 13)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16))
                    Text("Log\nout").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#EF4444"))
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPIRES").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                    Text(vm.account.expirationDate).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("DEVICES IN USE").font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
                    Text("\(vm.account.devicesInUse) / \(vm.account.maxDevices)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct DeviceLinkCardView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundColor(.gray)
                Text("Device link").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
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
                Text("LAN IP").font(.system(size: 13, weight: .semibold)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
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
                    Text(vm.isServerRunning ? "Active" : "Disabled").font(.system(size: 12)).foregroundColor(.gray)
                }
                Spacer()
            }

            Button(action: { vm.toggleServer() }) {
                HStack(spacing: 8) {
                    Image(systemName: vm.isServerRunning ? "stop.fill" : "play.fill")
                    Text(vm.isServerRunning ? "Stop Server" : "Start Server").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundColor(.white)
                .background(vm.isServerRunning ? Color(hex: "#EF4444") : Color(hex: "#10B981")).cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
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
                Image(systemName: "square.and.arrow.down").foregroundColor(.gray)
                Text("Direct media").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
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
                        Text(vm.currentMedia.kind == .none ? "No source selected" : vm.currentMedia.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Text("Ready for camera output").font(.system(size: 12)).foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).frame(maxHeight: .infinity)

                if vm.currentMedia.kind != .none {
                    Button(action: { vm.removeMedia() }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(.gray).padding(10)
