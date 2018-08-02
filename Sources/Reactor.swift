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
        if Thread.isMainThread {
            finishNotify(with: state)
        } else {
            notifyQueue.async {
                self.finishNotify(with: state)
            }
        }
    }
    
    fileprivate func finishNotify(with state: StateType) {
        if let selector = self.selector {
            self.subscriber?._update(with: selector(state))
        } else {
            self.subscriber?._update(with: state)
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
        if Thread.isMainThread {
            finishAdd(subscriber: subscriber, notifyQueue: queue, selector: selector)
        } else {
            jobQueue.async {
                self.finishAdd(subscriber: subscriber, notifyQueue: queue, selector: selector)
            }
        }
    }
    
    private func finishAdd(subscriber: AnySubscriber, notifyQueue: DispatchQueue?, selector: ((StateType) -> Any)?) {
        guard !subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
        let subscription = Subscription(subscriber: subscriber, selector: selector, notifyQueue: notifyQueue ?? jobQueue)
        subscriptions.append(subscription)
        subscription.notify(with: state)
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        if Thread.isMainThread {
            finishFire(event: event)
        } else {
            jobQueue.async {
                self.finishFire(event: event)
            }
        }
    }
    
    private func finishFire(event: Event) {
        self.state.react(to: event)
        let state = self.state
        middlewares.forEach { $0.middleware._process(event: event, state: state) }
    }
    
    public func fire<C: Command>(command: C) where C.StateType == StateType {
        if Thread.isMainThread {
            finishFire(command: command)
        } else {
            jobQueue.async {
                self.finishFire(command: command)
            }
        }
    }
    
    private func finishFire<C: Command>(command: C) where C.StateType == StateType {
        command.execute(state: state, core: self)
    }
    
}
