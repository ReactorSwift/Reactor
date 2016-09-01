import Foundation

public protocol Event {}

public protocol State {
    mutating func react(to event: Event)
}

public protocol AnyMiddleware {
    func _process(event: Event, state: Any)
}

public protocol Middleware: AnyMiddleware {
    associatedtype State
    func process(event: Event, state: State)
}

extension Middleware {
    public func _process(event: Event, state: Any) {
        if let state = state as? State {
            process(event: event, state: state)
        }
    }
}

public struct Middlewares<ReactorState: State> {
    private(set) var middleware: AnyMiddleware
}

public protocol AnySubscriber: class {
    func _update(with state: Any)
}

public protocol Subscriber: AnySubscriber {
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

public struct Subscription<ReactorState: State> {
    private(set) weak var subscriber: AnySubscriber? = nil
    let selector: ((ReactorState) -> Any)?
}


public class Reactor<ReactorState: State> {
    
    /**
     An `EventEmitter` is a function that takes the state and a reference
     to the reactor and optionally returns an `Event` that will be immediately
     executed. An `EventEmitter` may also use its reactor reference to perform
     events at a later time, for example an async callback.
     */
    public typealias EventEmitter = (ReactorState, Reactor<ReactorState>) -> Event?
    
    // MARK: - Properties
    
    private var subscriptions = [Subscription<ReactorState>]()
    private var middlewares = [Middlewares<ReactorState>]()
    
    
    // MARK: - State
    
    private (set) var state: ReactorState {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            DispatchQueue.main.async {
                for subscription in self.subscriptions {
                    subscription.subscriber?._update(with: self.state)
                }
            }
        }
    }
    
    public init(state: ReactorState, middlewares: [AnyMiddleware] = []) {
        self.state = state
        self.middlewares = middlewares.map(Middlewares.init)
    }
    
    
    // MARK: - Subscriptions
    
    public func add(subscriber: AnySubscriber, selector: ((ReactorState) -> Any)? = nil) {
        guard !subscriptions.contains(where: {$0.subscriber === subscriber}) else { return }
        subscriptions.append(Subscription(subscriber: subscriber, selector: selector))
        subscriber._update(with: state)
    }
    
    public func remove(subscriber: AnySubscriber) {
        subscriptions = subscriptions.filter { $0.subscriber !== subscriber }
    }
    
    // MARK: - Events
    
    public func perform(event: Event) {
        state.react(to: event)
        middlewares.forEach { $0.middleware._process(event: event, state: state) }
    }
    
    public func perform(emitter: EventEmitter) {
        if let event = emitter(state, self) {
            perform(event: event)
        }
    }
    
}
