import Foundation

public protocol Event {}

public protocol State {
    mutating func handle(event: Event)
}

public protocol AnyMiddleware {
    func _handle(event: Event, state: Any)
}

public protocol Middleware: AnyMiddleware {
    associatedtype State
    func handle(event: Event, state: State)
}

extension Middleware {
    public func _handle(event: Event, state: Any) {
        if let state = state as? State {
            handle(event: event, state: state)
        }
    }
}

struct Middlewares<S: State> {
    private(set) var middleware: AnyMiddleware
}

public protocol AnySubscriber: class {
    func _update(with state: Any)
}

protocol Subscriber: AnySubscriber {
    associatedtype State
    func update(with state: State)
}

extension Subscriber {
    public func _update(with state: Any) {
        if let state = state as? State {
            update(with: state)
        }
    }
}

public struct Subscription<S: State> {
    private(set) weak var subscriber: AnySubscriber? = nil
    let selector: ((S) -> Any)?
}


public class Reactor<S: State> {
    
    /**
     An `EventEmitter` is a function that takes the state and a reference
     to the reactor and optionally returns an `Event` that will be immediately
     executed. An `EventEmitter` may also use its reactor reference to perform
     events at a later time, for example an async callback.
     */
    typealias EventEmitter = (S, Reactor<S>) -> Event?
    
    // MARK: - Properties
    
    private var subscriptions = [Subscription<S>]()
    private var middlewares = [Middlewares<S>]()
    
    
    // MARK: - State
    
    private (set) var state: S {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            DispatchQueue.main.async {
                for subscription in self.subscriptions {
                    subscription.subscriber?._update(with: self.state)
                }
            }
        }
    }
    
    public init(state: S, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, selector: ((S) -> Any)? = nil) {
        guard !subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
        subscriptions.append(Subscription(subscriber: subscriber, selector: selector))
        subscriber._update(with: state)
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    // MARK: - Events
    
    public func perform(event: Event) {
        state.handle(event: event)
        middlewares.forEach { $0.middleware._handle(event: event, state: state) }
    }
    
    public func perform(eventCreator: EventEmitter) {
        if let event = eventCreator(state, self) {
            perform(event: event)
        }
    }
    
}
