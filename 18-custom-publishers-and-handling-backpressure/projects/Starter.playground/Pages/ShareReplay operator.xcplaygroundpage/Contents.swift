import Foundation
import Combine

fileprivate final class ShareReplaySubscription<Output, Failure: Error>: Subscription {

    let capacity: Int
    var subscriber: AnySubscriber<Output, Failure>? = nil
    var demand: Subscribers.Demand = .none
    var buffer: [Output]
    var completion: Subscribers.Completion<Failure>? = nil
    
    
    init<S>(subscriber: S, replay: [Output], capacity: Int, completion: Subscribers.Completion<Failure>?) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        self.subscriber = AnySubscriber(subscriber)
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
        // completion will be nil if the current suibscription didn't receive a completion event at time of subscription. 
        // For such subscriptions, receive(completion:) will be called to trigger the completion.
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
    
    func receive(_ input: Output) {
        guard subscriber != nil else { return }
        buffer.append(input)
        if buffer.count > capacity {
            buffer.removeFirst()
        }
        emitAsNeeded()
    }
    
    // This method is called if the current subscription didn't receive a completion event at time of subscription.
    func receive(completion: Subscribers.Completion<Failure>) {
        guard let subscriber else { return }
        self.subscriber = nil
        // We don't set completion to nil here because we know it must already be nil, otherwise this method won't be called.
        assert(self.completion == nil)
        self.buffer.removeAll()
        subscriber.receive(completion: completion)
    }
}

extension Publishers {
    final class ShareReplay<Upstream: Publisher>: Publisher {
        typealias Output = Upstream.Output
        typealias Failure = Upstream.Failure
        
        private let lock = NSRecursiveLock()
        private let upstream: Upstream
        private let capacity: Int
        private var replay = [Output]()
        private var subscriptions = [ShareReplaySubscription<Output, Failure>]()
        private var completion: Subscribers.Completion<Failure>? = nil
        
        init(upstream: Upstream, capacity: Int) {
            self.upstream = upstream
            self.capacity = capacity
        }
        
        private func relay(_ value: Output) {
            lock.lock()
            defer { lock.unlock() }
            
            guard completion == nil else { return }
            
            // We add the value to replay as well as "$0.receive(value)".
            // replay is for new subscriptions to receive the value upon subscribing, while "$0.receive(value)" is for existing subscriptions to receive the value.
            replay.append(value)
            if replay.count > capacity {
                replay.removeFirst()
            }
            subscriptions.forEach {
                $0.receive(value)
            }
        }
        
        private func complete(_ completion: Subscribers.Completion<Failure>) {
            lock.lock()
            defer { lock.unlock() }
            self.completion = completion
            subscriptions.forEach {
                $0.receive(completion: completion)
            }
        }
        
        func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            lock.lock()
            defer { lock.unlock() }
            
            let subscription = ShareReplaySubscription(subscriber: subscriber, replay: replay, capacity: capacity, completion: completion)
            subscriptions.append(subscription)
            subscriber.receive(subscription: subscription)
            
            guard subscriptions.count == 1 else { return }
            
            let sink = AnySubscriber { subscription in
                subscription.request(.unlimited)
            } receiveValue: { [weak self] value in
                self?.relay(value)
                return .none
            } receiveCompletion: { [weak self] completion in
                self?.complete(completion)
            }

            upstream.subscribe(sink)
        }
    }
}

extension Publisher {
    func shareReplay(capacity: Int = .max) -> Publishers.ShareReplay<Self> {
        Publishers.ShareReplay(upstream: self, capacity: capacity)
    }
}

// =============== Testing ===============
var logger = TimeLogger(sinceOrigin: true)
let subject = PassthroughSubject<Int,Never>()
let publisher = subject.print("shareReplay").shareReplay(capacity: 2)
subject.send(0) // Note: This value is never emitted, because it is before the first subscriber subscribed to the shared publisher.

let subscription1 = publisher.sink(
  receiveCompletion: {
    print("subscription1 completed: \($0)", to: &logger)
  },
  receiveValue: {
    print("subscription1 received \($0)", to: &logger)
  }
)

subject.send(1)
subject.send(2)
subject.send(3)

let subscription2 = publisher.sink(
  receiveCompletion: {
    print("subscription2 completed: \($0)", to: &logger)
  },
  receiveValue: {
    print("subscription2 received \($0)", to: &logger)
  }
)

subject.send(4)
subject.send(5)
subject.send(completion: .finished)

var subscription3: Cancellable? = nil

DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
  print("Subscribing to shareReplay after upstream completed")
  subscription3 = publisher.sink(
    receiveCompletion: {
      print("subscription3 completed: \($0)", to: &logger)
    },
    receiveValue: {
      print("subscription3 received \($0)", to: &logger)
    }
  )
}

// shareReplay: receive subscription: (PassthroughSubject)
// shareReplay: request unlimited
// shareReplay: receive value: (1)
// +0.04967s: subscription1 received 1
// shareReplay: receive value: (2)
// +0.05103s: subscription1 received 2
// shareReplay: receive value: (3)
// +0.05164s: subscription1 received 3
// +0.05246s: subscription2 received 2
// +0.05250s: subscription2 received 3
// shareReplay: receive value: (4)
// +0.05277s: subscription1 received 4
// +0.05290s: subscription2 received 4
// shareReplay: receive value: (5)
// +0.05353s: subscription1 received 5
// +0.05364s: subscription2 received 5
// shareReplay: receive finished
// +0.05545s: subscription1 completed: finished
// +0.05554s: subscription2 completed: finished
// Subscribing to shareReplay after upstream completed
// +1.10883s: subscription3 received 4
// +1.10901s: subscription3 received 5
// +1.10949s: subscription3 completed: finished
