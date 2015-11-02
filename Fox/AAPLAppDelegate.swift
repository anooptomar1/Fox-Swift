//
//  AAPLAppDelegate.swift
//  Fox
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/2.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    The OSX implementation of the application delegate of the game.
*/

import Cocoa

@NSApplicationMain
@objc(AAPLAppDelegate)
class AAPLAppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    
    func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication) -> Bool {
        return true
    }
    
}