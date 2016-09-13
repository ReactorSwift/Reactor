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
}



// MARK: - Core

public class Core<StateType: State> {
    
    private var subscriptions = [Subscription<StateType>]()
    private var middlewares = [Middlewares<StateType>]()
    private (set) var state: StateType {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            DispatchQueue.main.async {
                for subscription in self.subscriptions {
                    self.publishStateChange(subscriber: subscription.subscriber, selector: subscription.selector)
                }
            }
        }
    }
    
    public init(state: StateType, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, selector: ((StateType) -> Any)? = nil) {
        guard !subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
        subscriptions.append(Subscription(subscriber: subscriber, selector: selector))
        publishStateChange(subscriber: subscriber, selector: selector)
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    private func publishStateChange(subscriber: AnySubscriber?, selector: ((StateType) -> Any)?) {
        if let selector = selector {
            subscriber?._update(with: selector(self.state))
        } else {
            subscriber?._update(with: self.state)
        }
    }
    
    // MARK: - Events
    
    public func fire(event: Event) {
        state.react(to: event)
        middlewares.forEach { $0.middleware._process(event: event, state: state) }
    }
    
    public func fire<C: Command>(command: C) where C.StateType == StateType {
        command.execute(state: state, core: self)
    }
    
}
