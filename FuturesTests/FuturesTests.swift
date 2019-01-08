//
//  FuturesTests.swift
//  FuturesTests
//
//  Created by Artem Shimanski on 1/8/19.
//  Copyright © 2019 Artem Shimanski. All rights reserved.
//

import XCTest
@testable import Futures

class FuturesTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test1() {
		let exp = expectation(description: "end")
		let promise = Promise<Void>()
		
		promise.future.then {
			exp.fulfill()
		}
		
		DispatchQueue.main.async {
			try! promise.fulfill(())
		}
		
		wait(for: [exp], timeout: 10)
    }
	
	func test2() {
		let exp = expectation(description: "end")
		DispatchQueue.global(qos: .background).async {
			let promise = Future<Int>(1)
			try! XCTAssertEqual(promise.get(), 1)
			exp.fulfill()
		}
		wait(for: [exp], timeout: 10)
	}


	func testSimpleFuture() {
		let promise = Future<Int>(1)
		try! XCTAssertEqual(promise.get(until: Date(timeIntervalSinceNow: 1)), 1)
	}

	func testTimeout() {
		let promise = Promise<Int>()
		do {
			let result = try promise.future.get(until: Date(timeIntervalSinceNow: 1))
			XCTAssertEqual(result, 1)
			XCTFail()
		}
		catch {
			guard case FutureError.timeout = error else {XCTFail(); return}
		}
	}
	
	func testMainThreadLock1() {
		let promise = Promise<Int>()

		DispatchQueue.global(qos: .utility).async {
			try! promise.fulfill(1)
		}
		
		try! XCTAssertEqual(promise.future.get(until: Date(timeIntervalSinceNow: 1)), 1)
		
	}

	func testMainThreadLock2() {
		let promise = Promise<Int>()
		
		DispatchQueue.main.async {
			try! promise.fulfill(1)
		}
		
		try! XCTAssertEqual(promise.future.get(until: Date(timeIntervalSinceNow: 1)), 1)
		
	}

}
