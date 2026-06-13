import XCTest
@testable import MacOSCleaner

final class CleanupStateMachineTests: XCTestCase {
    var stateMachine: CleanupStateMachine!
    
    override func setUp() {
        super.setUp()
        stateMachine = CleanupStateMachine()
    }
    
    func testInitialStateIsIdle() {
        XCTAssertEqual(stateMachine.state, .idle)
    }
    
    func testValidTransitionPath() throws {
        // idle -> scanning
        try stateMachine.transition(to: .scanning)
        XCTAssertEqual(stateMachine.state, .scanning)
        
        // scanning -> preview
        try stateMachine.transition(to: .preview)
        XCTAssertEqual(stateMachine.state, .preview)
        
        // preview -> executing
        try stateMachine.transition(to: .executing)
        XCTAssertEqual(stateMachine.state, .executing)
        
        // executing -> completed
        try stateMachine.transition(to: .completed)
        XCTAssertEqual(stateMachine.state, .completed)
    }
    
    func testInvalidTransitions() {
        // idle -> preview (invalid)
        XCTAssertThrowsError(try stateMachine.transition(to: .preview))
        
        // idle -> executing (invalid)
        XCTAssertThrowsError(try stateMachine.transition(to: .executing))
        
        // idle -> completed (invalid)
        XCTAssertThrowsError(try stateMachine.transition(to: .completed))
        
        // scanning -> idle (invalid, must use reset())
        try! stateMachine.transition(to: .scanning)
        XCTAssertThrowsError(try stateMachine.transition(to: .idle))
    }
    
    func testRescanTransitions() throws {
        // preview -> scanning (valid for rescan)
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .preview)
        try stateMachine.transition(to: .scanning)
        XCTAssertEqual(stateMachine.state, .scanning)
        
        stateMachine.reset()
        
        // completed -> scanning (valid for rescan)
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .preview)
        try stateMachine.transition(to: .executing)
        try stateMachine.transition(to: .completed)
        try stateMachine.transition(to: .scanning)
        XCTAssertEqual(stateMachine.state, .scanning)
        
        stateMachine.reset()
        
        // failed -> scanning (valid for retry)
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .failed)
        try stateMachine.transition(to: .scanning)
        XCTAssertEqual(stateMachine.state, .scanning)
        
        stateMachine.reset()
        
        // cancelled -> scanning (valid for retry)
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .cancelled)
        try stateMachine.transition(to: .scanning)
        XCTAssertEqual(stateMachine.state, .scanning)
    }
    
    func testCancellation() throws {
        // From scanning
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .cancelled)
        XCTAssertEqual(stateMachine.state, .cancelled)
        
        stateMachine.reset()
        
        // From executing
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .preview)
        try stateMachine.transition(to: .executing)
        try stateMachine.transition(to: .cancelled)
        XCTAssertEqual(stateMachine.state, .cancelled)
    }
    
    func testFailure() throws {
        try stateMachine.transition(to: .scanning)
        try stateMachine.transition(to: .failed)
        XCTAssertEqual(stateMachine.state, .failed)
    }
    
    func testReset() throws {
        try stateMachine.transition(to: .scanning)
        stateMachine.reset()
        XCTAssertEqual(stateMachine.state, .idle)
    }
}
