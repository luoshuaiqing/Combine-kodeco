import Foundation
import Combine

fileprivate final class ShareReplaySubscription<Output, Failure: Error>: Subscription {

    let capacity: Int
    var subscriber: AnySubscriber<Output, Failure>? = nil
    var demand: Subscribers.Demand = .none
    var buffer: [Output]
    var completion: Subscribers.Completion<Failure>? = nil
    
    
    init(subscriber: AnySubscriber<Output, Failure>, replay: [Output], capacity: Int, completion: Subscribers.Completion<Failure>?) {
        self.subscriber = subscriber
        self.buffer = replay
        self.capacity = capacity
        self.completion = completion
    }
    
    private func complete(with completion: Subscribers.Completion<Failure>) {
        guard let subscriber else { return }
        self.subscriber = nil
        self.completion = nil
        self.buffer.removeAll()
        subscriber.receive(completion: completion)
    }
    
    private func emitAsNeeded() {
        guard let subscriber else { return }
        while demand > .none && !buffer.isEmpty {
            demand -= .max(1)
            let nextDemand = subscriber.receive(buffer.removeFirst())
            if nextDemand != .none {
                self.demand += nextDemand
            }
        }
        if let completion {
            complete(with: completion)
        }
    }
    
    func request(_ demand: Subscribers.Demand) {
        if demand != .none {
            self.demand += demand
        }
        emitAsNeeded()
    }
    
    func cancel() {
        complete(with: .finished)
    }
    
    // todo: what's this?
    func receive(_ input: Output) {
        guard subscriber != nil else { return }
        buffer.append(input)
        if buffer.count > capacity {
            buffer.removeFirst()
        }
        emitAsNeeded()
    }
    
    // todo: what's this?
    func receive(completion: Subscribers.Completion<Failure>) {
        guard let subscriber else { return }
        self.subscriber = nil
        self.buffer.removeAll()
        subscriber.receive(completion: completion)
    }
}
