//
//  AAPLCharacter.swift
//  Fox
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/1.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    This class manages the main character, including its animations, sounds and direction.
 */

import Foundation
import SceneKit

enum AAPLFloorMaterial: Int {
    case Grass
    case Rock
    case Water
    case InTheAir
    static let Count = InTheAir.rawValue + 1
}

@objc(AAPLCharacter)
class AAPLCharacter: NSObject {
    
    // Character nodes
    private(set) var node: SCNNode
    
    // Character states
    var walk: Bool = false {
        didSet {
            didSetWalk(oldValue)
        }
    }
    private(set) var burning: Bool = false
    var direction: CGFloat = 0 {
        didSet {
            disSetDirection(oldValue)
        }
    }
    var floorMaterial: AAPLFloorMaterial = .Grass
    
    
    private let StepsSoundCount = 10
    private let StepsInWaterSoundCount = 4
    
    private var _fireBirthRate: CGFloat = 0
    private var _smokeBirthRate: CGFloat = 0
    private var _whiteSmokeBirthRate: CGFloat = 0
    
    private var _fireEmitter: SCNNode
    private var _smokeEmitter: SCNNode
    private var _whiteSmokeEmitter: SCNNode
    
    private var _walkAnimation: CAAnimation!
    
    private var _steps: [[AAPLFloorMaterial: SCNAudioSource]]
    
    private func didSetWalk(oldValue: Bool) {
        if oldValue != walk {
            
            // Update node animation.
            if walk {
                node.addAnimation(_walkAnimation, forKey: "walk")
            } else {
                node.removeAnimationForKey("walk", fadeOutDuration: 0.2)
            }
        }
    }
    
    private func disSetDirection(dir: CGFloat) {
        if direction != dir {
            node.runAction(SCNAction.rotateToX(0, y: dir, z: 0, duration: 0.1, shortestUnitArc: true))
        }
    }
    
    private func playFootStep() {
        guard floorMaterial != .InTheAir else {
            return // We are in the air, no sound to play.
        }
        
        // Play a random step sound.
        let stepSoundIndex = min(StepsSoundCount-1, Int(rand() / Int32(RAND_MAX)) * StepsSoundCount)
        node.runAction(SCNAction.playAudioSource(_steps[stepSoundIndex][floorMaterial]!, waitForCompletion: false))
    }
    
    override init() {
        _steps = Array(count: StepsSoundCount, repeatedValue: [:])
        
        // Load the character.
        let characterScene = SCNScene(named: "game.scnassets/panda.scn")!
        let characterTopLevelNode = characterScene.rootNode.childNodes[0]
        node = SCNNode()
        _fireEmitter = characterTopLevelNode.childNodeWithName("fire", recursively: true)!
        _smokeEmitter = characterTopLevelNode.childNodeWithName("smoke", recursively: true)!
        _whiteSmokeEmitter = characterTopLevelNode.childNodeWithName("whiteSmoke", recursively: true)!
        super.init()
        
        // Load steps sounds.
        for i in 0..<StepsSoundCount {
            _steps[i][.Grass] = SCNAudioSource(named: "game.scnassets/sounds/Step_grass_0\(i).mp3")
            _steps[i][.Grass]!.volume = 0.5
            _steps[i][.Rock] = SCNAudioSource(named: "game.scnassets/sounds/Step_rock_0\(i).mp3")
            if i < StepsInWaterSoundCount {
                _steps[i][.Water] = SCNAudioSource(named: "game.scnassets/sounds/Step_splash_0\(i).mp3")
                _steps[i][.Water]!.load()
            } else {
                _steps[i][.Water] = _steps[i%StepsInWaterSoundCount][.Water]!
            }
            
            _steps[i][.Rock]!.load()
            _steps[i][.Grass]!.load()
        }
        
        // Create an intermediate node to manipulate the whole group at once.
        node.addChildNode(characterTopLevelNode)
        
        // Configure the "idle" animation to repeat forever.
        characterTopLevelNode.enumerateChildNodesUsingBlock{child, stop in
            for key in child.animationKeys { //for every animation keys
                let animation = child.animationForKey(key)! //get the animation
                
                animation.usesSceneTimeBase = false //make it systemTime based
                animation.repeatCount = Float.infinity //repeat forever
                
                child.addAnimation(animation, forKey: key) //replace the previous animation
            }
        }
        
        // retrieve some particle systems and save their birth rate
        _fireBirthRate = _fireEmitter.particleSystems![0].birthRate
        _fireEmitter.particleSystems![0].birthRate = 0
        _fireEmitter.hidden = false
        
        _smokeBirthRate = _smokeEmitter.particleSystems![0].birthRate
        _smokeEmitter.particleSystems![0].birthRate = 0
        _smokeEmitter.hidden = false
        
        _whiteSmokeBirthRate = _whiteSmokeEmitter.particleSystems![0].birthRate
        _whiteSmokeEmitter.particleSystems![0].birthRate = 0
        _whiteSmokeEmitter.hidden = false
        
        // Configure the physics body of the character.
        var min = SCNVector3(), max = SCNVector3()
        node.getBoundingBoxMin(&min, max: &max)
        
        let radius = CGFloat(max.x - min.x) * 0.4
        let height = CGFloat(max.y - min.y)
        
        // Create a kinematic with capsule.
        let colliderNode = SCNNode()
        colliderNode.name = "collider"
        colliderNode.position = SCNVector3Make(0, SCNFloat(height) * 0.51, 0)// a bit too high to not hit the floor
        colliderNode.physicsBody = SCNPhysicsBody(type: .Kinematic, shape: SCNPhysicsShape(geometry: SCNCapsule(capRadius: radius, height: height), options: nil))
        
        // We want contact notifications with the collectables, enemies and walls.
        colliderNode.physicsBody!.contactTestBitMask = AAPLBitmaskSuperCollectable | AAPLBitmaskCollectable | AAPLBitmaskCollision | AAPLBitmaskEnemy
        node.addChildNode(colliderNode)
        
        // Load and configure the walk animation
        _walkAnimation = self.loadAnimationFromSceneNamed("game.scnassets/walk.scn")
        _walkAnimation.usesSceneTimeBase = false
        _walkAnimation.fadeInDuration = 0.3
        _walkAnimation.fadeOutDuration = 0.3
        _walkAnimation.repeatCount = Float.infinity
        _walkAnimation.speed = Float(CharacterSpeedFactor)
        
        // Play foot steps at specific times in the animation.
        _walkAnimation.animationEvents = [
            SCNAnimationEvent(keyTime: 0.1) {animation, animatedObject, playingBackward in
                self.playFootStep()
            },
            SCNAnimationEvent(keyTime: 0.6) {animation, animatedObject, playingBackward in
                self.playFootStep()
            },
        ]
        
    }
    
    // utility to load the first found animation in a scene at the specified scene
    private func loadAnimationFromSceneNamed(path: String) -> CAAnimation? {
        let scene = SCNScene(named: path)!
        
        var animation: CAAnimation? = nil
        
        //find top level animation
        scene.rootNode.enumerateChildNodesUsingBlock{child, stop in
            if !child.animationKeys.isEmpty {
                animation = child.animationForKey(child.animationKeys[0])!
                stop.memory = true
            }
        }
        
        return animation
    }
    
    var physicsNode: SCNNode {
        return node.childNodes[0]
    }
    
    private func updateWalkSpeed(speedFactor: Float) {
        let wasWalking = walk
        
        // remove current walk animation if any.
        if wasWalking {
            self.walk = false
        }
        
        _walkAnimation.speed = Float(CharacterSpeedFactor) * speedFactor
        
        // restore walk animation if needed.
        if wasWalking {
            self.walk = true
        }
        
    }
    
    func hit() { //hit by fire!
        burning = true
        
        //start fire + smoke
        _fireEmitter.particleSystems![0].birthRate = _fireBirthRate
        _smokeEmitter.particleSystems![0].birthRate = _smokeBirthRate
        
        //walk faster
        self.updateWalkSpeed(2.3)
    }
    
    func pshhhh() { //pshhh in water :)
        if burning {
            burning = false
            
            //stop fire and smoke
            _fireEmitter.particleSystems![0].birthRate = 0
            SCNTransaction.begin()
            SCNTransaction.setAnimationDuration(1.0)
            _smokeEmitter.particleSystems![0].birthRate = 0
            SCNTransaction.commit()
            
            // start white smoke
            _whiteSmokeEmitter.particleSystems![0].birthRate = _whiteSmokeBirthRate
            
            // progressively stop white smoke
            SCNTransaction.begin()
            SCNTransaction.setAnimationDuration(5.0)
            _smokeEmitter.particleSystems![0].birthRate = 0
            SCNTransaction.commit()
            
            // walk normally
            self.updateWalkSpeed(1.0)
        }
    }
    
}