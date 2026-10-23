import AVFoundation

/// Merges a movie's audio tracks (system sound and microphone) into one. Browsers and chat apps
/// mostly play only the first audio track, so separate tracks would lose the voice-over.
enum AudioMixdown {
    /// Rewrites `url` in place: video is copied as is, audio tracks are mixed into one AAC track.
    /// Movies with fewer than two audio tracks are left alone.
    static func mergeAudioTracks(in url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1, let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(videoOutput)
        reader.add(audioOutput)

        let merged = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: merged, fileType: .mp4)
        let videoFormat = try await videoTrack.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: MovieWriter.audioSettings)
        writer.add(videoInput)
        writer.add(audioInput)

        guard reader.startReading(), writer.startWriting() else {
            throw writer.error ?? reader.error ?? RecordingError.writeFailed
        }
        writer.startSession(atSourceTime: .zero)
        async let videoDone: Void = copy(videoOutput, to: videoInput, label: "video")
        async let audioDone: Void = copy(audioOutput, to: audioInput, label: "audio")
        _ = await (videoDone, audioDone)
        await writer.finishWriting()
        guard writer.status == .completed, reader.status == .completed else {
            try? FileManager.default.removeItem(at: merged)
            throw writer.error ?? reader.error ?? RecordingError.writeFailed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: merged)
    }

    private static func copy(_ output: AVAssetReaderOutput, to input: AVAssetWriterInput, label: String) async {
        let queue = DispatchQueue(label: "Snap.AudioMixdown.\(label)")
        // Both are only touched from `queue` from here on.
        let pair = Unchecked((output, input))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pair.value.1.requestMediaDataWhenReady(on: queue) {
                let (output, input) = pair.value
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    input.append(sample)
                }
            }
        }
    }
}

/// Carries a value into a `@Sendable` closure when access is serialized by other means.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
