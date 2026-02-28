//
//  RecordingFile.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Foundation


struct RecordingFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    private static let createdAtFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var fileName: String {
        url.lastPathComponent
    }

    var displayTitle: String {
        url.deletingPathExtension().lastPathComponent
    }
    //using var for flexible changes in case of time format change for instance
    var createdAtFormatted: String {
        Self.createdAtFormatter.string(from: createdAt)
    }

    var durationFormatted: String {
        let total = Int(duration.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
