import Foundation
import Combine

struct DispatchTimerConfiguration {
    let queue: DispatchQueue?
    let interval: DispatchTimeInterval
    let leeway: DispatchTimeInterval
    // Max # of values the subscriber wants to receive
    let times: Subscribers.Demand
}

extension Publishers {
    struct DispatchTimer: Publisher {
        typealias Output = DispatchTime
        typealias Failure = Never
        
        let configuration: DispatchTimerConfiguration
        
        init(configuration: DispatchTimerConfiguration) {
            self.configuration = configuration
        }
        
        func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, DispatchTime == S.Input {
            let subscription = DispatchTimerSubscription(subscriber: subscriber, configuration: configuration)
            subscriber.receive(subscription: subscription)
        }
    }
}

private final class DispatchTimerSubscription<S: Subscriber>: Subscription where S.Input == DispatchTime {
    let configuration: DispatchTimerConfiguration
    var times: Subscribers.Demand
    var requested: Subscribers.Demand = .none
    var source: DispatchSourceTimer? = nil
    var subscriber: S?
    
    init(subscriber: S, configuration: DispatchTimerConfiguration) {
        self.configuration = configuration
        self.subscriber = subscriber
        self.times = configuration.times
    }
    
    func cancel() {
        source = nil
        subscriber = nil
    }
    
    func request(_ demand: Subscribers.Demand) {
        guard times > .none else {
            subscriber?.receive(completion: .finished)
            return
        }
        
        requested += demand
        if source == nil, requested > .none {
            let source = DispatchSource.makeTimerSource(queue: configuration.queue)
            source.schedule(deadline: .now() + configuration.interval, repeating: configuration.interval, leeway: configuration.leeway)
            
            source.setEventHandler { [weak self] in
                guard let self, requested > .none else { return }
                requested -= .max(1)
                times -= .max(1)
                subscriber?.receive(.now())
                if times == .none {
                    subscriber?.receive(completion: .finished)
                }
            }
            self.source = source
            source.activate()
        }
    }
}

extension Publishers {
    static func timer(queue: DispatchQueue? = nil, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), times: Subscribers.Demand = .unlimited) -> DispatchTimer {
        DispatchTimer(configuration: .init(queue: queue, interval: interval, leeway: leeway, times: times))
    }
}

var logger = TimeLogger(sinceOrigin: true)
let publisher = Publishers.timer(interval: .seconds(1), times: .max(6))
let subscription = publisher.sink { time in
    print("Timer emits: \(time)", to: &logger)
}
