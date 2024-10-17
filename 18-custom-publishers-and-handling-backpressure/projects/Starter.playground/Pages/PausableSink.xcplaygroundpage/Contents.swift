import Combine
import Foundation

protocol Pausable {
    var paused: Bool { get }
    func resume()
}

final class PausableSubscriber<Input, Failure: Error>: Subscriber, Pausable, Cancellable {
    let combineIdentifier = CombineIdentifier()
    
    // true indicates that it may receive more values and false indicates the subscription should pause.
    let receiveValue: (Input) -> Bool
    let receiveCompletion: (Subscribers.Completion<Failure>) -> Void
    
    private var subscription: Subscription? = nil
    var paused = false
    
    init(receiveValue: @escaping (Input) -> Bool, receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void) {
        self.receiveValue = receiveValue
        self.receiveCompletion = receiveCompletion
    }
    
    func cancel() {
        subscription?.cancel()
        subscription = nil
    }
    
    func receive(subscription: any Subscription) {
        self.subscription = subscription
        subscription.request(.max(1))
    }
    
    func receive(_ input: Input) -> Subscribers.Demand {
        paused = receiveValue(input) == false
        return paused ? .none : .max(1)
    }
    
    func receive(completion: Subscribers.Completion<Failure>) {
        receiveCompletion(completion)
        subscription = nil
    }
    
    func resume() {
        guard paused else { return }
        paused = false
        subscription?.request(.max(1))
    }
}

extension Publisher {
    func pausableSink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void, receiveValue: @escaping (Output) -> Bool) -> Pausable & Cancellable {
        let pausable = PausableSubscriber(receiveValue: receiveValue, receiveCompletion: receiveCompletion)
        subscribe(pausable)
        return pausable
    }
}

// =============== Testing ===============
let subscription = [1, 2, 3, 4, 5, 6]
    .publisher
    .pausableSink { completion in
        print("Pausable subscription completed: \(completion)")
    } receiveValue: { value in
        print("Receive value: \(value)")
        if value % 2 == 1 {
            print("Pausing")
            return false
        }
        return true
    }

let timer = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()
    .sink { _ in
        guard subscription.paused else { return }
        print("Subscription is paused, resuming")
        subscription.resume()
    }

// Receive value: 1
// Pausing
// Subscription is paused, resuming
// Receive value: 2
// Receive value: 3
// Pausing
// Subscription is paused, resuming
// Receive value: 4
// Receive value: 5
// Pausing
// Subscription is paused, resuming
// Receive value: 6
// Pausable subscription completed: finished
