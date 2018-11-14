//
//  Future.swift
//  Futures
//
//  Created by Artem Shimanski on 03.08.2018.
//  Copyright © 2018 Artem Shimanski. All rights reserved.
//

import Foundation

public enum FutureError: Error {
	case promiseAlreadySatisfied
	case timeout
}

public enum FutureState<Value> {
	case pending
	case success(Value)
	case failure(Error)
}

final public class Future<Value>: NSLocking {
	
	fileprivate(set) public var state: FutureState<Value> {
		didSet {
			condition.broadcast()
		}
	}
	
	fileprivate var condition = NSCondition()
	fileprivate var success = [(DispatchQueue?, (Value) -> Void)]()
	fileprivate var failure = [(DispatchQueue?, (Error) -> Void)]()
	fileprivate var finally = [(DispatchQueue?, () -> Void)]()
	
	public init(_ state: FutureState<Value>) {
		self.state = state
	}
	
	public convenience init(_ value: Value) {
		self.init(.success(value))
	}
	
	public func lock() {
		condition.lock()
	}
	
	public func unlock() {
		condition.unlock()
	}
	
	public func get(until: Date = .distantFuture) throws -> Value {
		if Thread.isMainThread {
			repeat {
				if let value = try tryGet() {
					return value
				}
			} while RunLoop.current.run(mode: RunLoop.current.currentMode ?? .default, before: until)
			throw FutureError.timeout
		}
		else {
			return try condition.performCritical {
				while case .pending = state, Date() < until {
					condition.wait(until: until)
				}
				switch state {
				case let .success(value):
					return value
				case let .failure(error):
					throw error
				case .pending:
					throw FutureError.timeout
				}
			}
		}
	}
	
	public func tryGet() throws -> Value? {
		return try condition.performCritical {
			switch state {
			case let .success(value):
				return value
			case let .failure(error):
				throw error
			default:
				return nil
			}
		}
	}
	
	public func wait(until: Date = .distantFuture) {
		condition.performCritical {
			while case .pending = state, Date() < until {
				condition.wait(until: until)
			}
		}
	}
	
	@discardableResult
	public func then<Result>(on queue: DispatchQueue? = nil, _ execute: @escaping (Value) throws -> Future<Result>) -> Future<Result> {
		return then(on: queue) { (value: Value, promise: Promise<Result>) in
			try execute(value).then { value in
				try! promise.fulfill(value)
			}.catch { error in
				try! promise.fail(error)
			}
		}
	}
	
	@discardableResult
	public func then<Result>(on queue: DispatchQueue? = nil, _ execute: @escaping (Value) throws -> Result) -> Future<Result> {
		return then(on: queue) { (value: Value, promise: Promise<Result>) in
			try promise.fulfill(execute(value))
		}
	}
	
	@discardableResult
	public func then<Result>(on queue: DispatchQueue? = nil, _ execute: @escaping (Value, Promise<Result>) throws -> Void) -> Future<Result> {
		
		let promise = Promise<Result>()
		
		let onSuccess = { (value: Value) in
			do {
				try execute(value, promise)
			}
			catch {
				try! promise.fail(error)
			}
		}
		
		condition.performCritical { () -> (() -> Void)? in
			switch state {
			case let .success(value):
				return {
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							onSuccess(value)
						}
					}
					else {
						onSuccess(value)
					}
				}
			case let .failure(error):
				return {
					try! promise.fail(error)
				}
			case .pending:
				success.append((queue, onSuccess))
				failure.append((queue, { error in try! promise.fail(error) }))
				return nil
			}
		}?()
		
		return promise.future
	}
	
	@discardableResult
	public func `catch`(on queue: DispatchQueue? = nil, _ execute: @escaping (Error) -> Void) -> Self {
		condition.performCritical { () -> (() -> Void)? in
			switch state {
			case let .failure(error):
				return {
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							execute(error)
						}
					}
					else {
						execute(error)
					}
				}
			case .success:
				return nil
			case .pending:
				failure.append((queue, execute))
				return nil
			}
		}?()
		return self
	}
	
	@discardableResult
	public func finally(on queue: DispatchQueue? = nil, _ execute: @escaping () -> Void) -> Self {
		
		condition.performCritical { () -> (() -> Void)? in
			switch state {
			case .success, .failure:
				return {
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							execute()
						}
					}
					else {
						execute()
					}
				}
			case .pending:
				finally.append((queue, execute))
				return nil
			}
		}?()
		return self
	}
}

extension Future where Value == Void {
	public convenience init() {
		self.init(.success(()))
	}
}

open class Promise<Value> {
	open var future = Future<Value>(.pending)
	
	public init() {}
	
	open func fulfill(_ value: Value) throws {
		try future.performCritical { () -> () -> Void in
			guard case .pending = future.state else { throw FutureError.promiseAlreadySatisfied }
			defer {
				future.success = []
				future.failure = []
				future.finally = []
			}
			
			future.state = .success(value)
			
			let execute = self.future.success
			let finally = self.future.finally
			
			return {
				execute.forEach { (queue, block) in
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							block(value)
						}
					}
					else {
						block(value)
					}
				}
				finally.forEach { (queue, block) in
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							block()
						}
					}
					else {
						block()
					}
				}
			}
		}()
	}
	
	open func fail(_ error: Error) throws {
		try future.performCritical { () -> () -> Void in
			guard case .pending = future.state else { throw FutureError.promiseAlreadySatisfied }
			defer {
				future.success = []
				future.failure = []
				future.finally = []
			}
			
			future.state = .failure(error)
			
			let execute = self.future.failure
			let finally = self.future.finally
			return {
				execute.forEach { (queue, block) in
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							block(error)
						}
					}
					else {
						block(error)
					}
				}
				finally.forEach { (queue, block) in
					if let queue = queue, queue != DispatchQueue.main || !Thread.isMainThread {
						queue.async {
							block()
						}
					}
					else {
						block()
					}
				}
			}
		}()
	}
}


extension OperationQueue {
	
	public convenience init (qos: QualityOfService, maxConcurrentOperationCount: Int = OperationQueue.defaultMaxConcurrentOperationCount) {
		self.init()
		self.qualityOfService = qos
		self.maxConcurrentOperationCount = maxConcurrentOperationCount
	}
	
	@discardableResult
	public func async<Value>(_ execute: @escaping () throws -> Value) -> Future<Value> {
		let promise = Promise<Value>()
		addOperation {
			do {
				try promise.fulfill(execute())
			}
			catch {
				try! promise.fail(error)
			}
		}
		return promise.future
	}
	
	@discardableResult
	public func async<Value>(_ execute: @escaping () throws -> Future<Value>) -> Future<Value> {
		let promise = Promise<Value>()
		addOperation {
			do {
				try execute().then { value in
					try promise.fulfill(value)
					}.catch { error in
						try! promise.fail(error)
				}
			}
			catch {
				try! promise.fail(error)
			}
		}
		return promise.future
	}
}

extension DispatchQueue {
	@discardableResult
	public func async<Value>(_ execute: @escaping () throws -> Value) -> Future<Value> {
		let promise = Promise<Value>()
		async {
			do {
				try promise.fulfill(execute())
			}
			catch {
				try! promise.fail(error)
			}
		}
		return promise.future
	}
	
	@discardableResult
	public func async<Value>(_ execute: @escaping () throws -> Future<Value>) -> Future<Value> {
		let promise = Promise<Value>()
		async {
			do {
				try execute().then { value in
					try promise.fulfill(value)
					}.catch { error in
						try! promise.fail(error)
				}
			}
			catch {
				try! promise.fail(error)
			}
		}
		return promise.future
	}
}

extension NSLocking {
	@discardableResult
	public func performCritical<T>(_ execute: () throws -> T) rethrows -> T {
		lock(); defer { unlock() }
		return try execute()
	}
}

public func all<A>(_ a: Future<A>) -> Future<A> {
	return a.then { return $0 }
}

public func all<A, B>(_ a: Future<A>, _ b: Future<B>) -> Future<(A, B)> {
	return a.then { a in
		return b.then { b in
			return (a, b)
		}
	}
}

public func all<A, B, C>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>) -> Future<(A, B, C)> {
	return a.then { a in
		return b.then { b in
			return c.then { c in
				return (a, b, c)
			}
		}
	}
}

public func all<A, B, C, D>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>) -> Future<(A, B, C, D)> {
	return a.then { a in
		return b.then { b in
			return c.then { c in
				return d.then { d in
					return (a, b, c, d)
				}
			}
		}
	}
}

public func all<A, B, C, D, E>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>, _ e: Future<E>) -> Future<(A, B, C, D, E)> {
	return a.then { a in
		return b.then { b in
			return c.then { c in
				return d.then { d in
					return e.then { e in
						return (a, b, c, d, e)
					}
				}
			}
		}
	}
}

public func all<A, B, C, D, E, F>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>, _ e: Future<E>, _ f: Future<F>) -> Future<(A, B, C, D, E, F)> {
	return a.then { a in
		return b.then { b in
			return c.then { c in
				return d.then { d in
					return e.then { e in
						return f.then { f in
							return (a, b, c, d, e, f)
						}
					}
				}
			}
		}
	}
}

public func all<S, Value>(_ futures: S) -> Future<[Value]> where S: Sequence, S.Element == Future<Value> {
	
	let promise = Promise<[Value]>()
	var values = [Value]()
	
	var pop: (() -> Void)!
	var i = futures.makeIterator()
	
	pop = {
		if let next = i.next() {
			next.then { result in
				values.append(result)
				pop()
				}.catch {error in
					try! promise.fail(error)
					pop = nil
			}
		}
		else {
			try! promise.fulfill(values)
			pop = nil
		}
	}
	pop()
	return promise.future
}

public func any<A>(_ a: Future<A>) -> Future<A?> {
	let promise = Promise<A?>()
	a.then {
		try! promise.fulfill($0)
	}.catch { _ in
		try! promise.fulfill(nil)
	}
	return promise.future
}

public func any<A, B>(_ a: Future<A>, _ b: Future<B>) -> Future<(A?, B?)> {
	var aResult: A?
	var bResult: B?
	let promise = Promise<(A?, B?)>()
	a.then { aResult = $0 }
		.finally {
			b.then { bResult = $0 }
				.finally {
					try! promise.fulfill((aResult, bResult))
			}
	}
	return promise.future
}

public func any<A, B, C>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>) -> Future<(A?, B?, C?)> {
	var aResult: A?
	var bResult: B?
	var cResult: C?
	let promise = Promise<(A?, B?, C?)>()
	a.then { aResult = $0 }
		.finally {
			b.then { bResult = $0 }
				.finally {
					c.then { cResult = $0 }
						.finally {
							try! promise.fulfill((aResult, bResult, cResult))
					}
			}
	}
	return promise.future
}

public func any<A, B, C, D>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>) -> Future<(A?, B?, C?, D?)> {
	var aResult: A?
	var bResult: B?
	var cResult: C?
	var dResult: D?
	let promise = Promise<(A?, B?, C?, D?)>()
	a.then { aResult = $0 }
		.finally {
			b.then { bResult = $0 }
				.finally {
					c.then { cResult = $0 }
						.finally {
							d.then { dResult = $0 }
								.finally {
									try! promise.fulfill((aResult, bResult, cResult, dResult))
							}
					}
			}
	}
	return promise.future
}

public func any<A, B, C, D, E>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>, _ e: Future<E>) -> Future<(A?, B?, C?, D?, E?)> {
	var aResult: A?
	var bResult: B?
	var cResult: C?
	var dResult: D?
	var eResult: E?
	let promise = Promise<(A?, B?, C?, D?, E?)>()
	a.then { aResult = $0 }
		.finally {
			b.then { bResult = $0 }
				.finally {
					c.then { cResult = $0 }
						.finally {
							d.then { dResult = $0 }
								.finally {
									e.then { eResult = $0 }
										.finally {
											try! promise.fulfill((aResult, bResult, cResult, dResult, eResult))
									}
							}
					}
			}
	}
	return promise.future
}

public func any<A, B, C, D, E, F>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, _ d: Future<D>, _ e: Future<E>, _ f: Future<F>) -> Future<(A?, B?, C?, D?, E?, F?)> {
	var aResult: A?
	var bResult: B?
	var cResult: C?
	var dResult: D?
	var eResult: E?
	var fResult: F?
	let promise = Promise<(A?, B?, C?, D?, E?, F?)>()
	a.then { aResult = $0 }
		.finally {
			b.then { bResult = $0 }
				.finally {
					c.then { cResult = $0 }
						.finally {
							d.then { dResult = $0 }
								.finally {
									e.then { eResult = $0 }
										.finally {
											f.then { fResult = $0 }
												.finally {
													try! promise.fulfill((aResult, bResult, cResult, dResult, eResult, fResult))
											}
									}
							}
					}
			}
	}
	return promise.future
}

public func any<S, Value>(_ futures: S) -> Future<[Value?]> where S: Sequence, S.Element == Future<Value> {
	let promise = Promise<[Value?]>()
	var values = [Value?]()
	
	var pop: (() -> Void)!
	var i = futures.makeIterator()
	
	pop = {
		if let next = i.next() {
			next.then { result in
				values.append(result)
				pop()
			}.catch {error in
				values.append(nil)
				pop()
			}
		}
		else {
			try! promise.fulfill(values)
			pop = nil
		}
	}
	pop()
	return promise.future
}
