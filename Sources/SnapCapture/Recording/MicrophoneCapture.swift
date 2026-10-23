import AVFoundation

/// The default microphone, delivered as 48 kHz stereo Float32 PCM to match the system audio.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let handler: (CMSampleBuffer) -> Void

    /// `handler` runs on `queue`.
    init(queue: DispatchQueue, handler: @escaping (CMSampleBuffer) -> Void) throws {
        self.handler = handler
        super.init()
        guard let device = AVCaptureDevice.default(for: .audio) else { throw RecordingError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw RecordingError.noMicrophone }
        session.addInput(input)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
    }

    /// Asks for microphone access the first time.
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() { session.startRunning() }
    func stop() { session.stopRunning() }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handler(sampleBuffer)
    }
}
