//
//  GameScene.swift
//  HexMatch
//
//  Created by Josh McKee on 1/11/16.
//  Copyright (c) 2016 Josh McKee. All rights reserved.
//

import SpriteKit
import CoreData
import SNZSpriteKitUI

class GameScene: SNZScene {
    var gameboardLayer = SKNode()
    var guiLayer = SKNode()
    
    var currentPieceLabel: SKLabelNode?
    var currentPieceHome = CGPointMake(0,0)
    var currentPieceSprite: SKSpriteNode?
    
    var stashPieceLabel: SKLabelNode?
    var stashPieceHome = CGPointMake(0,0)
    var stashBox: SKShapeNode?
    
    var resetButton: SNZButtonWidget?
    var undoButton: SNZButtonWidget?
    var gameOverLabel: SKLabelNode?
    
    var mergingPieces: [HexPiece] = Array()
    var mergedPieces: [HexPiece] = Array()

    var lastPlacedPiece: HexPiece?
    var lastPointsAwarded = 0
    
    var hexMap: HexMap?
    
    var undoState: NSData?
    
    var debugShape: SKShapeNode?
    
    let scoreFormatter = NSNumberFormatter()
    
    var _score = 0
    var score: Int {
        get {
            return self._score
        }
        set {
            self._score = newValue
            self.updateScore()
            
            // Update score in state
            GameState.instance!.score = self._score
            
            // Update high score
            if (self._score > GameState.instance!.highScore) {
                GameState.instance!.highScore = self._score
                self.updateHighScore()
            }
        }
    }
    
    var _bankPoints = 0
    var bankPoints: Int {
        get {
            return self._bankPoints
        }
        set {
            self._bankPoints = newValue
            self.updateBankPoints()
            
            // Update score in state
            GameState.instance!.bankPoints = self._bankPoints
        }
    }
    
    var scoreDisplay: SKLabelNode?
    var scoreLabel: SKLabelNode?
    
    var bankPointsDisplay: SKLabelNode?
    var bankPointsLabel: SKLabelNode?
    var bankPointBox: SKShapeNode?
    
    var highScoreDisplay: SKLabelNode?
    var highScoreLabel: SKLabelNode?
    
    override func didMoveToView(view: SKView) {        
        self.updateGuiPositions()
    }
    
    func initGame() {
        // Set background
        self.backgroundColor = UIColor(red: 0x69/255, green: 0x65/255, blue: 0x6f/255, alpha: 1.0)
        
        // Add guiLayer to scene
        addChild(self.guiLayer)
        
        // Get the hex map and render it
        self.renderFromState()
        
        // Generate proxy sprite for current piece
        self.updateCurrentPieceSprite()
        
        // Add gameboardLayer to scene
        addChild(self.gameboardLayer)
        
        // Init bank points
        self.bankPoints = GameState.instance!.bankPoints
        
        // Init guiLayer
        self.initGuiLayer()
        
        // Check to see if we are already out of open cells, and change to end game state if so
        // e.g. in case state was saved during end game.
        if (HexMapHelper.instance.hexMap!.getOpenCells().count==0) {
            GameStateMachine.instance!.enterState(GameSceneGameOverState.self)
        }
    }
    
    func renderFromState() {
        // Init HexMap
        self.hexMap = GameState.instance!.hexMap
        
        // Init score
        self._score = GameState.instance!.score
        
        // Init level
        HexMapHelper.instance.hexMap = self.hexMap!
        
        // Render our hex map to the gameboardLayer
        HexMapHelper.instance.renderHexMap(gameboardLayer);
    }
    
    /**
        Reset game state. This includes clearing current score, stashed piece, current piece, and regenerating hexmap with a new random starting layout.
    */
    func resetLevel() {
        // Remove current piece, stash piece sprites
        self.removeTransientGuiSprites()
    
        // Clear the board
        HexMapHelper.instance.clearHexMap(self.gameboardLayer)
        
        // Clear the hexmap
        self.hexMap?.clear()
        
        // Generate level
        LevelHelper.instance.initLevel(self.hexMap!)
        
        // Generate new current piece
        self.generateCurrentPiece()
        
        // Generate proxy sprite for current piece
        self.updateCurrentPieceSprite()
        
        // Reset buyables
        GameState.instance!.resetBuyablePieces()
        
        // Clear stash
        if (GameState.instance!.stashPiece != nil) {
            if (GameState.instance!.stashPiece!.sprite != nil) {
                GameState.instance!.stashPiece!.sprite!.removeFromParent()
            }
            GameState.instance!.stashPiece = nil
        }
        
        // Render game board
        HexMapHelper.instance.renderHexMap(gameboardLayer);
        
        // Reset score
        self.score = 0
        
        // Clear undo
        self.undoButton!.hidden = true
        self.undoState = nil
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        if (self.widgetTouchesBegan(touches, withEvent: event)) {
            return
        }
        
        let location = touches.first?.locationInNode(self)
        
        if (location != nil) {
            let nodes = nodesAtPoint(location!)
         
            for node in nodes {
                if (node.name == "hexMapCell") {
                    let x = node.userData!.valueForKey("hexMapPositionX") as! Int
                    let y = node.userData!.valueForKey("hexMapPositionY") as! Int
                    
                    let cell = HexMapHelper.instance.hexMap!.cell(x,y)
    
                    if (GameState.instance!.currentPiece != nil && GameState.instance!.currentPiece is RemovePiece) {
                        currentPieceSprite!.position = node.position
                    } else
                    if (cell!.willAccept(GameState.instance!.currentPiece!)) {
                        self.updateMergingPieces(cell!)
                        
                        // Move to touched point
                        currentPieceSprite!.removeActionForKey("moveAnimation")
                        currentPieceSprite!.position = node.position
                    }
                }
            }
        }
    }
    
    /**
        Handles touch move events. Updates animations for any pieces which would be merged if the player were to end the touch event in the cell being touched, if any.
    */
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        if (self.widgetTouchesMoved(touches, withEvent: event)) {
            return
        }
        
        let location = touches.first?.locationInNode(self)
        
        if (location != nil) {
            let nodes = nodesAtPoint(location!)
         
            for node in nodes {
                if (node.name == "hexMapCell") {
                    let x = node.userData!.valueForKey("hexMapPositionX") as! Int
                    let y = node.userData!.valueForKey("hexMapPositionY") as! Int
                    
                    let cell = HexMapHelper.instance.hexMap!.cell(x,y)
                    
                    if (GameState.instance!.currentPiece != nil && GameState.instance!.currentPiece is RemovePiece) {
                        currentPieceSprite!.position = node.position
                    } else
                    if (cell!.willAccept(GameState.instance!.currentPiece!)) {
                        self.updateMergingPieces(cell!)
                        
                        // Move to touched point
                        currentPieceSprite!.removeActionForKey("moveAnimation")
                        currentPieceSprite!.position = node.position
                    }
                }
            }
        }
        
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        if (self.widgetTouchesEnded(touches, withEvent: event) || touches.first == nil) {
            return
        }
        
        let location = touches.first?.locationInNode(self)
        
        if ((location != nil) && (GameStateMachine.instance!.currentState is GameScenePlayingState)) {
            for node in self.nodesAtPoint(location!) {
                if (self.nodeWasTouched(node)) {
                    break;
                }
            }
        }
    }
    
    func nodeWasTouched(node: SKNode) -> Bool {
        var handled = false
        
        if (node == self.stashBox) {
            self.swapStash()
            
            handled = true
        } else
        if (([self.scoreDisplay!,self.scoreLabel!,self.highScoreDisplay!,self.highScoreLabel!] as [SKNode]).contains(node)) {
            self.scene!.view?.presentScene(SceneHelper.instance.statsScene, transition: SKTransition.pushWithDirection(SKTransitionDirection.Right, duration: 0.4))

            handled = true
        }
        if (node == self.bankPointBox) {
            self.scene!.view?.presentScene(SceneHelper.instance.bankScene, transition: SKTransition.pushWithDirection(SKTransitionDirection.Down, duration: 0.4))

            handled = true
        } else
        if (node.name == "hexMapCell") {
            let x = node.userData!.valueForKey("hexMapPositionX") as! Int
            let y = node.userData!.valueForKey("hexMapPositionY") as! Int
            
            let cell = HexMapHelper.instance.hexMap!.cell(x,y)
            
            // Refresh merging pieces
            self.updateMergingPieces(cell!)
            
            // Do we have a Remove piece?
            if (GameState.instance!.currentPiece != nil && GameState.instance!.currentPiece is RemovePiece) {
                // Capture state for undo
                self.captureState()
                
                // Process the removal
                self.playRemovePiece(cell!)
            } else
            // Does the cell contain a collectible hex piece?
            if (cell!.hexPiece != nil && cell!.hexPiece!.isCollectible) {
                // Capture state for undo
                self.captureState()
                
                // Let the piece know it was collected
                cell!.hexPiece!.wasCollected()
                
                // Clear out the hex cell
                cell!.hexPiece = nil
            } else
            // Will the target cell accept our current piece, and will the piece either allow placement
            // without a merge, or if not, do we have a merge?
            if (cell!.willAccept(GameState.instance!.currentPiece!) && (GameState.instance!.currentPiece!.canPlaceWithoutMerge() || self.mergingPieces.count>0)) {
                // Capture state for undo
                self.captureState()
            
                // Store last placed piece, prior to any merging
                GameState.instance!.lastPlacedPiece = GameState.instance!.currentPiece

                // Place the current piece
                self.placeCurrentPiece(cell!)
            }
            
            handled = true
        }
        
        return handled
    }
    
    func handleMerge(cell: HexCell) {
        // Are we merging pieces?
        if (self.mergingPieces.count>0) {
            var maxValue = 0
            
            // Remove animations from merging pieces, and find the maximum value
            for hexPiece in self.mergingPieces {
                hexPiece.sprite!.removeActionForKey("mergeAnimation")
                hexPiece.sprite!.setScale(1.0)
                if (hexPiece.value > maxValue) {
                    maxValue = hexPiece.value
                }
            }
            
            // Let piece know it was placed w/ merge
            GameState.instance!.currentPiece = GameState.instance!.currentPiece!.wasPlacedWithMerge(maxValue)
            
            // Store merged pieces, if any
            self.mergedPieces = self.mergingPieces
            
            // Create merge animation
            let moveAction = SKAction.moveTo(HexMapHelper.instance.hexMapToScreen(cell.position), duration: 0.15)
            let moveSequence = SKAction.sequence([moveAction, SKAction.removeFromParent()])
            
            // Remove merged pieces from board
            for hexPiece in self.mergingPieces {
                hexPiece.sprite!.runAction(moveSequence)
                hexPiece.hexCell?.hexPiece = nil
            }
            
            // Play merge sound
            self.runAction(SoundHelper.instance.mergePieces)
            
        } else {
            // clear merged array, since we are not merging any on this placement
            self.mergedPieces.removeAll()
            
            // let piece know we are placing it
            GameState.instance!.currentPiece!.wasPlacedWithoutMerge()
            
            // Play placement sound
            self.runAction(SoundHelper.instance.placePiece)
        }
    }
    
    func placeCurrentPiece(cell: HexCell) {
        // Handle merging, if any
        self.handleMerge(cell)
    
        // Place the piece
        cell.hexPiece = GameState.instance!.currentPiece
        
        // Record statistic
        GameStats.instance!.incIntForKey(cell.hexPiece!.getStatsKey())
        
        // Move sprite from GUI to gameboard layer
        GameState.instance!.currentPiece!.sprite!.moveToParent(self.gameboardLayer)
        
        // Position on gameboard
        GameState.instance!.currentPiece!.sprite!.position = HexMapHelper.instance.hexMapToScreen(cell.position)
        
        // Award points
        self.awardPointsForPiece(GameState.instance!.currentPiece!)
        self.scrollPoints(self.lastPointsAwarded, position: GameState.instance!.currentPiece!.sprite!.position)
        
        // Generate new piece
        self.generateCurrentPiece()
        
        // Update current piece sprite
        self.updateCurrentPieceSprite()
        
        // End turn
        self.turnDidEnd()
    }
    
    func playRemovePiece(cell: HexCell) {
        if (cell.hexPiece != nil) {
            // Let the piece know it was collected
            cell.hexPiece!.wasRemoved()
            
            // Clear out the hex cell
            cell.hexPiece = nil
            
            // Remove sprite
            GameState.instance!.currentPiece!.sprite!.removeFromParent()
            
            // Generate new piece
            self.generateCurrentPiece()
            
            // Update current piece sprite
            self.updateCurrentPieceSprite()
            
            // End turn
            self.turnDidEnd()
        }
    }
    
    func captureState() {
        self.undoState = NSKeyedArchiver.archivedDataWithRootObject(GameState.instance!)
        
        // Show undo button
        self.undoButton!.hidden = false
    }
    
    func restoreState() {
        if (self.undoState != nil) {
            // Remove current piece, stash piece sprites
            self.removeTransientGuiSprites()
        
            // Clear piece sprites from rendered hexmap
            HexMapHelper.instance.clearHexMap(self.gameboardLayer)
            
            // Load undo state
            GameState.instance = (NSKeyedUnarchiver.unarchiveObjectWithData(self.undoState!) as? GameState)!
            
            // Get the hex map and render it
            self.renderFromState()
            
            // Restore bank points
            self.bankPoints = GameState.instance!.bankPoints
            
            // Update gui
            self.updateGuiLayer()
            
            // Clear undo state
            self.undoState = nil
        }
    }
    
    /**
        Called after player has placed a piece. Processes moves for mobile pieces, checks for end game state.
    */
    func turnDidEnd() {
        let occupiedCells = HexMapHelper.instance.hexMap!.getOccupiedCells()
        
        // Give each piece a turn
        for occupiedCell in occupiedCells {
            occupiedCell.hexPiece?.takeTurn()
        }
        
        // Look for merges resulting from hexpiece turns
        var merges = HexMapHelper.instance.getFirstMerge();
        while (merges.count>0) {
            var mergeFocus: HexPiece?
            var highestAdded = -1
            var maxValue = 0
            
            for merged in merges {
                if (merged.added > highestAdded) {
                    highestAdded = merged.added
                    mergeFocus = merged
                }
                if (merged.value > maxValue) {
                    maxValue = merged.value
                }
            }
            
            // Create merge animation
            let moveAction = SKAction.moveTo(mergeFocus!.sprite!.position, duration: 0.15)
            let moveSequence = SKAction.sequence([moveAction, SKAction.removeFromParent()])
            
            var actualMerged: [HexPiece] = Array()
            
            // Remove merged pieces from board
            for merged in merges {
                if (merged != mergeFocus) {
                    actualMerged.append(merged)
                    merged.sprite!.runAction(moveSequence)
                    merged.hexCell?.hexPiece = nil
                }
            }
            
            // add pieces which were not the merge focus to our list of pieces merged on the last turn
            self.mergedPieces += actualMerged
            
            // let merge focus know it was merged
            mergeFocus = mergeFocus!.wasPlacedWithMerge(maxValue)
            
            // Award points
            self.awardPointsForPiece(mergeFocus!)
            self.scrollPoints(self.lastPointsAwarded, position: mergeFocus!.sprite!.position)
        
            // Get next merge
            merges = HexMapHelper.instance.getFirstMerge();
        }
        
        // Stick a proxy for the current piece on to the game board in an empty cell.
        // Calling this after all other pieces have taken their turn, to avoid doubling up
        // in a cell where a mobile has recently moved in.
        self.updateCurrentPieceSprite()
            
        // Test for game over
        if (HexMapHelper.instance.hexMap!.getOpenCells().count==0) {
            GameStateMachine.instance!.enterState(GameSceneGameOverState.self)
        }
    }
    
    /**
        Rolls back the last move made. Places removed merged pieces back on the board, removes points awarded, and calls self.restoreLastPiece, which puts the last piece played back in the currentPiece property.
    */
    func undoLastMove() {
        self.restoreState()
        
        // Hide undo button
        self.undoButton!.hidden = true    
    }
   
    /**
        Stops merge animation on any current set of would-be merged pieces, then updates self.mergingPieces with any merges which would occur if self.curentPiece were to be placed in cell. Stats merge animation on the new set of merging pieces, if any.
        
        - Parameters:
            - cell: The cell to test for merging w/ the current piece
    */
    func updateMergingPieces(cell: HexCell) {
        if (cell.willAccept(GameState.instance!.currentPiece!)) {
            // Stop animation on current merge set
            for hexPiece in self.mergingPieces {
                hexPiece.sprite!.removeActionForKey("mergeAnimation")
                hexPiece.sprite!.setScale(1.0)
            }
            
            self.mergingPieces = cell.getWouldMergeWith(GameState.instance!.currentPiece!)
            
            // Start animation on new merge set
            for hexPiece in self.mergingPieces {
                hexPiece.sprite!.removeActionForKey("mergeAnimation")
                hexPiece.sprite!.setScale(1.2)
            }
        }
    }
   
    override func update(currentTime: CFTimeInterval) {
        
    }
    
    /**
        Initializes GUI layer components, sets up labels, buttons, etc.
    */
    func initGuiLayer() {
        // set up score formatter
        self.scoreFormatter.numberStyle = .DecimalStyle
    
        // Calculate current piece home position
        self.currentPieceHome = CGPoint(x: 80, y: self.frame.height - 70)
        
        // Add current piece label
        self.currentPieceLabel = self.createUILabel("Current")
        self.currentPieceLabel!.position = CGPoint(x: 20, y: self.frame.height - 40)
        self.guiLayer.addChild(self.currentPieceLabel!)
        
        // Calculate stash piece home position
        self.stashPieceHome = CGPoint(x: 180, y: self.frame.height - 70)
        
        // Add stash box
        self.stashBox = SKShapeNode(rect: CGRectMake(160, self.frame.height-90, 140, 72))
        self.stashBox!.strokeColor = UIColor.clearColor()
        self.guiLayer.addChild(self.stashBox!)
        
        // Add stash piece label
        self.stashPieceLabel = self.createUILabel("Stash")
        self.stashPieceLabel!.position = CGPoint(x: 150, y: self.frame.height - 40)
        self.guiLayer.addChild(self.stashPieceLabel!)
        
        // Add stash piece sprite, if any
        self.updateStashPieceSprite()
        
        // Add bank label
        self.bankPointsLabel = self.createUILabel("Bank Points")
        self.bankPointsLabel!.position = CGPoint(x: self.frame.width - 100, y: self.frame.height - 120)
        self.guiLayer.addChild(self.bankPointsLabel!)
        
        // Add bank display
        self.bankPointsDisplay = self.createUILabel(self.scoreFormatter.stringFromNumber(self.bankPoints)!)
        self.bankPointsDisplay!.position = CGPoint(x: self.frame.width - 100, y: self.frame.height - 144)
        self.bankPointsDisplay!.fontSize = 24
        self.guiLayer.addChild(self.bankPointsDisplay!)
        
        // Add bank point box
        self.bankPointBox = SKShapeNode(rect: CGRectMake(self.frame.width - 100, self.frame.height-90, 150, 72))
        self.bankPointBox!.strokeColor = UIColor.clearColor()
        self.guiLayer.addChild(self.bankPointBox!)
        
        // Add reset button
        self.resetButton = SNZButtonWidget(parentNode: guiLayer)
        self.resetButton!.autoSize = true
        self.resetButton!.anchorPoint = CGPointMake(0,0)
        self.resetButton!.caption = "Start Over"
        self.resetButton!.bind("tap",{
            self.scene!.view?.presentScene(SceneHelper.instance.levelScene, transition: SKTransition.pushWithDirection(SKTransitionDirection.Up, duration: 0.4))
        })
        self.addWidget(self.resetButton!)
        
        // Add undo button
        self.undoButton = SNZButtonWidget(parentNode: guiLayer)
        self.undoButton!.autoSize = true
        self.undoButton!.anchorPoint = CGPointMake(1,0)
        self.undoButton!.caption = "Undo"
        self.undoButton!.bind("tap",{
            self.undoLastMove()
        })
        self.addWidget(self.undoButton!)
        
        // Add score label
        self.scoreLabel = self.createUILabel("Score")
        self.scoreLabel!.position = CGPoint(x: 20, y: self.frame.height - 120)
        self.guiLayer.addChild(self.scoreLabel!)
        
        // Add score display
        self.scoreDisplay = self.createUILabel(self.scoreFormatter.stringFromNumber(self.score)!)
        self.scoreDisplay!.position = CGPoint(x: 20, y: self.frame.height - 144)
        self.scoreDisplay!.fontSize = 24
        self.guiLayer.addChild(self.scoreDisplay!)
        
        // Add high score label
        self.highScoreLabel = self.createUILabel("High Score")
        self.highScoreLabel!.position = CGPoint(x: 20, y: self.frame.height - 170)
        self.guiLayer.addChild(self.highScoreLabel!)
        
        // Add high score display
        self.highScoreDisplay = self.createUILabel(self.scoreFormatter.stringFromNumber(GameState.instance!.highScore)!)
        self.highScoreDisplay!.position = CGPoint(x: 20, y: self.frame.height - 194)
        self.highScoreDisplay!.fontSize = 24
        self.guiLayer.addChild(self.highScoreDisplay!)
    
        // Init the Game Over overlay
        self.initGameOver()
        
        // Set initial positions
        self.updateGuiPositions()
        
        // Set initial visibility of undo button
        self.undoButton!.hidden = (GameState.instance!.lastPlacedPiece == nil);
        
        // Render the widgets
        self.renderWidgets()
    }
    
    /**
        Updates the position of GUI elements. This gets called whem rotation changes.
    */
    func updateGuiPositions() {

        if (self.currentPieceLabel != nil) {
            // Current Piece
            self.currentPieceLabel!.position = CGPoint(x: 20, y: self.frame.height - 40)
            
            self.currentPieceHome = CGPoint(x: 60, y: self.frame.height - 70)
            
            if (GameState.instance!.currentPiece != nil && GameState.instance!.currentPiece!.sprite != nil) {
                GameState.instance!.currentPiece!.sprite!.position = self.currentPieceHome
            }
            
            // Stash
            if (self.frame.width > self.frame.height) { // landscape
                self.stashBox!.removeFromParent()
                self.stashBox = SKShapeNode(rect: CGRectMake(10, self.frame.height-150, 100, 60))
                self.stashBox!.strokeColor = UIColor.clearColor()
                self.guiLayer.addChild(self.stashBox!)
                
                self.stashPieceLabel!.position = CGPoint(x: 20, y: self.frame.height - 110)
                
                self.stashPieceHome = CGPoint(x: 60, y: self.frame.height - 140)
                if (GameState.instance!.stashPiece != nil && GameState.instance!.stashPiece!.sprite != nil) {
                    GameState.instance!.stashPiece!.sprite!.position = self.stashPieceHome
                }
            } else {
                self.stashBox!.removeFromParent()
                self.stashBox = SKShapeNode(rect: CGRectMake(120, self.frame.height-90, 100, 72))
                self.stashBox!.strokeColor = UIColor.clearColor()
                self.guiLayer.addChild(self.stashBox!)
                
                self.stashPieceLabel!.position = CGPoint(x: 140, y: self.frame.height - 40)
                
                self.stashPieceHome = CGPoint(x: 180, y: self.frame.height - 70)
                if (GameState.instance!.stashPiece != nil && GameState.instance!.stashPiece!.sprite != nil) {
                    GameState.instance!.stashPiece!.sprite!.position = self.stashPieceHome
                }
            }
            
            // bank points
            self.bankPointsLabel!.position = CGPoint(x: self.frame.width - 120, y: self.frame.height - 40)
            self.bankPointsDisplay!.position = CGPoint(x: self.frame.width - 120, y: self.frame.height - 64)
            
            self.bankPointBox!.removeFromParent()
            self.bankPointBox = SKShapeNode(rect: CGRectMake(self.frame.width - 130, self.frame.height-90, 120, 72))
            self.bankPointBox!.strokeColor = UIColor.clearColor()
            self.guiLayer.addChild(self.bankPointBox!)
            
            // Score
            if (self.frame.width > self.frame.height) { // landscape
                self.scoreLabel!.position = CGPoint(x: 20, y: self.frame.height - 180)
                self.scoreDisplay!.position = CGPoint(x: 20, y: self.frame.height - 204)
                
                self.highScoreLabel!.position = CGPoint(x: 20, y: self.frame.height - 230)
                self.highScoreDisplay!.position = CGPoint(x: 20, y: self.frame.height - 254)
            } else {
                self.scoreLabel!.position = CGPoint(x: 20, y: self.frame.height - 120)
                self.scoreDisplay!.position = CGPoint(x: 20, y: self.frame.height - 144)
            
                self.highScoreLabel!.position = CGPoint(x: self.frame.width-150, y: self.frame.height - 120)
                self.highScoreDisplay!.position = CGPoint(x: self.frame.width-150, y: self.frame.height - 144)
            }
                        
            // Gameboard
            self.updateGameboardLayerPosition()
            
            // Widgets
            self.updateWidgets()
        }
    }
    
    func updateGameboardLayerPosition() {
        if (HexMapHelper.instance.hexMap != nil) {
            var scale: CGFloat = 1.0
            var shiftY: CGFloat = 0
            
            let marginPortrait: CGFloat = 90
            let marginLandscape: CGFloat = 60
            
            
            let gameboardWidth = HexMapHelper.instance.getRenderedWidth()
            let gameboardHeight = HexMapHelper.instance.getRenderedHeight()
            
            // Calculate scaling factor to make gameboard fit screen
            if (self.frame.width > self.frame.height) { // landscape
                scale = self.frame.height / (gameboardHeight + marginLandscape)
            } else { // portrait
                scale = self.frame.width / (gameboardWidth + marginPortrait)
                
                shiftY = 30 // shift down a little bit if we are in portrait, so that we don't overlap UI elements.
            }
            
            // Scale gameboard layer
            self.gameboardLayer.setScale(scale)
            
            // Reposition gameboard layer to center in view
            self.gameboardLayer.position = CGPointMake(((self.frame.width) - (gameboardWidth * scale))/2, (((self.frame.height) - (gameboardHeight * scale))/2) - shiftY)
        }
    }
    
    /**
        Helper function to create an instance of SKLabelNode with typical defaults for our GUI and a specified caption.
        
        - Parameters:
            - caption: The caption for the label node
            
        - Returns: An instance of SKLabelNode, initialized with caption and gui defaults.
    */
    func createUILabel(caption: String) -> SKLabelNode {
        let label = SKLabelNode(text: caption)
        label.fontColor = UIColor(red: 0xf7/255, green: 0xef/255, blue: 0xed/255, alpha: 1.0)
        label.fontSize = 18
        label.zPosition = 20
        label.fontName = "Avenir-Black"
        label.horizontalAlignmentMode = SKLabelHorizontalAlignmentMode.Left

        return label
    }
    
    func removeTransientGuiSprites() {
        if (GameState.instance!.stashPiece != nil) {
            if (GameState.instance!.stashPiece!.sprite != nil) {
                GameState.instance!.stashPiece!.sprite!.removeFromParent()
            }
        }
        
        if (GameState.instance!.currentPiece != nil) {
            if (GameState.instance!.currentPiece!.sprite != nil) {
                GameState.instance!.currentPiece!.sprite!.removeFromParent()
            }
        }
    }
    
    func updateGuiLayer() {
        self.updateStashPieceSprite()
        self.updateScore()
        self.updateHighScore()
        self.updateCurrentPieceSprite()
    }
    
    func updateStashPieceSprite() {
        if (GameState.instance!.stashPiece != nil) {
            if (GameState.instance!.stashPiece!.sprite == nil) {
                GameState.instance!.stashPiece!.sprite = GameState.instance!.stashPiece!.createSprite()
                GameState.instance!.stashPiece!.sprite!.position = self.stashPieceHome
                self.guiLayer.addChild(GameState.instance!.stashPiece!.sprite!)
            } else {
                GameState.instance!.stashPiece!.sprite!.removeFromParent()
                GameState.instance!.stashPiece!.sprite = GameState.instance!.stashPiece!.createSprite()
                GameState.instance!.stashPiece!.sprite!.position = self.stashPieceHome
                self.guiLayer.addChild(GameState.instance!.stashPiece!.sprite!)
            }
        }
    }
    
    /**
        Refreshes the text of the score display with a formatted copy of the current self.score value
    */
    func updateScore() {
        if (self.scoreDisplay != nil) {
            self.scoreDisplay!.text = self.scoreFormatter.stringFromNumber(self.score)
        }
    }
    
    func updateBankPoints() {
        if (self.bankPointsDisplay != nil) {
            self.bankPointsDisplay!.text = self.scoreFormatter.stringFromNumber(self.bankPoints)
        }
    }
    
    /**
        Refreshes the text of the high score display with a formatted copy of the current high score value
    */
    func updateHighScore() {
        if (self.highScoreDisplay != nil) {
            self.highScoreDisplay!.text = self.scoreFormatter.stringFromNumber(GameState.instance!.highScore)
        }
    }
    
    func scrollPoints(points: Int, position: CGPoint) {
        if (points > 0) {
            let scrollUp = SKAction.moveByX(0, y: 100, duration: 1.0)
            let fadeOut = SKAction.fadeAlphaTo(0, duration: 1.0)
            let remove = SKAction.removeFromParent()
            
            let scrollFade = SKAction.sequence([SKAction.group([scrollUp, fadeOut]),remove])
            
            let pointString:String = self.scoreFormatter.stringFromNumber(points)!
            
            let label = SKLabelNode(text: pointString)
            label.fontColor = UIColor.whiteColor()
            label.fontSize = CGFloat(18 + pointString.characters.count)
            label.zPosition = 30
            label.position = position
            label.fontName = "Avenir-Black"
            self.gameboardLayer.addChild(label)
            
            label.runAction(scrollFade)
        }
    }
    
    func scaleToFitRect(node:SKLabelNode, rect:CGRect) {
        node.fontSize *= min(rect.width / node.frame.width, rect.height / node.frame.height)
    }
    
    func burstMessage(message: String) {
        
        let tokens = message.componentsSeparatedByString("\n").reverse()
        
        var totalHeight:CGFloat = 0
        let padding:CGFloat = 20
        
        var labels: [SKLabelNode] = Array()
        
        for token in tokens {
            let label = SKLabelNode(text: token)
            label.fontColor = UIColor.whiteColor()
            label.zPosition = 500
            label.fontName = "Avenir-Black"
            label.fontSize = 20
            
            self.scaleToFitRect(label, rect: CGRectInset(self.frame, 30, 30))
            
            totalHeight += label.frame.height + padding
            
            label.position = CGPointMake(self.frame.width / 2, (self.frame.height / 2))
            
            labels.append(label)
        }
        
        let burstAnimation = SKAction.sequence([
            SKAction.scaleTo(1.2, duration: 0.4),
            SKAction.scaleTo(0.8, duration: 0.2),
            SKAction.scaleTo(1.0, duration: 0.2),
            SKAction.waitForDuration(1.5),
            SKAction.group([
                SKAction.scaleTo(5.0, duration: 1.0),
                SKAction.fadeOutWithDuration(1.0)
            ])
        ])
        
        var verticalOffset:CGFloat = 0
        
        for label in labels {
            label.position.y = (self.frame.height / 2) - (totalHeight / 2) + (label.frame.height / 2) + verticalOffset
        
            verticalOffset += padding + label.frame.height
        
            label.setScale(0)
            SceneHelper.instance.gameScene.addChild(label)
            label.runAction(burstAnimation)
        }
    }

    
    func initGameOver() {
        let label = SKLabelNode(text: "GAME OVER")
        label.fontColor = UIColor.blackColor()
        label.fontSize = 64
        label.zPosition = 20
        label.fontName = "Avenir-Black"
        label.horizontalAlignmentMode = SKLabelHorizontalAlignmentMode.Center
        
        label.position = CGPoint(x: self.frame.width / 2, y: self.frame.height / 2)
        
        self.gameOverLabel = label;
    }
    
    func showGameOver() {
        self.burstMessage("NO MOVES REMAINING\nGAME OVER")
    
        // Disable Undo
        self.undoButton!.hidden = true
        self.undoState = nil
    
        self.runAction(SKAction.sequence([SKAction.waitForDuration(2.0),SKAction.runBlock({
             // Show Game Over text
            self.guiLayer.addChild(self.gameOverLabel!)
        })]))
    }
    
    
    func hideGameOver() {
        self.gameOverLabel!.removeFromParent()
    }
    
    /**
        Generates a point value and applies it to self.score, based on the piece specified.
        
        - Parameters:
            - hexPiece: The piece for which points are being awarded.
    */
    func awardPointsForPiece(hexPiece: HexPiece) {
        var modifier = self.mergingPieces.count-1
        
        if (modifier < 1) {
            modifier = 1
        }
        
        self.awardPoints(hexPiece.getPointValue() * modifier)
    }
    
    func awardPoints(points: Int) {
        self.lastPointsAwarded = points
        self.score += lastPointsAwarded
        
        // Bank 5%
        self.bankPoints += Int(Double(points) * 0.05)
        
        self.checkForUnlocks()
    }
    
    func checkForUnlocks() {
        if (LevelHelper.instance.mode == .Hexagon && !GameState.instance!.unlockedLevels.contains(.Pit) && self.score >= 500000) {
            GameState.instance!.unlockedLevels.append(.Pit)
            
            self.burstMessage("New Map Unlocked\nTHE PIT")
        }
        
        if (LevelHelper.instance.mode == .Pit && !GameState.instance!.unlockedLevels.contains(.Moat) && self.score >= 1000000) {
            GameState.instance!.unlockedLevels.append(.Moat)
            
            self.burstMessage("New Map Unlocked\nTHE MOAT")
        }
    }
    
    /**
        Generates a random piece and assigns it to GameState.instance!.currentPiece. This is the piece which will be placed if the player
        touches a valid cell on the gameboard.
    */
    func generateCurrentPiece() {
        GameState.instance!.currentPiece = LevelHelper.instance.getRandomPiece()
    }
    
    func setCurrentPiece(hexPiece: HexPiece) {
        if (GameState.instance!.currentPiece!.sprite != nil) {
            GameState.instance!.currentPiece!.sprite!.removeFromParent()
        }
        
        GameState.instance!.currentPiece = hexPiece
        self.updateCurrentPieceSprite()
    }
    
    func spendBankPoints(points: Int) {
        self.bankPoints -= points
    }
    
    func updateCurrentPieceSprite(relocate: Bool = true) {
        var position: CGPoint?
    
        if (GameState.instance!.currentPiece != nil) {
            if (!relocate) {
                position = self.currentPieceSprite!.position
            }
            
            // Sprite to go in the GUI
            
            if (GameState.instance!.currentPiece!.sprite != nil) {
                GameState.instance!.currentPiece!.sprite!.removeFromParent()
            }
            
            GameState.instance!.currentPiece!.sprite = GameState.instance!.currentPiece!.createSprite()
            
            GameState.instance!.currentPiece!.sprite!.position = self.currentPieceHome
            GameState.instance!.currentPiece!.sprite!.zPosition = 10
            guiLayer.addChild(GameState.instance!.currentPiece!.sprite!)
        
            // Sprite to go on the game board
            if (self.currentPieceSprite != nil) {
                self.currentPieceSprite!.removeFromParent()
            }
            
            // Create sprite
            self.currentPieceSprite = GameState.instance!.currentPiece!.createSprite()
            
            // fix z position
            self.currentPieceSprite!.zPosition = 999
            
            // Pulsate
            self.currentPieceSprite!.runAction(SKAction.repeatActionForever(SKAction.sequence([
                SKAction.scaleTo(1.4, duration: 0.4),
                SKAction.scaleTo(0.8, duration: 0.4)
            ])))
            
            if (relocate || position == nil) {
                var targetCell: HexCell?
                
                // Either use last placed piece, or center of game board, for target position
                if (GameState.instance!.lastPlacedPiece != nil && GameState.instance!.lastPlacedPiece!.hexCell != nil) {
                    targetCell = GameState.instance!.lastPlacedPiece!.hexCell!
                } else {
                    targetCell = HexMapHelper.instance.hexMap!.cell(Int(HexMapHelper.instance.hexMap!.width/2), Int(HexMapHelper.instance.hexMap!.height/2))!
                }
                
                // Get a random open cell near the target position
                let boardCell = HexMapHelper.instance.hexMap!.getRandomCellNear(targetCell!)
            
                // Get cell position
                if (boardCell != nil) {
                    position = HexMapHelper.instance.hexMapToScreen(boardCell!.position)
                }
            }

            // Position sprite
            if (position != nil) { // position will be nil if board is full
                self.currentPieceSprite!.position = position!
                self.gameboardLayer.addChild(self.currentPieceSprite!)
            }
        }
    }
    
    /**
        Swaps GameState.instance!.currentPiece with the piece currently in the stash, if any. If no piece is in the stash, a new currentPiece is geneated and the old currentPiece is placed in the stash.
    */
    func swapStash() {
        if (GameState.instance!.stashPiece != nil) {
            let tempPiece = GameState.instance!.currentPiece!
            
            GameState.instance!.currentPiece = GameState.instance!.stashPiece
            GameState.instance!.stashPiece = tempPiece
            
            GameState.instance!.currentPiece!.sprite!.runAction(SKAction.moveTo(self.currentPieceHome, duration: 0.1))
            GameState.instance!.stashPiece!.sprite!.runAction(SKAction.sequence([SKAction.moveTo(self.stashPieceHome, duration: 0.1),SKAction.runBlock({
                self.updateCurrentPieceSprite(false)
            })]))
        } else {
            GameState.instance!.stashPiece = GameState.instance!.currentPiece
            GameState.instance!.stashPiece!.sprite!.runAction(SKAction.sequence([SKAction.moveTo(self.stashPieceHome, duration: 0.1),SKAction.runBlock({
                self.generateCurrentPiece()
                self.updateCurrentPieceSprite(false)
            })]))
            self.generateCurrentPiece()
        }
    }
}