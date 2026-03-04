//
//  EchoMindLiveActivityBundle.swift
//  EchoMindLiveActivity
//
//  Created by Oleksandr Stepanov on 03.03.26.
//

import WidgetKit
import SwiftUI

@main
struct EchoMindLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        EchoMindLiveActivity()
        EchoMindLiveActivityControl()
        EchoMindRecordingLiveActivityWidget()
        EchoMindModelDownloadLiveActivityWidget()
    }
}
