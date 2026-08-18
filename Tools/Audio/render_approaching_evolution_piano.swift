#!/usr/bin/env swift

import AVFoundation
import AudioToolbox
import Foundation

private struct PianoEvent {
    let frame: AVAudioFramePosition
    let isNoteOn: Bool
    let note: UInt8
    let velocity: UInt8
    let channel: UInt8
}

private enum RenderFailure: Error, CustomStringConvertible {
    case usage
    case badEvent(String)
    case noRenderBuffer
    case renderFailed(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: render_approaching_evolution_piano.swift EVENTS.tsv OUTPUT.wav FRAME_COUNT PROGRAM"
        case .badEvent(let line):
            return "invalid piano event: \(line)"
        case .noRenderBuffer:
            return "could not allocate the offline render buffer"
        case .renderFailed(let message):
            return "offline piano render failed: \(message)"
        }
    }
}

private let sampleRate = 44_100.0
private let maximumBlock: AVAudioFrameCount = 4_096
private let soundBank = URL(
    fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
)

private func readEvents(at url: URL, totalFrames: AVAudioFramePosition) throws -> [PianoEvent] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var events: [PianoEvent] = []

    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let fields = line.split(separator: "\t")
        guard fields.count == 5,
              let frame = AVAudioFramePosition(fields[0]),
              let note = UInt8(fields[2]),
              let velocity = UInt8(fields[3]),
              let channel = UInt8(fields[4]),
              (fields[1] == "on" || fields[1] == "off"),
              frame >= 0,
              frame < totalFrames,
              note <= 127,
              channel <= 15 else {
            throw RenderFailure.badEvent(line)
        }
        events.append(PianoEvent(
            frame: frame,
            isNoteOn: fields[1] == "on",
            note: note,
            velocity: velocity,
            channel: channel
        ))
    }

    // At one frame, release repeated notes before starting their replacements.
    return events.sorted {
        if $0.frame != $1.frame { return $0.frame < $1.frame }
        if $0.isNoteOn != $1.isNoteOn { return !$0.isNoteOn }
        if $0.channel != $1.channel { return $0.channel < $1.channel }
        return $0.note < $1.note
    }
}

private func renderFrames(
    _ count: AVAudioFramePosition,
    engine: AVAudioEngine,
    buffer: AVAudioPCMBuffer,
    file: AVAudioFile
) throws {
    var remaining = count
    while remaining > 0 {
        let requested = AVAudioFrameCount(min(remaining, AVAudioFramePosition(maximumBlock)))
        let status = try engine.renderOffline(requested, to: buffer)
        switch status {
        case .success:
            try file.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        case .cannotDoInCurrentContext:
            continue
        case .insufficientDataFromInputNode:
            throw RenderFailure.renderFailed("sampler returned insufficient data")
        case .error:
            throw RenderFailure.renderFailed("AVAudioEngine returned an error")
        @unknown default:
            throw RenderFailure.renderFailed("AVAudioEngine returned an unknown status")
        }
    }
}

private func run() throws {
    guard CommandLine.arguments.count == 5,
          let totalFrames = AVAudioFramePosition(CommandLine.arguments[3]),
          let program = UInt8(CommandLine.arguments[4]),
          program <= 127,
          totalFrames > 0 else {
        throw RenderFailure.usage
    }

    let eventsURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let events = try readEvents(at: eventsURL, totalFrames: totalFrames)

    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: nil)

    try sampler.loadSoundBankInstrument(
        at: soundBank,
        program: program,
        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8(kAUSampler_DefaultBankLSB)
    )

    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
    ) else {
        throw RenderFailure.renderFailed("could not create the 44.1 kHz stereo format")
    }

    try engine.enableManualRenderingMode(
        .offline,
        format: format,
        maximumFrameCount: maximumBlock
    )
    try engine.start()

    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    try? FileManager.default.removeItem(at: outputURL)
    let file = try AVAudioFile(forWriting: outputURL, settings: settings)
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat,
        frameCapacity: maximumBlock
    ) else {
        throw RenderFailure.noRenderBuffer
    }

    var cursor: AVAudioFramePosition = 0
    var index = 0
    while index < events.count {
        let eventFrame = events[index].frame
        if eventFrame > cursor {
            try renderFrames(eventFrame - cursor, engine: engine, buffer: buffer, file: file)
            cursor = eventFrame
        }
        while index < events.count && events[index].frame == eventFrame {
            let event = events[index]
            if event.isNoteOn {
                sampler.startNote(event.note, withVelocity: event.velocity, onChannel: event.channel)
            } else {
                sampler.stopNote(event.note, onChannel: event.channel)
            }
            index += 1
        }
    }

    if cursor < totalFrames {
        try renderFrames(totalFrames - cursor, engine: engine, buffer: buffer, file: file)
    }
    engine.stop()
    engine.disableManualRenderingMode()
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
