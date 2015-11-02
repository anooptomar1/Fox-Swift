//
//  AAPLGameViewController.swift
//  Fox
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/1.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    This class manages most of the game logic.
*/

import SceneKit
import AVFoundation
import SpriteKit

// Collision bit masks
let AAPLBitmaskCollision        = 1 << 2
let AAPLBitmaskCollectable      = 1 << 3
let AAPLBitmaskEnemy            = 1 << 4
let AAPLBitmaskSuperCollectable = 1 << 5
let AAPLBitmaskWater            = 1 << 6

// Speed parameter
let CharacterSpeedFactor: SCNFloat = (2/1.3)

#if !os(iOS)
    typealias BaseViewController = NSViewController
#else
    typealias BaseViewController = UIViewController
#endif
@objc(AAPLGameViewController)
class AAPLGameViewController: BaseViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    
    weak var gameView: AAPLGameView!
    
    private let GravityAcceleration: SCNFloat = (0.18)
    private let MaxRise: SCNFloat = (0.08)
    private let MaxJump: SCNFloat = (10.0)
    
    // Nodes to manipulate the camera
    private var _cameraYHandle: SCNNode!
    private var _cameraXHandle: SCNNode!
    
    // The character
    private(set) var character: AAPLCharacter!
    
    // Simulate gravity
    private var _accelerationY: SCNFloat = 0
    
    private var _maxPenetrationDistance: CGFloat = 0
    private var _positionNeedsAdjustment: Bool = false
    private var _replacementPosition: SCNVector3 = SCNVector3()
    private var _previousUpdateTime: NSTimeInterval = 0
    
    // Game states
    private var _gameIsComplete: Bool = false
    private var _isInvincible: Bool = false
    private var _lockCamera: Bool = false
    
    private var _grassArea: SCNMaterial?
    private var _waterArea: SCNMaterial?
    private var _flames: [SCNNode] = []
    private var _enemies: [SCNNode] = []
    
    // Sounds
    private var _flameThrowerSound: SCNAudioPlayer!
    private var _collectPearlSound: SCNAudioSource!
    private var _collectFlowerSound: SCNAudioSource!
    private var _hitSound: SCNAudioSource!
    private var _pshhhSound: SCNAudioSource!
    private var _aahSound: SCNAudioSource!
    private var _victoryMusic: SCNAudioSource!
    
    // Particles
    private var _collectParticles: SCNParticleSystem!
    private var _confetti: SCNParticleSystem!
    
    // For automatic camera animation
    private var _currentGround: SCNNode?
    private var _mainGround: SCNNode!
    private var _groundToCameraPosition: NSMapTable!
    
    private func setupCamera() {
        let pov = self.gameView.pointOfView!
        
        let ALTITUDE: SCNFloat = 1.0
        let DISTANCE: SCNFloat = 10.0
        
        // We create 2 nodes to manipulate the camera:
        // The first node "_cameraXHandle" is at the center of the world (0, ALTITUDE, 0) and will only rotate on the X axis
        // The second node "_cameraYHandle" is a child of the first one and will ony rotate on the Y axis
        // The camera node is a child of the "_cameraYHandle" at a specific distance (DISTANCE).
        // So rotating _cameraYHandle and _cameraXHandle will update the camera position and the camera will always look at the center of the scene.
        
        _cameraYHandle = SCNNode()
        _cameraXHandle = SCNNode()
        _cameraYHandle.position = SCNVector3Make(0,ALTITUDE,0)
        _cameraYHandle.addChildNode(_cameraXHandle)
        self.gameView.scene!.rootNode.addChildNode(_cameraYHandle)
        
        pov.eulerAngles = SCNVector3Make(0, 0, 0)
        pov.position = SCNVector3Make(0,0,DISTANCE)
        
        _cameraYHandle.rotation = SCNVector4Make(0, 1, 0, SCNFloat(M_PI_2 + M_PI_4*3))
        _cameraXHandle.rotation = SCNVector4Make(1, 0, 0, SCNFloat(-M_PI_4*0.125))
        
        _cameraXHandle.addChildNode(pov)
        
        // Animate camera on launch and prevent the user from manipulating the camera until the end of the animation.
        _lockCamera = true
        SCNTransaction.begin()
        SCNTransaction.setCompletionBlock{
            self._lockCamera = false
        }
        
        // Create 2 additive animations that converge to 0
        // That way at the end of the animation, the camera will be at its default position.
        let cameraYAnimation = CABasicAnimation(keyPath: "rotation.w")
        cameraYAnimation.fromValue = (SCNFloat(M_PI*2) - _cameraYHandle.rotation.w)
        cameraYAnimation.toValue = 0.0
        cameraYAnimation.additive = true
        cameraYAnimation.beginTime = CACurrentMediaTime()+3; // wait a little bit before stating
        cameraYAnimation.fillMode = kCAFillModeBoth
        cameraYAnimation.duration = 5.0
        cameraYAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        _cameraYHandle.addAnimation(cameraYAnimation, forKey: nil)
        
        let cameraXAnimation = CABasicAnimation(keyPath: "rotation.w")
        cameraXAnimation.fromValue = (SCNFloat(-M_PI_2) + _cameraXHandle.rotation.w)
        cameraXAnimation.toValue = 0.0
        cameraXAnimation.additive = true
        cameraXAnimation.fillMode = kCAFillModeBoth
        cameraXAnimation.duration = 5.0
        cameraXAnimation.beginTime = CACurrentMediaTime()+3
        cameraXAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        _cameraXHandle.addAnimation(cameraXAnimation, forKey: nil)
        SCNTransaction.commit()
        
        // Add a look at constraint that will always be disable.
        // We will only progressively enable it while pinching to focus on the character.
        let lookAtConstraint = SCNLookAtConstraint(target: character.node.childNodeWithName("Bip001_Head", recursively: true)!)
        lookAtConstraint.influenceFactor = 0
        pov.constraints = [lookAtConstraint]
    }
    
    
    func panCamera(dir: CGSize) {
        guard !_lockCamera else {
            return
        }
        
        let F: SCNFloat = 0.005
        
        // Make sure the camera handles are correctly reset (because automatic camera animations may have put the "rotation" in a weird state.
        SCNTransaction.begin()
        SCNTransaction.setAnimationDuration(0.0)
        
        _cameraYHandle.removeAllActions()
        _cameraXHandle.removeAllActions()
        
        if _cameraYHandle.rotation.y < 0 {
            _cameraYHandle.rotation = SCNVector4Make(0, 1, 0, -_cameraYHandle.rotation.w)
        }
        if _cameraXHandle.rotation.x < 0 {
            _cameraXHandle.rotation = SCNVector4Make(1, 0, 0, -_cameraXHandle.rotation.w)
        }
        SCNTransaction.commit()
        
        // Update the camera position with some inertia.
        SCNTransaction.begin()
        SCNTransaction.setAnimationDuration(0.5)
        SCNTransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut))
        
        _cameraYHandle.rotation = SCNVector4Make(0, 1, 0, _cameraYHandle.rotation.y * (_cameraYHandle.rotation.w - SCNFloat(dir.width) * F))
        _cameraXHandle.rotation = SCNVector4Make(1, 0, 0, (max(SCNFloat(-M_PI_2), min(0.13, _cameraXHandle.rotation.w + SCNFloat(dir.height) * F))))
        
        SCNTransaction.commit()
    }
    
    private func setupCollisionNodes(node: SCNNode) {
        if node.geometry != nil {
            // Collision meshes must use a concave shape for intersection correctness.
            node.physicsBody = SCNPhysicsBody.staticBody()
            node.physicsBody!.categoryBitMask = AAPLBitmaskCollision
            node.physicsBody!.physicsShape = SCNPhysicsShape(node:node,  options:[SCNPhysicsShapeTypeKey : SCNPhysicsShapeTypeConcavePolyhedron])
            
            // Get grass area to play the right sound steps
            if node.geometry?.firstMaterial?.name == "grass-area" {
                if _grassArea != nil {
                    node.geometry!.firstMaterial = _grassArea
                } else {
                    _grassArea = node.geometry!.firstMaterial
                }
            }
            
            // Get the water area
            if node.geometry?.firstMaterial?.name == "water" {
                _waterArea = node.geometry!.firstMaterial
            }
            
            // Temporary workaround because concave shape created from geometry instead of node fails
            let child = SCNNode()
            node.addChildNode(child)
            child.hidden = true
            child.geometry = node.geometry
            node.geometry = nil
            node.hidden = false
            
            if node.name == "water" {
                node.physicsBody!.categoryBitMask = AAPLBitmaskWater
            }
        }
        
        for child in node.childNodes {
            if !child.hidden {
                self.setupCollisionNodes(child)
            }
        }
    }
    
    private func setupSounds() {
        // Get an arbitrary node to attach the sounds to.
        let node = self.gameView.scene!.rootNode
        
        // The wind sound.
        var source = SCNAudioSource(named: "game.scnassets/sounds/wind.m4a")!
        source.volume = 0.3
        let player = SCNAudioPlayer(source: source)
        source.loops = true
        source.shouldStream = true
        source.positional = false
        node.addAudioPlayer(player)
        
        // fire
        source = SCNAudioSource(named: "game.scnassets/sounds/flamethrower.mp3")!
        source.loops = true
        source.volume = 0
        source.positional = false
        _flameThrowerSound = SCNAudioPlayer(source: source)
        node.addAudioPlayer(_flameThrowerSound)
        
        // hit
        _hitSound = SCNAudioSource(named: "game.scnassets/sounds/ouch_firehit.mp3")!
        _hitSound.volume = 2.0
        _hitSound.load()
        
        _pshhhSound = SCNAudioSource(named: "game.scnassets/sounds/fire_extinction.mp3")!
        _pshhhSound.volume = 2.0
        _pshhhSound.load()
        
        _aahSound = SCNAudioSource(named: "game.scnassets/sounds/aah_extinction.mp3")!
        _aahSound.volume = 2.0
        _aahSound.load()
        
        // collectable
        _collectPearlSound = SCNAudioSource(named: "game.scnassets/sounds/collect1.mp3")!
        _collectPearlSound.volume = 0.5
        _collectPearlSound.load()
        _collectFlowerSound = SCNAudioSource(named: "game.scnassets/sounds/collect2.mp3")!
        _collectFlowerSound.load()
        
        // victory
        _victoryMusic = SCNAudioSource(named: "game.scnassets/sounds/Music_victory.mp3")!
        _victoryMusic.volume = 0.5
    }
    
    private func setupMusic() {
        // Get an arbitrary node to attach the sounds to.
        let node = self.gameView.scene!.rootNode
        
        let source = SCNAudioSource(named: "game.scnassets/sounds/music.m4a")!
        source.loops = true
        source.volume = 0.25
        source.shouldStream = true
        source.positional = false
        
        let player = SCNAudioPlayer(source: source)
        
        node.addAudioPlayer(player)
    }
    
    private func setupAutomaticCameraPositions() {
        let root = self.gameView.scene!.rootNode
        
        _mainGround = root.childNodeWithName("bloc05_collisionMesh_02", recursively: true)
        
        _groundToCameraPosition = NSMapTable(keyOptions: .OpaqueMemory, valueOptions: .StrongMemory)
        
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make(-0.188683, 4.719608, 0)), forKey: root.childNodeWithName("bloc04_collisionMesh_02", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make(-0.435909, 6.297167, 0)), forKey: root.childNodeWithName("bloc03_collisionMesh", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make( -0.333663, 7.868592, 0)), forKey: root.childNodeWithName("bloc07_collisionMesh", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make(-0.575011, 8.739003, 0)), forKey: root.childNodeWithName("bloc08_collisionMesh", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make( -1.095519, 9.425292, 0)), forKey: root.childNodeWithName("bloc06_collisionMesh", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make(-0.072051, 8.202264, 0)), forKey: root.childNodeWithName("bloc05_collisionMesh_02", recursively: true))
        _groundToCameraPosition.setObject(NSValue(SCNVector3: SCNVector3Make(-0.072051, 8.202264, 0)), forKey: root.childNodeWithName("bloc05_collisionMesh_01", recursively: true))
    }
    
    override func awakeFromNib() {
        #if os(iOS)
            self.gameView = (self.view as! AAPLGameView)
        #endif
        
        // Create a new scene.
        let scene = SCNScene(named: "game.scnassets/level.scn")!
        
        // Set the scene to the view and loops for the animation of the bamboos.
        self.gameView.scene = scene
        self.gameView.playing = true
        self.gameView.loops = true
        
        // Create the character
        character = AAPLCharacter()
        
        // Various setup
        self.setupCamera()
        self.setupSounds()
        self.setupMusic()
        
        //setup particles
        _collectParticles = SCNParticleSystem(named: "collect.scnp", inDirectory: "game.scnassets")
        _collectParticles.loops = false
        _confetti = SCNParticleSystem(named: "confetti.scnp", inDirectory: "game.scnassets")
        
        // Add the character to the scene.
        scene.rootNode.addChildNode(character.node)
        
        // Place it
        let sp = scene.rootNode.childNodeWithName("startingPoint", recursively: true)!
        character.node.transform = sp.transform
        
        // Setup physics masks and physics shape
        let collisionNodes = scene.rootNode.childNodesPassingTest{node, stop in
            !(node.name?.rangeOfString("collision")?.isEmpty ?? true)
        }
        
        for node in collisionNodes {
            node.hidden = false
            self.setupCollisionNodes(node)
        }
        
        // Retrieve flames and enemies
        _flames = scene.rootNode.childNodesPassingTest{node, stop in
            if node.name == "flame" {
                node.physicsBody!.categoryBitMask = AAPLBitmaskEnemy
                return true
            }
            return false
        }
        
        _enemies = scene.rootNode.childNodesPassingTest{node, stop in
            node.name == "enemy"
        }
        
        // Setup delegates
        self.gameView.scene!.physicsWorld.contactDelegate = self
        self.gameView.delegate = self
        
        //setup view overlays
        self.gameView.setup()
        
        #if ENABLE_AUTOMATIC_CAMERA
            self.setupAutomaticCameraPositions()
        #endif
    }
    
    private func updateCameraWithCurrentGround(node: SCNNode) {
        guard !_gameIsComplete else {
            return
        }
        
        guard let currentGround = _currentGround else {
            _currentGround = node
            return
        }
        
        // Automatically update the position of the camera when we move to another block.
        if node !== currentGround {
            _currentGround = node
            
            if let position = _groundToCameraPosition.objectForKey(node) as? NSValue {
                
                var p = position.SCNVector3Value
                
                if node === _mainGround && character.node.position.x < 2.5 {
                    p = SCNVector3Make(-0.098175, 3.926991, 0)
                }
                
                let actionY = SCNAction.rotateToX(0, y: CGFloat(p.y), z: 0, duration: 3.0, shortestUnitArc: true)
                actionY.timingMode = .EaseInEaseOut
                
                let actionX = SCNAction.rotateToX(CGFloat(p.x), y: 0, z: 0, duration: 3.0, shortestUnitArc: true)
                actionX.timingMode = .EaseInEaseOut
                
                _cameraYHandle.runAction(actionY)
                _cameraXHandle.runAction(actionX)
            }
        }
    }
    
    // Game loop
    func renderer(renderer: SCNSceneRenderer, updateAtTime time: NSTimeInterval) {
        // delta time since last update
        if _previousUpdateTime == 0.0 {
            _previousUpdateTime = time
        }
        
        let deltaTime = min(max(1/60.0, time - _previousUpdateTime), 1.0)
        _previousUpdateTime = time
        
        // Reset some states every frame
        _maxPenetrationDistance = 0
        _positionNeedsAdjustment = false
        
        let direction = self.gameView!.direction
        let initialPosition = character.node.position
        
        //move
        if direction.x != 0 && direction.z != 0 {
            let CharacterSpeed = (SCNFloat(deltaTime) * CharacterSpeedFactor * 0.84)
            //move character
            let position = character.node.position
            character.node.position = SCNVector3Make(position.x+direction.x*CharacterSpeed, position.y+direction.y*CharacterSpeed, position.z+direction.z*CharacterSpeed)
            
            // update orientation
            let angle = atan2(CGFloat(direction.x), CGFloat(direction.z))
            character.direction = angle
            
            character.walk = true
        } else {
            character.walk = false
        }
        
        // Update the altitude of the character
        let scene = self.gameView!.scene!
        var position = character.node.position
        var p0 = position
        var p1 = position
        p0.y -= MaxJump
        p1.y += MaxRise
        
        // Do a vertical ray intersection
        let results = scene.physicsWorld.rayTestWithSegmentFromPoint(p1, toPoint: p0, options: [SCNPhysicsTestCollisionBitMaskKey: AAPLBitmaskCollision | AAPLBitmaskWater, SCNPhysicsTestSearchModeKey : SCNPhysicsTestSearchModeClosest])
        
        var groundY: SCNFloat = -10
        
        if !results.isEmpty {
            let result = results[0]
            groundY = result.worldCoordinates.y
            
            self.updateCameraWithCurrentGround(result.node)
            
            let groundMaterial = result.node.childNodes[0].geometry!.firstMaterial
            if _grassArea === groundMaterial {
                character.floorMaterial = .Grass
            } else if _waterArea === groundMaterial {
                if character.burning {
                    character.pshhhh()
                    character.node.runAction(SCNAction.sequence([SCNAction.playAudioSource(_pshhhSound, waitForCompletion: true), SCNAction.playAudioSource(_aahSound, waitForCompletion: false)]))
                }
                
                character.floorMaterial = .Water
                
                // do a new ray test without the water to get the altitude of the ground (under the water).
                let results = scene.physicsWorld.rayTestWithSegmentFromPoint(p1, toPoint: p0, options: [SCNPhysicsTestCollisionBitMaskKey: AAPLBitmaskCollision, SCNPhysicsTestSearchModeKey : SCNPhysicsTestSearchModeClosest])
                
                let result = results[0]
                groundY = result.worldCoordinates.y
            } else {
                character.floorMaterial = .Rock
            }
            
        } else {
            // no result, we are probably out the bounds of the level -> revert the position of the character.
            character.node.position = initialPosition
            return
        }
        
        let THRESHOLD: SCNFloat = 1e-5
        if groundY < position.y - THRESHOLD {
            _accelerationY += SCNFloat(deltaTime) * GravityAcceleration; // approximation of acceleration for a delta time.
            if groundY < position.y - 0.2 {
                character.floorMaterial = .InTheAir
            }
        } else {
            _accelerationY = 0
        }
        
        position.y -= _accelerationY
        
        // reset acceleration if we touch the ground
        if groundY > position.y {
            _accelerationY = 0
            position.y = groundY
        }
        
        // Flames are static physics bodies, but they are moved by an action - So we need to tell the physics engine that the transforms did change.
        for flame in _flames {
            flame.physicsBody?.resetTransform()
        }
        
        // Adjust the volume of the enemy based on the distance with the character.
        var distanceToClosestEnemy = MAXFLOAT
        let pos3 = SCNVector3ToFloat3(character.node.position)
        for enemy in _enemies {
            //distance to enemy
            let enemyMat = enemy.worldTransform
            let enemyPos = vector_float3(Float(enemyMat.m41), Float(enemyMat.m42), Float(enemyMat.m43))
            
            let distance = vector_distance(pos3, enemyPos)
            distanceToClosestEnemy = min(distanceToClosestEnemy, distance)
        }
        
        // Adjust sounds volumes based on distance with the enemy.
        if !_gameIsComplete {
            let fireVolume = 0.3 * max(0, min(1, 1 - ((distanceToClosestEnemy - 1.2) / 1.6)))
            (_flameThrowerSound.audioNode as! AVAudioPlayerNode).volume = fireVolume //###
        }
        
        // Finally, update the position of the character.
        character.node.position = position
    }
    
    private func collectPearl(node: SCNNode) {
        if let parentNode = node.parentNode {
            let soundEmitter = SCNNode()
            soundEmitter.position = node.position
            parentNode.addChildNode(soundEmitter)
            
            soundEmitter.runAction(SCNAction.sequence([
                SCNAction.playAudioSource(_collectPearlSound, waitForCompletion: true),
                SCNAction.removeFromParentNode()]))
            
            node.removeFromParentNode()
            
            self.gameView!.didCollectAPearl()
        }
    }
    
    private func collectFlower(node: SCNNode) {
        if let parentNode = node.parentNode {
            let soundEmitter = SCNNode()
            soundEmitter.position = node.position
            parentNode.addChildNode(soundEmitter)
            
            soundEmitter.runAction(SCNAction.sequence([
                SCNAction.playAudioSource(_collectFlowerSound, waitForCompletion: true),
                SCNAction.removeFromParentNode()]))
            
            node.removeFromParentNode()
            
            // Check if game is complete.
            let gameComplete = self.gameView!.didCollectAFlower()
            
            // Emit some particles.
            var particlePosition = soundEmitter.worldTransform
            particlePosition.m42 += 0.1
            self.gameView!.scene!.addParticleSystem(_collectParticles, withTransform: particlePosition)
            
            if gameComplete {
                self.showEndScreen()
            }
        }
    }
    
    private func showEndScreen() {
        _gameIsComplete = true
        
        // Add confettis
        let particlePosition = SCNMatrix4MakeTranslation(0, 8, 0)
        self.gameView!.scene!.addParticleSystem(_confetti, withTransform: particlePosition)
        
        // Congratulation title
        let congrat = SKSpriteNode(imageNamed: "congratulations.png")
        congrat.position = CGPointMake(self.gameView.bounds.size.width/2 , self.gameView.bounds.size.height/2)
        let overlay = self.gameView!.overlaySKScene!
        congrat.xScale = 0
        congrat.yScale = 0
        congrat.alpha = 0
        congrat.runAction(SKAction.group([
            SKAction.fadeInWithDuration(0.25),
            SKAction.sequence([
                SKAction.scaleTo(0.55, duration: 0.25),
                SKAction.scaleTo(0.45, duration: 0.1)]
            )]))
        
        // Panda Image
        let congratPanda = SKSpriteNode(imageNamed: "congratulations_pandaMax.png")
        congratPanda.position = CGPointMake(self.gameView.bounds.size.width/2 , self.gameView.bounds.size.height/2 - 90)
        congratPanda.anchorPoint = CGPointMake(0.5, 0)
        congratPanda.xScale = 0
        congratPanda.yScale = 0
        congratPanda.alpha = 0
        congratPanda.runAction(SKAction.sequence([SKAction.waitForDuration(0.5), SKAction.group([
            SKAction.fadeInWithDuration(0.5),
            SKAction.sequence([
                SKAction.scaleTo(0.5, duration: 0.25),
                SKAction.scaleTo(0.4, duration: 0.1)]
            )
            ])]))
        
        overlay.addChild(congratPanda)
        overlay.addChild(congrat)
        
        // Stop the music.
        self.gameView!.scene!.rootNode.removeAllAudioPlayers()
        
        // Play the congrat sound.
        self.gameView!.scene!.rootNode.addAudioPlayer(SCNAudioPlayer(source: _victoryMusic))
        
        // Animate the camera forever
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC)), dispatch_get_main_queue()) {
            self._cameraYHandle.runAction(SCNAction.repeatActionForever(SCNAction.rotateByX(0, y: -1, z: 0, duration: 3)))
            self._cameraXHandle.runAction(SCNAction.rotateToX(CGFloat(-M_PI_4), y: 0, z: 0, duration: 5.0))
        }
    }
    
    func renderer(renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: NSTimeInterval) {
        // If we hit a wall, position needs to be adjusted
        if _positionNeedsAdjustment {
            character.node.position = _replacementPosition
        }
    }
    
    private func characterNode(capsule: SCNNode, hitWall wall: SCNNode, withContact contact: SCNPhysicsContact) {
        guard capsule.parentNode === character.node else {
            return
        }
        
        guard _maxPenetrationDistance <= contact.penetrationDistance else {
            return
        }
        
        _maxPenetrationDistance = contact.penetrationDistance
        
        var charPos = SCNVector3ToFloat3(character.node.position)
        var n = SCNVector3ToFloat3(contact.contactNormal)
        
        n *= Float(contact.penetrationDistance)
        
        n.y = 0
        charPos += n
        
        _replacementPosition = SCNVector3FromFloat3(charPos)
        _positionNeedsAdjustment = true
    }
    
    
    func physicsWorld(world: SCNPhysicsWorld, didUpdateContact contact: SCNPhysicsContact) {
        if contact.nodeA.physicsBody!.categoryBitMask == AAPLBitmaskCollision {
            self.characterNode(contact.nodeB, hitWall: contact.nodeA, withContact: contact)
        }
        if contact.nodeB.physicsBody!.categoryBitMask == AAPLBitmaskCollision {
            self.characterNode(contact.nodeA, hitWall: contact.nodeB, withContact: contact)
        }
    }
    
    private func wasHit() {
        if !_isInvincible {
            _isInvincible = true
            
            self.character.hit()
            
            self.character.node.runAction(
                SCNAction.sequence([
                    SCNAction.playAudioSource(_hitSound, waitForCompletion: false),
                    SCNAction.repeatAction(SCNAction.sequence([
                        SCNAction.fadeOpacityTo(0.01, duration: 0.1),
                        SCNAction.fadeOpacityTo(1, duration: 0.1)]),
                        count: 7),
                    SCNAction.runBlock{node in
                        self._isInvincible = false
                    }]))
        }
    }
    
    func physicsWorld(world: SCNPhysicsWorld, didBeginContact contact: SCNPhysicsContact) {
        if contact.nodeA.physicsBody!.categoryBitMask == AAPLBitmaskCollision {
            self.characterNode(contact.nodeB, hitWall: contact.nodeA, withContact: contact)
        }
        if contact.nodeB.physicsBody!.categoryBitMask == AAPLBitmaskCollision {
            self.characterNode(contact.nodeA, hitWall: contact.nodeB, withContact: contact)
        }
        if contact.nodeA.physicsBody!.categoryBitMask == AAPLBitmaskCollectable {
            self.collectPearl(contact.nodeA)
        }
        if contact.nodeB.physicsBody!.categoryBitMask == AAPLBitmaskCollectable {
            self.collectPearl(contact.nodeB)
        }
        if contact.nodeA.physicsBody!.categoryBitMask == AAPLBitmaskSuperCollectable {
            self.collectFlower(contact.nodeA)
        }
        if contact.nodeB.physicsBody!.categoryBitMask == AAPLBitmaskSuperCollectable {
            self.collectFlower(contact.nodeA)
        }
        if contact.nodeA.physicsBody!.categoryBitMask == AAPLBitmaskEnemy {
            self.wasHit()
        }
        if contact.nodeB.physicsBody!.categoryBitMask == AAPLBitmaskEnemy {
            self.wasHit()
        }
    }
    
}