//
//  RemoteTVExtensionBundle.swift
//  RemoteTVExtension
//

import SwiftUI
import WidgetKit

/// `@main` entry point of the Control Center / Lock Screen widget extension. A widget
/// extension's principal type is its `WidgetBundle`; every `ControlWidget` it vends shows
/// up in the controls gallery (Settings → Control Center, or the Lock Screen editor).
@main
struct RemoteTVExtensionBundle: WidgetBundle {
    var body: some Widget {
        TVPowerControl()
        TVMuteControl()
        TVVolumeUpControl()
        TVVolumeDownControl()
        TVChannelUpControl()
        TVChannelDownControl()
        OpenRemoteTVAppControl()
    }
}
