import Foundation


// MARK: - State

public protocol State {
    mutating func react(to event: Event)
}


// MARK: - Events

public protocol Event {}


// MARK: - Commands

public protocol Command {
    associatedtype StateType: State
    func execute(state: StateType, core: Core<StateType>)
}


// MARK: - Middlewares

public protocol AnyMiddleware {
    func _process(event: Event, state: Any)
}

public protocol Middleware: AnyMiddleware {
    associatedtype StateType
    func process(event: Event, state: StateType)
}

extension Middleware {
    public func _process(event: Event, state: Any) {
        if let state = state as? StateType {
            process(event: event, state: state)
        }
    }
}

public struct Middlewares<StateType: State> {
    private(set) var middleware: AnyMiddleware
}


// MARK: - Subscribers

public protocol AnySubscriber: class {
    func _update(with state: Any)
}

public protocol Subscriber: AnySubscriber {
    associatedtype StateType
    func update(with state: StateType)
}

extension Subscriber {
    public func _update(with state: Any) {
        if let state = state as? StateType {
            update(with: state)
        }
    }
}

public struct Subscription<StateType: State> {
    private(set) weak var subscriber: AnySubscriber? = nil
    let selector: ((StateType) -> Any)?
    let notifyQueue: DispatchQueue

    fileprivate func notify(with state: StateType) {
        notifyQueue.async {
            if let selector = self.selector {
                self.subscriber?._update(with: selector(state))
            } else {
                self.subscriber?._update(with: state)
            }
        }
    }
}



// MARK: - Core

public class Core<StateType: State> {
    
    private let jobQueue:DispatchQueue = DispatchQueue(label: "reactor.core.queue", qos: .userInitiated, attributes: [])

    private let subscriptionsSyncQueue = DispatchQueue(label: "reactor.core.subscription.sync")
    private var _subscriptions = [Subscription<StateType>]()
    private var subscriptions: [Subscription<StateType>] {
        get {
            return subscriptionsSyncQueue.sync {
                return self._subscriptions
            }
        }
        set {
            subscriptionsSyncQueue.sync {
                self._subscriptions = newValue
            }
        }
    }

    private let middlewares: [Middlewares<StateType>]
    public private (set) var state: StateType {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            for subscription in subscriptions {
                subscription.notify(with: state)
            }
        }
    }
    
    public init(state: StateType, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, notifyOnQueue queue: DispatchQueue? = DispatchQueue.main, selector: ((StateType) -> Any)? = nil) {
        jobQueue.async {
            guard !self.subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
            let subscription = Subscription(subscriber: subscriber, selector: selector, notifyQueue: queue ?? self.jobQueue)
            self.subscriptions.append(subscription)
            subscription.notify(with: self.state)
        }
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        jobQueue.async {
            self.state.react(to: event)
            let state = self.state
            self.middlewares.forEach { $0.middleware._process(event: event, state: state) }
        }
    }
    
    public func fire<C: Command>(command: C) where C.StateType == StateType {
        jobQueue.async {
            command.execute(state: self.state, core: self)
        }
    }
    
}
