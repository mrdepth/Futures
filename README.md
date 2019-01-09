# Futures
The library provides facilities to obtain values that are returned and to catch exceptions that are thrown by asynchronous tasks.

## Requirements
- iOS 9.0+
- Swift 4.2

## Usage

### Sample 1
```swift
DispatchQueue.global(qos: .background).async {
	return try String(contentsOf: URL(string: "https://google.com")!)
}.then { result in
	print(result)
}.catch {error in
	print(error)
}.finally {
	//executes after 'then' and 'catch'
}
```
			
### Sample 2
```swift
func doSomeWork() -> Future<Int> {
	let promise = Promise<Int>()
	DispatchQueue.global(qos: .background).async {
		try! promise.fulfill(10)
	}
	return promise.future
}

doSomeWork().then { result in
	print(result)
}
```
			
### Sample 3
```swift
DispatchQueue.global(qos: .utility).async {
	return 1
}.then { result in
	return result + 1
}.then { result in
	//Future<Future<T>> will be unwrapped to Future<T>
	return DispatchQueue.global(qos: .utility).async {
		return result + 1
	}
}.then { result in
	print(result)
}
```
