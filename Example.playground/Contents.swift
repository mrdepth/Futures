//: Playground - noun: a place where people can play

import UIKit
import Futures

DispatchQueue.global(qos: .background).async {
	return try String(contentsOf: URL(string: "https://google.com")!)
}.then { result in
	print(result)
}.wait()


let promise = Promise<Int>()
DispatchQueue.global(qos: .background).async {
	try! promise.fulfill(10)
}
try! promise.future.get()
