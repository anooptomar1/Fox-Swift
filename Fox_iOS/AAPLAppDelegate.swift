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
    The iOS implementation of the application delegate of the game.
*/

import UIKit

@UIApplicationMain
@objc(AAPLAppDelegate)
class AAPLAppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    
    func application(application: UIApplication, supportedInterfaceOrientationsForWindow window: UIWindow?) -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Landscape
    }
    
}