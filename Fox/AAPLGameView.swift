//
//  AAPLGameView.swift
//  Fox
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/1.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    The view displaying the game scene. Handles keyboard (OS X) and touch (iOS) input for controlling the game.
*/

import SceneKit
import SpriteKit

//Floating point type used in SCNVectors.
#if os(iOS)
    typealias SCNFloat = Float
#else
    typealias SCNFloat = CGFloat
#endif

@objc(AAPLGameView)
class AAPLGameView: SCNView {
    
    @IBOutlet weak var controller: AAPLGameViewController!
    var collectedFlowers: Int = 0
    var collectedPearls: Int = 0
    
    enum AAPLDirection: Int {
        case Up
        case Left
        case Right
        case Down
        static let Count = Down.rawValue+1
    }
    
    #if !os(iOS)
    private var keyPressed: [Bool] = Array(count: AAPLDirection.Count, repeatedValue: false)
    private var _lastMousePosition: CGPoint = CGPoint()
    #else
    private var _direction: CGPoint = CGPoint()
    private var _panningTouch: UITouch?
    private var _padTouch: UITouch?
    #endif
    
    private var _padRect: CGRect = CGRect()
    private var _flowers: [SKSpriteNode] = []
    private var _pearlLabel: SKLabelNode?
    private var _overlayGroup: SKNode?
    private var _pearlCount: Int = 0
    private var _flowerCount: Int = 0
    
    private var _directionCacheValid: Bool = false
    private var _directionCache: SCNVector3 = SCNVector3()
    
    private var _defaultFov: Double = 0
    
    //MARK: Initial Setup
    
    func setup() {
        var w = self.bounds.size.width
        var h = self.bounds.size.height
        
        #if os(iOS)
            // Support Landscape scape
            if w < h {
                (w, h) = (h, w)
            }
        #endif
        
        // Setup the game overlays using SpriteKit.
        let skScene = SKScene(size: CGSizeMake(w, h))
        skScene.scaleMode = .ResizeFill
        
        _overlayGroup = SKNode()
        skScene.addChild(_overlayGroup!)
        _overlayGroup!.position = CGPointMake(0, h)
        
        // The Max icon.
        var sprite = SKSpriteNode(imageNamed: "MaxIcon.png")
        sprite.position = CGPointMake(50, -50)
        _overlayGroup!.addChild(sprite)
        sprite.xScale = 0.5
        sprite.yScale = 0.5
        
        // The flowers.
        _flowers.removeAll()
        for i in 0..<3 {
            _flowers.append(SKSpriteNode(imageNamed: "FlowerEmpty.png"))
            _flowers[i].position = CGPointMake(110 + CGFloat(i)*40, -50)
            _flowers[i].xScale = 0.25
            _flowers[i].yScale = 0.25
            _overlayGroup!.addChild(_flowers[i])
        }
        
        // The peal icon and count.
        sprite = SKSpriteNode(imageNamed: "ItemsPearl.png")
        sprite.position = CGPointMake(110, -100)
        sprite.xScale = 0.5
        sprite.yScale = 0.5
        _overlayGroup!.addChild(sprite)
        
        _pearlLabel = SKLabelNode(fontNamed: "Chalkduster")
        _pearlLabel!.text = "x0"
        _pearlLabel!.position = CGPointMake(152, -113)
        _overlayGroup!.addChild(_pearlLabel!)
        
        // The D-Pad
        #if SHOW_DPAD && os(iOS)
            let DPAD_RADIUS: CGFloat = 80
            sprite = SKSpriteNode(imageNamed: "dpad.png")
            sprite.position = CGPointMake(100, 100)
            sprite.xScale = 0.5
            sprite.yScale = 0.5
            skScene.addChild(sprite)
            
            _padRect = CGRectMake((sprite.position.y-DPAD_RADIUS)/w, 1.0 - ((sprite.position.y + DPAD_RADIUS) / h), 2 * DPAD_RADIUS/w, 2 * DPAD_RADIUS/h)
        #else
            _padRect = CGRectMake(0, 0.7, 0.3, 0.3)
        #endif
        
        // Assign the SpriteKit overlay to the SceneKit view.
        self.overlaySKScene = skScene
        
        // Setup the pinch gesture
        _defaultFov = self.pointOfView!.camera!.xFov
        
        #if os(iOS)
            let pinch = UIPinchGestureRecognizer()
            pinch.delegate = self
            pinch.addTarget(self, action: "pinchWithGestureRecognizer:")
            pinch.cancelsTouchesInView = false
            self.addGestureRecognizer(pinch)
        #endif
    }
    
    //MARK: Overlays
    
    func didCollectAFlower() -> Bool {
        if _flowerCount < 3 {
            _flowers[_flowerCount].texture = SKTexture(imageNamed: "FlowerFull.png")
        }
        
        _flowerCount++
        
        return _flowerCount == 3 // Return YES when every flowers are collected.
    }
    
    
    func didCollectAPearl() {
        _pearlCount++
        if (_pearlCount == 10) {
            _pearlLabel!.position = CGPointMake(158, _pearlLabel!.position.y)
        }
        
        _pearlLabel!.text = "x\(_pearlCount)"
    }
    
    //MARK: Events
    
    #if !os(iOS)
    
    // Override setFrame to update SpriteKit overlays
    override var frame: NSRect {
    get {
    return super.frame
    }
    set {
    super.frame = newValue
    
    //update SpriteKit overlays
    _overlayGroup!.position = CGPointMake(0, newValue.size.height)
    }
    }
    
    override func mouseDown(theEvent: NSEvent) {
    // Remember last mouse position for dragging.
    _lastMousePosition = self.convertPoint(theEvent.locationInWindow, fromView: nil)
    super.mouseDown(theEvent)
    }
    
    override func mouseDragged(theEvent: NSEvent) {
    _directionCacheValid = false
    
    let mousePosition = self.convertPoint(theEvent.locationInWindow, fromView: nil)
    
    // Pan the camera on drag.
    self.controller.panCamera(CGSizeMake(mousePosition.x-_lastMousePosition.x, mousePosition.y-_lastMousePosition.y))
    _lastMousePosition = mousePosition
    
    super.mouseDragged(theEvent)
    }
    
    // Keep a cache of pressed keys.
    override func keyDown(theEvent: NSEvent) {
    _directionCacheValid = false
    
    let firstChar = theEvent.charactersIgnoringModifiers!.utf16[String.UTF16Index(_offset: 0)]
    
    switch Int(firstChar) {
    case NSUpArrowFunctionKey:
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Up.rawValue] = true
    }
    return
    case NSDownArrowFunctionKey:
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Down.rawValue] = true
    }
    return
    case NSRightArrowFunctionKey: //
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Right.rawValue] = true
    }
    return
    case NSLeftArrowFunctionKey:
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Left.rawValue] = true
    }
    return
    default:
    break
    }
    
    super.keyDown(theEvent)
    }
    
    override func keyUp(theEvent: NSEvent) {
    _directionCacheValid = false
    
    let firstChar = theEvent.charactersIgnoringModifiers!.utf16[String.UTF16Index(_offset: 0)]
    
    switch Int(firstChar) {
    case NSUpArrowFunctionKey: // accelerate forward
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Up.rawValue] = false
    }
    return
    case NSDownArrowFunctionKey: // accelerate forward
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Down.rawValue] = false
    }
    return
    case NSRightArrowFunctionKey: //
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Right.rawValue] = false
    }
    return
    case NSLeftArrowFunctionKey:
    if !theEvent.ARepeat {
    keyPressed[AAPLDirection.Left.rawValue] = false
    }
    return
    default:
    break
    }
    
    super.keyUp(theEvent)
    }
    #else  // TARGET_OS_IPHONE
    
    private func touch(touch: UITouch, var isInRect rect: CGRect) -> Bool {
        let bounds = self.bounds
        rect = CGRectApplyAffineTransform(rect, CGAffineTransformMakeScale(bounds.size.width, bounds.size.height))
        return CGRectContainsPoint(rect, touch.locationInView(self))
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        for touch in touches {
            if self.touch(touch, isInRect: _padRect) {
                // We're in the dpad
                if _padTouch == nil {
                    _padTouch = touch
                }
            } else if _panningTouch == nil {
                // Start panning
                _panningTouch = touches.first
            }
            
            if _padTouch != nil && _panningTouch != nil {
                break  // We already have what we need
            }
        }
        super.touchesBegan(touches, withEvent: event)
    }
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        _directionCacheValid = false
        
        if let panningTouch = _panningTouch {
            let _p0 = panningTouch.previousLocationInView(self)
            let _p1 = panningTouch.locationInView(self)
            
            self.controller.panCamera(CGSizeMake(_p1.x-_p0.x, _p0.y-_p1.y))
        }
        
        if let padTouch = _padTouch {
            let _p0 = padTouch.previousLocationInView(self)
            let _p1 = padTouch.locationInView(self)
            
            let SPEED: CGFloat = 1.0 / 10.0
            let LIMIT: CGFloat = 1
            _direction.x += (_p1.x-_p0.x) * SPEED
            _direction.y += (_p1.y-_p0.y) * SPEED
            
            if _direction.x > LIMIT {
                _direction.x = LIMIT
            }
            
            if _direction.x < -LIMIT {
                _direction.x = -LIMIT
            }
            
            if _direction.y > LIMIT {
                _direction.y = LIMIT
            }
            
            if _direction.y < -LIMIT {
                _direction.y = -LIMIT
            }
            
            self.directionDidChange()
        }
        super.touchesMoved(touches, withEvent: event)
    }
    
    private func commonTouchesEnded(touches: Set<UITouch>?, withEvent event: UIEvent?) {
        if let panningTouch = _panningTouch
            where touches?.contains(panningTouch) ?? false {
                _panningTouch = nil
        }
        
        if let padTouch = _padTouch
            where touches?.contains(padTouch) ?? false
                || !(event?.touchesForView(self)?.contains(padTouch) ?? false) {
                    _padTouch = nil
                    _direction = CGPointMake(0, 0)
                    self.directionDidChange()
        }
    }
    
    override func touchesCancelled(touches: Set<UITouch>?, withEvent event: UIEvent?) {
        self.commonTouchesEnded(touches, withEvent: event)
        super.touchesCancelled(touches, withEvent: event)
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        self.commonTouchesEnded(touches, withEvent: event)
        super.touchesEnded(touches, withEvent: event)
    }
    
    @objc func pinchWithGestureRecognizer(recognizer: UIPinchGestureRecognizer) {
        SCNTransaction.begin()
        SCNTransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut))
        
        var fov = _defaultFov
        var constraintFactor: Double = 0
        
        if recognizer.state == .Ended || recognizer.state == .Cancelled {
            //back to initial zoom
            SCNTransaction.setAnimationDuration(0.5)
        } else {
            SCNTransaction.setAnimationDuration(0.1)
            if recognizer.scale > 1 {
                let scale = 1.0 + Double((recognizer.scale - 1) * 0.75); //make pinch smoother
                fov *= 1 / scale; //zoom on pinch
                constraintFactor = min(1,(scale - 1) * 0.75); //focus on character when pinching
            }
        }
        
        self.pointOfView!.camera!.xFov = fov
        self.pointOfView!.constraints![0].influenceFactor = CGFloat(constraintFactor)
        
        SCNTransaction.commit()
    }
    
    
    func shouldAutorotateToInterfaceOrientation(interfaceOrientation: UIInterfaceOrientation) -> Bool {
        return interfaceOrientation == .LandscapeRight || interfaceOrientation == .LandscapeLeft
    }
    
    func shouldAutorotate() -> Bool {
        return false
    }
    
    func supportedInterfaceOrientations() -> Int {
        return UIDeviceOrientation.LandscapeRight.rawValue | UIDeviceOrientation.LandscapeLeft.rawValue
    }
    
    #endif // TARGET_OS_IPHONE
    
    private func directionDidChange() {
        _directionCacheValid = false
    }
    
    private func directionFromPressedKeys() -> CGPoint {
        #if !os(iOS)
            var d = CGPointMake(0, 0)
            
            if keyPressed[AAPLDirection.Up.rawValue] {
                d.y -= 1
            }
            if keyPressed[AAPLDirection.Down.rawValue] {
                d.y += 1
            }
            if keyPressed[AAPLDirection.Left.rawValue] {
                d.x -= 1
            }
            if keyPressed[AAPLDirection.Right.rawValue] {
                d.x += 1
            }
            
            return d
        #else
            return _direction
        #endif
    }
    
    // returns the direction based on the pressed keys and the current camera orientation
    private func computeDirection() -> SCNVector3 {
        let p = self.directionFromPressedKeys()
        var dir = SCNVector3Make(SCNFloat(p.x), 0, SCNFloat(p.y))
        var p0 = SCNVector3Make(0, 0, 0)
        
        dir = (self.pointOfView?.presentationNode.convertPosition(dir, toNode: nil))!
        p0 = (self.pointOfView?.presentationNode.convertPosition(p0, toNode: nil))!
        
        dir = SCNVector3Make(dir.x - p0.x, 0, dir.z - p0.z)
        
        if dir.x != 0 || dir.z != 0 {
            //normalize
            dir = SCNVector3FromFloat3(vector_normalize(SCNVector3ToFloat3(dir)))
        }
        
        return dir
    }
    
    var direction: SCNVector3 {
        if !_directionCacheValid {
            _directionCache = self.computeDirection()
            _directionCacheValid = true
        }
        
        return _directionCache
    }
}
#if os(iOS)
    extension AAPLGameView: UIGestureRecognizerDelegate {
        override func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UIPinchGestureRecognizer && _padTouch != nil {
                return false
            }
            
            return true
        }
    }
#endif
