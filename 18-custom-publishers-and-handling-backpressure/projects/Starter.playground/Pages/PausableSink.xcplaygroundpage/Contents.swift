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
