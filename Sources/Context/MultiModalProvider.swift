import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Provides camera and screen capture frames for multi-modal Gemini Live sessions.
///
/// Supports two capture modes:
/// - **Camera**: Captures from the FaceTime/built-in camera using `AVCaptureSession`.
/// - **Screen**: Captures the primary display using `ScreenCaptureKit`.
///
/// Captured frames are JPEG-encoded and delivered via ``onFrameCaptured`` for
/// transmission to the Gemini Live API as `inlineData` alongside audio.
///
/// - Important: Requires Camera and Screen Recording permissions in the app entitlements
///   and user authorization.
@MainActor
final class MultiModalProvider: NSObject {

    // MARK: - Types

    /// The type of visual capture currently active.
    enum CaptureMode: String, Sendable {
        case camera
        case screen
    }

    /// A captured frame ready for transmission to Gemini.
    struct CapturedFrame: Sendable {
        /// JPEG-encoded image data.
        let imageData: Data

        /// MIME type for the image data.
        let mimeType: String = "image/jpeg"
    }

    // MARK: - Public Properties

    /// Called when a new frame is captured, with JPEG data ready for Gemini.
    var onFrameCaptured: ((_ frame: CapturedFrame) -> Void)?

    /// Whether camera capture is currently active.
    private(set) var isCameraActive: Bool = false

    /// Whether screen capture is currently active.
    private(set) var isScreenActive: Bool = false

    // MARK: - Private Properties — Camera

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "com.quinnvoice.camera", qos: .userInitiated)

    // MARK: - Private Properties — Screen

    private var screenCaptureStream: SCStream?
    private var screenStreamOutput: ScreenStreamOutput?

    // MARK: - Private Properties — Frame Rate

    /// Target frames per second for capture. Lower = less bandwidth.
    private let targetFPS: Double = 2.0
    private var lastFrameTime: Date = .distantPast

    /// JPEG compression quality (0.0 = max compression, 1.0 = best quality).
    private let jpegQuality: CGFloat = 0.5

    /// Maximum image dimension (width or height) before downscaling.
    private let maxDimension: CGFloat = 1024

    // MARK: - Camera Capture

    /// Start capturing frames from the built-in camera (FaceTime camera).
    ///
    /// - Throws: If the camera is unavailable or the capture session fails to start.
    func startCamera() throws {
        guard !isCameraActive else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        // Find the built-in camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            throw CaptureError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CaptureError.cameraUnavailable
        }
        session.addInput(input)

        // Configure video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw CaptureError.cameraUnavailable
        }
        session.addOutput(output)

        self.captureSession = session
        self.videoOutput = output

        session.startRunning()
        isCameraActive = true
    }

    /// Stop camera capture and release resources.
    func stopCamera() {
        guard isCameraActive else { return }
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        isCameraActive = false
    }

    // MARK: - Screen Capture

    /// Start capturing the primary display using ScreenCaptureKit.
    ///
    /// - Throws: If screen recording permission is denied or no displays are available.
    func startScreenCapture() async throws {
        guard !isScreenActive else { return }

        // Get available content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw CaptureError.screenUnavailable
        }

        // Configure the stream filter — capture the whole display
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream settings
        let config = SCStreamConfiguration()
        config.width = Int(min(CGFloat(display.width), maxDimension))
        config.height = Int(min(CGFloat(display.height), maxDimension * CGFloat(display.height) / CGFloat(display.width)))
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = ScreenStreamOutput { [weak self] sampleBuffer in
            Task { @MainActor [weak self] in
                self?.processScreenFrame(sampleBuffer)
            }
        }
        self.screenStreamOutput = output

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.screenCaptureStream = stream
        isScreenActive = true
    }

    /// Stop screen capture and release resources.
    func stopScreenCapture() async {
        guard isScreenActive else { return }

        if let stream = screenCaptureStream {
            try? await stream.stopCapture()
        }
        screenCaptureStream = nil
        screenStreamOutput = nil
        isScreenActive = false
    }

    /// Stop all active captures.
    func stopAll() async {
        stopCamera()
        await stopScreenCapture()
    }

    // MARK: - Frame Processing

    /// Process a camera sample buffer into a JPEG frame.
    private nonisolated func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard let jpegData = pixelBufferToJPEG(pixelBuffer) else { return }

        let frame = CapturedFrame(imageData: jpegData)
        let fps = targetFPS
        Task { @MainActor in
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFrameTime)
            guard elapsed >= (1.0 / fps) else { return }
            self.lastFrameTime = now
            self.onFrameCaptured?(frame)
        }
    }

    /// Process a screen capture sample buffer into a JPEG frame.
    private func processScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastFrameTime)
        guard elapsed >= (1.0 / targetFPS) else { return }
        lastFrameTime = now

        guard let jpegData = pixelBufferToJPEG(pixelBuffer) else { return }

        let frame = CapturedFrame(imageData: jpegData)
        onFrameCaptured?(frame)
    }

    /// Convert a CVPixelBuffer to JPEG data, downscaling if necessary.
    private nonisolated func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        // Determine scale factor for downscaling
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let maxDim = max(width, height)

        var finalImage = ciImage
        if maxDim > maxDimension {
            let scale = maxDimension / maxDim
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            finalImage = ciImage.transformed(by: transform)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return context.jpegRepresentation(of: finalImage, colorSpace: colorSpace, options: [:])
    }

    // MARK: - Permission Check

    /// Check if the app has camera access authorization.
    ///
    /// - Parameter request: If `true`, prompts the user for camera access.
    /// - Returns: `true` if camera access is authorized.
    static func checkCameraPermission(request: Bool = false) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            if request {
                return await AVCaptureDevice.requestAccess(for: .video)
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Errors

    enum CaptureError: Error, LocalizedError {
        case cameraUnavailable
        case screenUnavailable
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is not available"
            case .screenUnavailable: return "No display available for screen capture"
            case .permissionDenied: return "Permission denied for capture"
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension MultiModalProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processCameraFrame(sampleBuffer)
    }
}

// MARK: - Screen Capture Stream Output

/// Helper class to receive ScreenCaptureKit stream output.
private final class ScreenStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}
